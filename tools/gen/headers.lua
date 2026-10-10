-- The header parser's facts for one framework, behind one interface (design-spec-driven.md D3). Input: the framework's name, the
-- SDK's path, and the repository tree (where the parser is). Output: the facts of the parse, grouped by kind:
--   members:      a list of {cls, kind, api, alias, decl, avail}, the members of the framework's iOS view, in the parser's order
--   declared:     a set of the typedef, class and protocol names the iOS build sees
--   typedefs:     name -> the text the typedef is defined as
--   superclasses: class -> the superclass its @interface names in the headers (comments removed; a later line wins)
-- The parser is `gen.py headers`, read through a pipe; it is the only part of the generator that reads SDK headers. A replacement
-- parser prints the same kinds in the same fields, and nothing else changes. Tests inject their facts through use().

local stream = import("stream", {anonymous = true})
local tsv = import("tsv", {anonymous = true})

local injected = nil

-- Makes facts(...) answer from source(fw, sdk) instead of the parser. For tests, which must not parse headers.
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
