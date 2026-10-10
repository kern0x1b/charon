-- The string operations the oracle's code runs on text (strip, collapse, the part before a separator, the last occurrence of a
-- plain substring, Python's splitlines), spelled once for the commands. Lua patterns only: nothing here is a regular expression.

local tsv = import("tsv", {anonymous = true})

-- A set: a table keyed by each string of the list.
function set(list)
    local out = {}
    for _, item in ipairs(list) do
        out[item] = true
    end
    return out
end

-- The text without leading and trailing whitespace (Python's strip()).
function strip(text)
    return (string.gsub((string.gsub(text, "^%s+", "")), "%s+$", ""))
end

-- The text with each run of whitespace as one space, and none at either end (Python's " ".join(text.split())).
function collapse(text)
    return strip((string.gsub(text, "%s+", " ")))
end

-- The text without the characters of a pattern class at its end (Python's rstrip(chars)); class is e.g. "[ ;]".
function rstrip(text, class)
    return (string.gsub(text, class .. "+$", ""))
end

-- The text before the first occurrence of a plain separator (Python's split(sep)[0]); the whole text when there is none.
function before(text, sep)
    local at = string.find(text, sep, 1, true)
    if at == nil then
        return text
    end
    return string.sub(text, 1, at - 1)
end

-- The index of the last occurrence of a plain substring (Python's rfind), or nil when there is none.
function last_index(text, sub)
    local found, pos = nil, 1
    while true do
        local at = string.find(text, sub, pos, true)
        if at == nil then
            return found
        end
        found = at
        pos = at + 1
    end
end

-- The text with the universal newlines of a text read in Python's text mode: \r\n and \r become \n.
function universal(text)
    return (string.gsub(text, "\r\n?", "\n"))
end

-- The lines of a text as Python's splitlines() gives them: the line breaks are \n, \r\n, \r, \v, \f, \x1c, \x1d and \x1e, and a
-- final break ends the last line rather than starting an empty one.
function lines(text)
    local marked = string.gsub(universal(text), "[\11\12\28-\30]", "\n")
    return tsv.lines(marked)
end
