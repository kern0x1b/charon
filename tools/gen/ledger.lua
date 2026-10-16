-- The 6.1.3 ledger's cache pass: what the release's own dyld shared cache says about each declaration of the model, and the absence
-- rule over it. The cache is read by name: the release (6.1.3) resolves through modules/apple/dyld.lua (held_source under root), and
-- the two charon readers run on the resolved file: tools/corpus/objc-inventory.lua (ObjC classes, protocols and their selectors) and
-- tools/corpus/dump-cache.lua (every exported symbol). Nothing under ~/.charon/dyld is opened here by hand.
--
-- A declaration is checkable when the cache can show it: an ObjC class or protocol, a method or property (its selector on its class),
-- a constant or a function (its linker symbol). An enum member has no symbol of its own, so it is not checkable, and neither is a type
-- (enum, struct, typealias) or a Swift declaration: the header pass and the Swift pass decide those.
--
-- The absence rule: a framework none of whose own declarations is in the cache is absent from the release. Only the ObjC runtime names
-- are evidence of absence. A C function or constant missing from the cache proves nothing: a static inline function has no symbol, so an
-- iOS 6 header-only framework (CoreAudioTypes, os) would read as absent. A C symbol the cache does have is evidence of presence.

local TAB = "\t"
local NO_VALUE = "-"
-- The declaration kinds the cache checks by a linker symbol: their absence is no evidence (see above).
local C_SYMBOL_KINDS = {constant = true, ["function"] = true}

-- The fields of a tab-separated line, empty ones included.
function split(line, sep)
    local out, from = {}, 1
    while true do
        local at = string.find(line, sep, from, true)
        if at == nil then
            table.insert(out, string.sub(line, from))
            return out
        end
        table.insert(out, string.sub(line, from, at - 1))
        from = at + #sep
    end
end

-- A set of the selectors a reader prints, comma-joined (an empty field is the empty set). objc-inventory writes each selector with a sign in
-- front ("-setFrame:"), which is not part of its name: the field's position says whether it is an instance or a class selector.
local function names_set(field)
    local set = {}
    if field == nil or field == "" then
        return set
    end
    for name in string.gmatch(field, "[^,]+") do
        set[(string.gsub(name, "^[-+]", ""))] = true
    end
    return set
end

