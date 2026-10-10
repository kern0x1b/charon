-- The byte order of the package's and the generator's sorted outputs: bytes, as Python sorts str for ASCII. Lua's `<` on strings
-- follows the process locale (strcoll: under en_US it sorts "a_b" before "aB"), so every sort of a name goes through this module.

-- True when string a sorts before string b, comparing bytes (the first difference decides; a prefix sorts first).
function less(a, b)
    local n = math.min(#a, #b)
    for i = 1, n do
        local x, y = string.byte(a, i), string.byte(b, i)
        if x ~= y then
            return x < y
        end
    end
    return #a < #b
end

-- The strings of a list, sorted by bytes (a new list).
function strings(list)
    local out = table.move(list, 1, #list, 1, {})
    table.sort(out, less)
    return out
end

-- The keys of a map, or the members of a set, sorted by bytes (a new list).
function keys(map)
    local out = {}
    for key in pairs(map) do
        table.insert(out, key)
    end
    table.sort(out, less)
    return out
end
