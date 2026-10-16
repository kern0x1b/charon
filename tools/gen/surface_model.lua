-- The surface of the SDK, computed from the model: every framework's committed declaration shard (spec/<F>/declarations.tsv, ObjC
-- and C) and Swift shard (spec/<F>/swift.tsv), read through the same readers the generator uses. A row is in the surface when its
-- introduction on iOS is after 6.1, with the columns the surface table has (framework, kind, lang, api, introduced, deprecated,
-- obsoleted, unavailable, via, getter). via says where the introduction came from, as sdk-introduced.py wrote it: `own` (the
-- declaration's own availability), `container` (the class, protocol, enum or type it sits in: a member with none of its own), and
-- `class-floor` (an ObjC category member: the class it extends, a floor). A nested framework's shards (spec/<Outer>/<Inner>) are the
-- rows of its outer framework, as the ledgers and the table name them. The rows come out sorted as the table is.
-- surface.lua reads these rows where it read the corpus table; the scope, the trace layer and the docs keep their logic.

local layout = import("layout", {anonymous = true})
local headers = import("headers", {anonymous = true})
local files = import("files", {anonymous = true})
local order = import("order", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local decl = import("decl", {anonymous = true})

-- The release the surface starts after: a row is in the surface when its iOS introduction is later than this.
local AFTER = "6.1"
local NO_VALUE = "-"
local SWIFT_SHARD_FILE = "swift.tsv"
local SWIFT_PREFIX = "swift-"
-- The surface kind of each ObjC declaration kind the shard holds. An enum constant is a constant of its enum, as the table has it. A
-- row of any other kind (a category, a super, a field, a typedef) is in no surface.
local OBJC_KINDS = {interface = "class", protocol = "protocol", method = "method", property = "property", var = "constant",
                    enumconst = "constant", ["function"] = "function", enum = "enum", struct = "struct"}
-- The surface kinds a Swift shard row can have (swift_shard.lua's surface_kind, without the accessors it leaves out).
local SWIFT_KINDS = {class = true, struct = true, enum = true, protocol = true, typealias = true, method = true, property = true,
                     constant = true, ["function"] = true}
-- The columns of a surface row, in the order the surface table writes them.
local COLUMNS = {"framework", "kind", "lang", "api", "introduced", "deprecated", "obsoleted", "unavailable", "via", "getter"}

-- The shard readers of the foundation (tools/found), imported from the tree being read, as headers.lua does.
local function found(tree, name)
    return import("found." .. name, {rootdir = path.join(tree, "tools"), anonymous = true})
end

-- The shard folders of the tree, nested ones included ("Outer/Inner"), in byte order: each a folder with a declaration shard or a Swift
-- shard. A folder with a Swift shard only is one too.
function shard_folders(tree)
    local root = path.join(tree, layout.constants().SNAP_ROOT)
    local seen, names = {}, {}
    for _, pattern in ipairs({"*", "*/*"}) do
        for _, file in ipairs({layout.constants().SHARD_FILE, SWIFT_SHARD_FILE}) do
            for _, filepath in ipairs(files.glob(path.join(root, pattern, file))) do
                local fw = path.relative(path.directory(filepath), root)
                if not seen[fw] then
                    seen[fw] = true
                    table.insert(names, fw)
                end
            end
        end
    end
    table.sort(names, order.less)
    return names
end

-- The surface framework a shard folder's rows belong to: its outermost folder (MetalPerformanceShaders/MPSCore is
-- MetalPerformanceShaders), which is the name the ledgers give the framework.
local function surface_name(fw)
    return string.match(fw, "^[^/]+")
end

-- The surface frameworks of the tree, in byte order: the outermost folder of every shard folder, each once.
function frameworks(tree)
    local seen, names = {}, {}
    for _, fw in ipairs(shard_folders(tree)) do
        local name = surface_name(fw)
        if not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    table.sort(names, order.less)
    return names
end

-- The ObjC record of one declaration row of a framework's shard, or nil when the row is not a surface kind. The record carries the
-- row's own iOS availability; a member carries its owner class and whether it sits in a category; a constant carries the enum it sits
-- in (its container), when it has one.
local function objc_record(fw, r, shard, avail)
    local kind = OBJC_KINDS[r.kind]
    if kind == nil then
        return nil
    end
    if r.kind == "var" and not string.match(r.usr, "^c:[^@]*@[^@]+$") then
        return nil
    end
    local name = shard.decode(r.kind, r.usr, r.name or "", r.side or "")
    local container = r.container or NO_VALUE
    local api, owner
    if kind == "method" or kind == "property" then
        owner = string.match(r.usr, "^c:objc%(%a+%)([^%(]+)%(")
        if owner == nil then
            return nil
        end
        if kind == "method" then
            local sign = string.find(r.usr, "(cm)", 1, true) and "+" or "-"
            api = sign .. "[" .. owner .. " " .. name .. "]"
        else
            api = owner .. "." .. name
        end
    elseif kind == "function" then
        api = name .. "()"
    else
        api = name
    end
    local parsed = avail.parse_availability(r.availability or NO_VALUE)
    local ios = parsed.entries.ios
    local intro = ios and ios.intro ~= NO_VALUE and ios.intro or nil
    local dep = ios and ios.dep ~= NO_VALUE and ios.dep or nil
    local obs = ios and ios.obs ~= NO_VALUE and ios.obs or nil
    if dep == nil and parsed.always_deprecated then
        dep = "yes"
    end
    local unavailable = (ios and ios.unavailable) or parsed.always_unavailable
    local getter = NO_VALUE
    if kind == "property" then
        local value = decl.attribute_value(r.attrs, "getter")
        if value and value ~= name then
            getter = value
        end
    end
    local category = owner ~= nil and container ~= NO_VALUE and container ~= ""
    return {framework = fw, kind = kind, lang = "objc", api = api, owner = owner, container = container, category = category,
            introduced = intro, deprecated = dep or NO_VALUE, obsoleted = obs or NO_VALUE,
            unavailable = unavailable and "yes" or "", getter = getter, via = intro and "own" or "none"}
end

-- The Swift record of one row of a framework's Swift shard, or nil when the row is not a surface kind. The api is the shard's name as
-- the digester gives it (the container, a dot, the name; an operator's labels are the digester's `_:` form); the availability cell
-- holds the platform introductions only.
local function swift_record(fw, r)
    local kind = string.sub(r.kind or "", #SWIFT_PREFIX + 1)
    if not SWIFT_KINDS[kind] then
        return nil
    end
    local container = r.container or NO_VALUE
    local api = container ~= NO_VALUE and (container .. "." .. r.name) or r.name
    local intro = string.match(r.availability or NO_VALUE, "ios=([^,]+)")
    return {framework = fw, kind = kind, lang = "swift", api = api, container = container,
            introduced = intro, deprecated = NO_VALUE, obsoleted = NO_VALUE, unavailable = "", getter = NO_VALUE,
            via = intro and "own" or "none"}
end

-- The records of every surface framework, read once: framework -> the records of its shards (a nested folder's in the outer
-- framework's list), in the shards' order.
local function records(tree, avail)
    local shard = found(tree, "shard")
    local out = {}
    for _, fw in ipairs(frameworks(tree)) do
        out[fw] = {}
    end
    for _, folder in ipairs(shard_folders(tree)) do
        local name = surface_name(folder)
        local list = out[name]
        for _, r in ipairs(headers.shard_records(tree, folder)) do
            local record = objc_record(name, r, shard, avail)
            if record then
                table.insert(list, record)
            end
        end
        local text = files.read_text(path.join(tree, layout.constants().SNAP_ROOT, folder, SWIFT_SHARD_FILE))
        if text then
            for _, r in ipairs(tsv.records(text)) do
                local record = swift_record(name, r)
                if record then
                    table.insert(list, record)
                end
            end
        end
    end
    return out
end

-- The class floor of the ObjC categories: class or protocol name -> the earliest introduction of its own rows, whatever the framework
-- (a category may sit in another framework than its class, as sdk-introduced.py's inherit_class_floor looks it up).
local function class_floors(all, number)
    local floor = {}
    for _, list in pairs(all) do
        for _, record in ipairs(list) do
            if record.lang == "objc" and (record.kind == "class" or record.kind == "protocol") and record.introduced then
                local have = floor[record.api]
                if have == nil or number(record.introduced) < number(have) then
                    floor[record.api] = record.introduced
                end
            end
        end
    end
    return floor
end

-- Fills the introduction of the rows that have none of their own. An ObjC member takes its class's introduction in the same framework
-- (via container), and a category member, or a member whose class has none there, the class floor. An enum constant takes its enum's.
-- A Swift member takes the nearest type its api names that has an introduction (via container).
local function inherit(list, floor)
    local own = {}
    for _, record in ipairs(list) do
        local type_kind = record.kind == "class" or record.kind == "protocol" or record.kind == "struct" or record.kind == "enum"
            or record.kind == "typealias"
        if type_kind and record.introduced and own[record.lang .. "\t" .. record.api] == nil then
            own[record.lang .. "\t" .. record.api] = record.introduced
        end
    end
    for _, record in ipairs(list) do
        if record.introduced == nil and record.lang == "objc" and (record.kind == "method" or record.kind == "property") then
            if not record.category and own["objc\t" .. record.owner] then
                record.introduced, record.via = own["objc\t" .. record.owner], "container"
            elseif floor[record.owner] then
                record.introduced, record.via = floor[record.owner], "class-floor"
            end
        elseif record.introduced == nil and record.lang == "objc" and record.kind == "constant" and record.container ~= NO_VALUE then
            record.introduced, record.via = own["objc\t" .. record.container], "container"
        elseif record.introduced == nil and record.lang == "swift" and record.container ~= NO_VALUE then
            local container = record.container
            while container ~= NO_VALUE and own["swift\t" .. container] == nil do
                container = string.match(container, "^(.*)%.[^.]*$") or NO_VALUE
            end
            if container ~= NO_VALUE then
                record.introduced, record.via = own["swift\t" .. container], "container"
            end
        end
    end
end

-- The surface rows of the tree, every framework: a list of records with the COLUMNS of the surface table, sorted as the table is (by
-- the introduction, the framework, the language, the kind and the api; the shards' order last). A row of a framework named twice is
-- in the list twice, as it is in the table.
function rows(tree)
    local avail = found(tree, "avail")
    local number = avail.version_number
    local all = records(tree, avail)
    local floor = class_floors(all, number)
    local out = {}
    for _, fw in ipairs(frameworks(tree)) do
        inherit(all[fw], floor)
        for _, record in ipairs(all[fw]) do
            if record.introduced and number(record.introduced) > number(AFTER) then
                record.sequence = #out + 1
                table.insert(out, record)
            end
        end
    end
    table.sort(out, function(a, b)
        local na, nb = number(a.introduced), number(b.introduced)
        if na ~= nb then
            return na < nb
        end
        if a.framework ~= b.framework then
            return order.less(a.framework, b.framework)
        end
        if a.lang ~= b.lang then
            return a.lang < b.lang
        end
        if a.kind ~= b.kind then
            return a.kind < b.kind
        end
        if a.api ~= b.api then
            return order.less(a.api, b.api)
        end
        return a.sequence < b.sequence
    end)
    return out
end

-- The surface table's text for a list of rows: the header line, then one line per row with its cells in COLUMNS order.
function table_text(list)
    local lines = {table.concat(COLUMNS, "\t")}
    for _, record in ipairs(list) do
        local cells = {}
        for index, name in ipairs(COLUMNS) do
            local value = tostring(record[name] or NO_VALUE)
            cells[index] = (string.gsub(value, "[\t\n]", " "))
        end
        table.insert(lines, table.concat(cells, "\t"))
    end
    return table.concat(lines, "\n") .. "\n"
end
