-- The header parser's facts for one framework, behind one interface (design-spec-driven.md D3). Input: the framework's name, the
-- SDK's path, and the repository tree (where the parser is). Output: the facts of the parse, grouped by kind:
--   members:      a list of {cls, kind, api, alias, decl, avail}, the members of the framework's iOS view, in the parser's order
--   declared:     a set of the typedef, class and protocol names the iOS build sees
--   typedefs:     name -> the text the typedef is defined as
--   superclasses: class -> the superclass its @interface names in the headers (comments removed; a later line wins)
--   comments:     the comment the doc shows above a member, for the non-empty ones only: keyed by comment_key(class, kind, key)
--                 (kind is "method" or "property"; a method's key is its first selector part, a property's its name). Read with
--                 comment_of(facts, class, kind, key). The comment is taken from the header text the doc reads (platform blocks
--                 stripped, comments kept), by the parser's header_comment.
--   raw:          a set of the apis of the members the headers declare on any platform branch (the iOS view leaves some out)
--   identifiers:  a set of the words the headers spell outside their comments (every platform branch)
-- The parser is `gen.py headers`, read through a pipe; it is the only part of the generator that reads SDK headers. A replacement
-- parser prints the same kinds in the same fields, and nothing else changes. Tests inject their facts through use().

local stream = import("stream", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local layout = import("layout", {anonymous = true})

local injected = nil

-- Makes facts(...) answer from source(fw, sdk) instead of the parser. For tests, which must not parse headers.
function use(source)
    injected = source
end

-- The key of a comment fact: the class, the kind and the key, joined by tabs (a tab never occurs in a field).
function comment_key(cls, kind, key)
    return cls .. "\t" .. kind .. "\t" .. key
end

-- The comment the header gives a member (see comments in the header of this module), or "" when it gives none.
function comment_of(parsed, cls, kind, key)
    return parsed.comments[comment_key(cls, kind, key)] or ""
end

-- The facts of one framework (see the header of this module).
function facts(tree, fw, sdk)
    if injected then
        return injected(fw, sdk)
    end
    local out = {members = {}, declared = {}, typedefs = {}, superclasses = {}, comments = {}, raw = {}, identifiers = {}}
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
        elseif cells[1] == "comment" then
            out.comments[comment_key(cells[2], cells[3], cells[4])] = cells[5] or ""
        elseif cells[1] == "raw" then
            out.raw[cells[2]] = true
        elseif cells[1] == "identifier" then
            out.identifiers[cells[2]] = true
        else
            error("the header parser printed an unknown fact: " .. cells[1])
        end
    end)
    assert(status == 0, "the header parser failed on " .. fw .. " (status " .. status .. ")")
    return out
end

-- The rows of one framework's committed declaration shard, each a record keyed by the column names the shard's own header line gives
-- (columns=...), so a column added to the shards is read by name and no reader depends on its position. The shard path is
-- tree/packages/a/apple-backports/spec/<F>/declarations.tsv. A framework with no shard has no rows.
function shard_records(tree, fw)
    local file = path.join(tree, layout.constants().SNAP_ROOT, fw, "declarations.tsv")
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
        elseif columns then
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

-- The facts of one framework read from its committed declaration shard (design-foundation.md 5.7), beside the parser's facts
-- above and not yet their consumers' input: members (the class members, with the IR's availability fields, the availability
-- text rendered by the foundation's renderer, and the declaration hash), declared names, typedef names and superclasses. Read
-- through the foundation's shard reader and renderer under tree/tools/found, by the column names of the shard.
function shard_facts(tree, fw)
    local out = {members = {}, declared = {}, typedefs = {}, superclasses = {}}
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
        if r.kind == "method" or r.kind == "property" then
            local cls = string.match(r.usr, "^c:objc%(cs%)([^%(]+)")
            if cls then
                local api, alias
                if r.kind == "method" then
                    api = side .. "[" .. cls .. " " .. name .. "]"
                    alias = api
                else
                    api = "-[" .. cls .. " " .. name .. "]"
                    alias = cls .. "." .. name
                end
                table.insert(out.members, {cls = cls, kind = r.kind, api = api, alias = alias, avail = r.avail,
                                           message = r.message, text = avail.render(r.avail, r.message), hash = r.declhash,
                                           usr = r.usr, key = r.container})
            end
        elseif r.kind == "typedef" then
            out.typedefs[name] = true
        elseif entities[r.kind] then
            out.declared[name] = true
        elseif r.kind == "super" then
            out.superclasses[r.container] = name
        end
    end
    return out
end
