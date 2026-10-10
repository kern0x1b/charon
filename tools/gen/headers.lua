-- The header parser's facts for one framework, behind one interface (design-spec-driven.md D3). Input: the framework's name, the
-- SDK's path, and the repository tree (where the parser is). Output: the facts of the parse, grouped by kind:
--   members:      a list of {cls, kind, api, alias, decl, avail}, the members of the framework's iOS view, in the parser's order
--   declared:     a set of the typedef, class and protocol names the iOS build sees
--   typedefs:     name -> the text the typedef is defined as
--   superclasses: class -> the superclass its @interface names in the headers (comments removed; a later line wins)
-- The parser is `gen.py headers`, read through a pipe; it is the only part of the generator that reads SDK headers. A replacement
-- parser prints the same kinds in the same fields, and nothing else changes. Tests inject their facts through use().
-- The typed facts of a shard (shard_facts, typedef_index, declared_names) are read from the committed declaration shards and
-- answer from the same injected source when one is set (design-foundation.md 5.7).

local stream = import("stream", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local layout = import("layout", {anonymous = true})
local files = import("files", {anonymous = true})
local order = import("order", {anonymous = true})

local injected = nil
-- The typedef index and the declared names of the tree, read once per tree (the shards are read once per process).
local typedef_memo = {}
local declared_memo = {}

-- Makes facts(...), shard_facts(...), typedef_index(...) and declared_names(...) answer from source(fw, sdk) instead of the parser and
-- the shards. For tests, which must not parse headers. source returns the four kinds of facts, and members may carry the typed fields
-- (type, params, attrs) that shard_facts reads; functions is name -> {type, params}.
function use(source)
    injected = source
end

-- The facts of one framework (see the header of this module).
function facts(tree, fw, sdk)
    if injected then
        return injected(fw, sdk)
    end
    local out = {members = {}, declared = {}, typedefs = {}, superclasses = {}}
    -- The parser is a Python program until it is replaced: this is the one place that names it.
    local status = stream.lines("python3", {path.join(tree, "tools", "gen.py"), "headers", "--tree", tree, "--framework", fw,
                                            "--sdk", sdk}, function(line)
        local cells = tsv.fields(line)
        if cells[1] == "member" then
            table.insert(out.members, {cls = cells[2], kind = cells[3], api = cells[4],
                                       alias = cells[5] ~= "-" and cells[5] or nil, decl = cells[6],
                                       avail = cells[7] ~= "-" and cells[7] or nil})
        elseif cells[1] == "declared" then
            out.declared[cells[2]] = true
        elseif cells[1] == "typedef" then
            out.typedefs[cells[2]] = cells[3]
        elseif cells[1] == "superclass" then
            out.superclasses[cells[2]] = cells[3]
        else
            error("the header parser printed an unknown fact: " .. cells[1])
        end
    end)
    assert(status == 0, "the header parser failed on " .. fw .. " (status " .. status .. ")")
    return out
end

-- The rows of a shard file (its columns come from its own header line, columns=...), each a record keyed by the column names, so a
-- column added to the shards is read by name. kinds (a set, or nil for all) keeps only the rows of those kinds, read before the
-- row is split. A missing file has no rows.
local function read_rows(file, kinds)
    local out = {}
    if not os.isfile(file) then
        return out
    end
    local columns = nil
    for line in io.lines(file) do
        if string.sub(line, 1, 1) == "#" then
            local names = string.match(line, "columns=([^\t]*)")
            if names then
                columns = {}
                for name in string.gmatch(names, "[^,]+") do
                    table.insert(columns, name)
                end
            end
        elseif columns and (kinds == nil or kinds[string.match(line, "^[^\t]*")]) then
            local cells = {}
            for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
                table.insert(cells, cell)
            end
            local row = {}
            for index, name in ipairs(columns) do
                row[name] = cells[index]
            end
            table.insert(out, row)
        end
    end
    return out
end

-- The declaration shard of a framework: tree/packages/a/apple-backports/spec/<F>/declarations.tsv (a nested framework's is
-- spec/<Outer>/<Inner>/declarations.tsv).
local function shard_path(tree, fw)
    return path.join(tree, layout.constants().SNAP_ROOT, fw, "declarations.tsv")
end

-- The rows of one framework's committed declaration shard (design-foundation.md 5.7), by the column names. A framework with no shard has
-- no rows.
function shard_records(tree, fw)
    return read_rows(shard_path(tree, fw), nil)
end

-- The name a shard row gives (the USR's, or the stored cell).
local function row_name(shard, r)
    return (shard.decode(r.kind, r.usr, r.name or "", r.side or ""))
end

-- The shards of every framework of the tree, in name order, nested frameworks included.
local function shard_files(tree)
    local found = {}
    for _, pattern in ipairs({"*", "*/*"}) do
        for _, filepath in ipairs(files.glob(path.join(tree, layout.constants().SNAP_ROOT, pattern, "declarations.tsv"))) do
            table.insert(found, filepath)
        end
    end
    table.sort(found, order.less)
    return found
end

-- The facts of one framework read from its committed declaration shard (design-foundation.md 5.7), beside the parser's facts
-- above: members (the class members, with the IR's availability fields, the availability text rendered by the foundation's
-- renderer, the declaration hash, and the typed fields type, params and attrs), functions (name -> {type, params}, the C functions),
-- declared names, typedef names and superclasses. Read through the foundation's shard reader and renderer under tree/tools/found.
function shard_facts(tree, fw)
    local out = {members = {}, declared = {}, typedefs = {}, superclasses = {}, functions = {}}
    if injected then
        local source = injected(fw, nil)
        for key, value in pairs(source) do
            out[key] = value
        end
        out.members = out.members or {}
        out.declared = out.declared or {}
        out.typedefs = out.typedefs or {}
        out.superclasses = out.superclasses or {}
        out.functions = out.functions or {}
        return out
    end
    local records = shard_records(tree, fw)
    if #records == 0 then
        return out
    end
    local shard = import("found.shard", {rootdir = path.join(tree, "tools"), anonymous = true})
    local avail = import("found.avail", {rootdir = path.join(tree, "tools"), anonymous = true})
    local entities = {var = true, ["function"] = true, enum = true, struct = true, union = true, enumconst = true,
                      interface = true, protocol = true}
    for _, r in ipairs(records) do
        local name, side = shard.decode(r.kind, r.usr, r.name or "", r.side or "")
            -- a class property is "+" (design-foundation.md 3.5): its USR carries the class part (cpy); the shard stores no side for it
            if r.kind == "property" and string.find(r.usr, "(cpy)", 1, true) then
                side = "+"
            end
        if r.kind == "method" or r.kind == "property" then
            local cls = string.match(r.usr, "^c:objc%(cs%)([^%(]+)")
            if cls then
                -- a class property takes the sign of a class method ("+"): the side the shard records (design-foundation.md 3.5)
                local api = side .. "[" .. cls .. " " .. name .. "]"
                local alias = r.kind == "method" and api or (cls .. "." .. name)
                table.insert(out.members, {cls = cls, kind = r.kind, api = api, alias = alias, availability = r.availability,
                                           message = r.message, text = avail.render(r.availability, r.message),
                                           type = r.type, params = r.params, attrs = r.attrs, hash = r.declhash, usr = r.usr,
                                           key = r.container})
            end
        elseif r.kind == "typedef" then
            out.typedefs[name] = r.type
        elseif r.kind == "super" then
            out.superclasses[r.container] = name
        elseif entities[r.kind] then
            out.declared[name] = true
            if r.kind == "function" then
                out.functions[name] = {type = r.type, params = r.params, usr = r.usr}
            end
        end
    end
    return out
end

-- The typedef index of the whole SDK: each typedef name -> the underlying type its shard row gives (a typedef of two frameworks keeps
-- the first, in name order). Read once per tree. With a source injected, the framework's own typedefs of the source.
function typedef_index(tree, fw)
    if injected then
        return injected(fw, nil).typedefs or {}
    end
    if typedef_memo[tree] == nil then
        local shard = import("found.shard", {rootdir = path.join(tree, "tools"), anonymous = true})
        local index = {}
        for _, filepath in ipairs(shard_files(tree)) do
            for _, r in ipairs(read_rows(filepath, {typedef = true})) do
                local name = row_name(shard, r)
                if r.type and r.type ~= "-" and index[name] == nil then
                    index[name] = r.type
                end
            end
        end
        typedef_memo[tree] = index
    end
    return typedef_memo[tree]
end

-- True when an availability text (the shard's column) has the platform unavailable: its ios entry's last field is 1.
local function ios_unavailable(availability)
    for entry in string.gmatch(availability or "", "[^,]+") do
        local value = string.match(entry, "^ios=(.*)$")
        if value and string.match(value, "[^/]*$") == "1" then
            return true
        end
    end
    return false
end

-- Adds the typedef, class and protocol names of one shard to names, and the classes the iOS SDK marks unavailable to unavailable.
local function add_type_names(tree, filepath, names, unavailable)
    local shard = import("found.shard", {rootdir = path.join(tree, "tools"), anonymous = true})
    for _, r in ipairs(read_rows(filepath, {typedef = true, interface = true, protocol = true})) do
        local name = row_name(shard, r)
        names[name] = true
        if r.kind == "interface" and ios_unavailable(r.availability) then
            unavailable[name] = true
        end
    end
end

-- The declared names of the tree: the typedef, class and protocol names of every shard (nested frameworks included), less the
-- classes the iOS SDK marks unavailable in any shard. Read once per tree.
local function declared_index(tree)
    if declared_memo[tree] == nil then
        local names, unavailable = {}, {}
        for _, filepath in ipairs(shard_files(tree)) do
            add_type_names(tree, filepath, names, unavailable)
        end
        for name in pairs(unavailable) do
            names[name] = nil
        end
        declared_memo[tree] = names
    end
    return declared_memo[tree]
end

-- The declared names the iOS build sees (gen.py declared_names, read over every shard instead of a list of frameworks): a set, a copy of
-- the tree's declared names. fw is the framework asked for; its own shard is one of the tree's. With a source injected, its declared set.
function declared_names(tree, fw)
    if injected then
        return injected(fw, nil).declared or {}
    end
    local out = {}
    for name in pairs(declared_index(tree)) do
        out[name] = true
    end
    return out
end

-- The type of each extern variable of a framework, by its name: the constants' type column (design-foundation.md 5.7, the typed
-- shards). The type is the one the shard spells; the typedef it names is not resolved, because a typedef's own text carries the
-- qualifiers of its pointee (CFStringRef is "const struct __CFString *"), which are not the variable's. A name the shard holds no
-- variable for is absent.
function constant_types(tree, fw)
    local out = {}
    local shard = import("found.shard", {rootdir = path.join(tree, "tools"), anonymous = true})
    for _, r in ipairs(shard_records(tree, fw)) do
        if r.kind == "var" then
            out[shard.decode(r.kind, r.usr, r.name or "", r.side or "")] = r.type or "-"
        end
    end
    return out
end
