-- The extractor's own list of the frameworks it skips (tools/found/unparsed.tsv, written by the extractor): after a comment line, one line
-- per skipped framework, its name and the reason, tab-separated. The scope takes its coverage from this list. A framework it names has
-- no declaration the extractor reads, so a member the spec does not hold there has the listed reason. Reads only.

local files = import("files", {anonymous = true})
local tsv = import("tsv", {anonymous = true})

-- The list's path in a tree.
function list_path(tree)
    return path.join(tree, "tools", "found", "unparsed.tsv")
end

-- framework name -> reason, from the text of the list. A comment line (it begins with #) and an empty line are not entries.
function parse(text)
    local out = {}
    for _, line in ipairs(tsv.lines(text)) do
        if line ~= "" and string.sub(line, 1, 1) ~= "#" then
            local cells = tsv.fields(line)
            out[cells[1]] = cells[2] or ""
        end
    end
    return out
end

-- The skipped frameworks of a tree: framework name -> reason. The list must be there: a missing list is an error, not an empty one.
function skipped(tree)
    local text = files.read_text(list_path(tree))
    assert(text, "no extractor list of skipped frameworks at " .. list_path(tree))
    return parse(text)
end