-- The release's runtime names: classes and protocols with their instance and class selectors (objc-inventory.lua's lines), and the
-- exported symbols (dump-cache.lua's lines, "<symbol>\t<install name>", the symbol with its leading underscore). Returns a table
-- {classes = name -> {inst, cls}, protocols = name -> {inst, cls}, exports = symbol -> true}.
function parse_facts(objc_text, export_text)
    local facts = {classes = {}, protocols = {}, exports = {}}
    for line in string.gmatch(objc_text or "", "[^\n]+") do
        local f = split(line, TAB)
        local entry = {inst = names_set(f[5]), cls = names_set(f[6])}
        if f[1] == "class" then
            facts.classes[f[2]] = entry
        elseif f[1] == "protocol" then
            facts.protocols[f[2]] = entry
        end
    end
    for line in string.gmatch(export_text or "", "[^\n]+") do
        local symbol = split(line, TAB)[1]
        if symbol ~= nil and symbol ~= "" then
            facts.exports[symbol] = true
        end
    end
    return facts
end

-- The release folder's cache file, resolved from the release name (dyld.held_source under dyld.root()). nil when the release holds no
-- armv7 cache.
function cache_of(tree, release)
    local dyld = import("apple.dyld", {rootdir = path.join(tree, "modules"), anonymous = true})
    return dyld.held_source(path.join(dyld.root(), release), "armv7")
end

-- Runs one charon reader over the cache and returns its stdout. The reader is an xmake script, run with the tree's own charon root.
local function reader(tree, script, cache)
    return os.iorunv("xmake", {"l", path.join(tree, "tools", "corpus", script), cache}, {envs = {CHARON_ROOT = tree}})
end

-- The release's facts, read through the two readers. Returns the facts, the cache file and the readers' raw text (for the dump).
function read_release(tree, release)
    local cache = cache_of(tree, release)
    assert(cache, "the release " .. release .. " holds no armv7 dyld shared cache: nothing to read it against")
    local objc_text, export_text = reader(tree, "objc-inventory.lua", cache), reader(tree, "dump-cache.lua", cache)
    return parse_facts(objc_text, export_text), cache, objc_text, export_text
end

-- The owner, selector and side of a method or property record: a method "-[Owner sel:]" is owner and sel: (class side when the sign is +),
-- and a property "Owner.name" is owner and its getter (or its name), either side. nil for an api the pattern does not read.
local function member_of(record)
    local sign, owner, sel = string.match(record.api, "^([-+])%[([%w_]+) (.+)%]$")
    if owner then
        return owner, sel, sign == "+"
    end
    owner, sel = string.match(record.api, "^([%w_]+)%.([%w_]+)$")
    if owner then
        local getter = record.getter
        if getter and getter ~= NO_VALUE and getter ~= "" then
            sel = getter
        end
        return owner, sel, nil
    end
    return nil
end

-- An enum member (c:@E<enum>@<member>): a constant of the enum, with no linker symbol of its own, so the cache cannot show it.
local function enum_member(record)
    return record.usr ~= nil and string.match(record.usr, "^c:@E[^@]*@[^@]+@") ~= nil
end

-- Whether the cache shows one declaration: "present" or "absent" with its reason, or nil when the cache cannot decide it (not checkable).
function check(record, facts)
    local kind, lang, api = record.kind, record.lang, record.api
    if lang ~= "objc" or enum_member(record) then
        return nil
    end
    if kind == "class" or kind == "protocol" then
        if facts.classes[api] or facts.protocols[api] then
            return "present", "a " .. kind .. " " .. api .. " in the 6.1.3 cache"
        end
        return "absent", "no class or protocol " .. api .. " in the 6.1.3 cache"
    elseif kind == "method" or kind == "property" then
        local owner, sel, class_side = member_of(record)
        if owner == nil then
            return nil
        end
        local entry = facts.classes[owner] or facts.protocols[owner]
        if entry == nil then
            return "absent", "no class or protocol " .. owner .. " in the 6.1.3 cache, for " .. api
        end
        local present
        if class_side == nil then
            present = entry.inst[sel] or entry.cls[sel]
        elseif class_side then
            present = entry.cls[sel]
        else
            present = entry.inst[sel]
        end
        if present then
            return "present", "selector " .. sel .. " of " .. owner .. " in the 6.1.3 cache"
        end
        return "absent", "no selector " .. sel .. " on " .. owner .. " in the 6.1.3 cache"
    elseif kind == "constant" or kind == "function" then
        local name = string.gsub(api, "%(%)$", "")
        if facts.exports["_" .. name] then
            return "present", "the symbol " .. name .. " is exported by the 6.1.3 cache"
        end
        return "absent", "no symbol " .. name .. " exported by the 6.1.3 cache"
    end
    return nil
end

-- The absence rule over the declarations of each framework: decls = framework -> its records (surface_model.declarations), each claimed by
-- a framework through claimed_by. Returns framework -> {verdict, checkable, present, reason}, verdict one of:
--   "present"    a declaration the framework owns is in the 6.1.3 cache (present counts them);
--   "absent"     none of its own runtime declarations (class, protocol, method, property) is in the cache, and it has at least one: the
--                framework is not in the release, so every row is work; checkable counts the runtime declarations;
--   "undecided"  the cache cannot say: its own declarations are types, enum members, Swift, or C symbols the cache lacks.
function verdicts(decls, facts)
    -- A declaration counts for the framework that owns it (claimed_by), whichever framework's shard holds it: a usr two frameworks declare
    -- is in both shards and owned by one of them.
    -- A nested shard (MetalPerformanceShaders/MPSCore) is a unit of its own, named by its folder, as the trace and the input read it: its
    -- declarations claimed by its outer framework count for it too.
    local tally = {}
    local function count(key, record, status, reason)
        tally[key] = tally[key] or {runtime = 0, present = 0, c_absent = 0, first_absent = nil}
        local t = tally[key]
        if status == "present" then
            t.present = t.present + 1
            if not C_SYMBOL_KINDS[record.kind] then
                t.runtime = t.runtime + 1
            end
        elseif status == "absent" and C_SYMBOL_KINDS[record.kind] then
            t.c_absent = t.c_absent + 1
        elseif status == "absent" then
            t.runtime = t.runtime + 1
            t.first_absent = t.first_absent or reason
        end
    end
    for fw in pairs(decls) do
        tally[fw] = {runtime = 0, present = 0, c_absent = 0, first_absent = nil}
    end
    for _, list in pairs(decls) do
        for _, record in ipairs(list) do
            if record.claimed_by and tally[record.claimed_by] then
                local status, reason = check(record, facts)
                count(record.claimed_by, record, status, reason)
                if record.unit and record.unit ~= record.claimed_by and string.match(record.unit, "^([^/]+)") == record.claimed_by then
                    count(record.unit, record, status, reason)
                end
            end
        end
    end
    local out = {}
    for fw, t in pairs(tally) do
        local runtime, present, first_absent, c_absent = t.runtime, t.present, t.first_absent, t.c_absent
        local verdict, reason
        if present > 0 then
            verdict, reason = "present", present .. " own declarations are in the 6.1.3 cache"
        elseif first_absent ~= nil then
            verdict = "absent"
            reason = "none of its " .. runtime .. " own runtime declarations is in the 6.1.3 cache; e.g. " .. first_absent
        else
            verdict = "undecided"
            reason = "no own runtime declaration to check (" .. c_absent .. " C symbols are missing from the cache, which a static inline"
                     .. " function also is): the lifted headers decide it"
        end
        out[fw] = {verdict = verdict, checkable = runtime, present = present, reason = reason}
    end
    return out
end
