-- The byte order of the package's and the generator's sorted outputs: bytes, as Python sorts str for ASCII. Lua's `<` on strings
-- follows the process locale (strcoll: under en_US it sorts "a_b" before "aB"), so every sort of a name goes through this module.

-- True when string a sorts before string b, comparing bytes (the first difference decides; a prefix sorts first). Names share long
-- prefixes ("-[AVAudioUnitSampler ..."), so eight bytes are compared at a time, as one big-endian unsigned integer: the first
-- difference of two such words is the first difference of the bytes, and the unsigned order of the words is the byte order. A byte
-- loop took a third of a cold `gen --all` (17 million string.byte calls in its profile).
local unpack, byte, ult = string.unpack, string.byte, math.ult

function less(a, b)
    if a == b then
        return false
    end
    local la, lb = #a, #b
    local n = la < lb and la or lb
    local i = 1
    while i + 7 <= n do
        local x, y = unpack(">I8", a, i), unpack(">I8", b, i)
        if x ~= y then
            return ult(x, y)
        end
        i = i + 8
    end
    while i <= n do
        local x, y = byte(a, i), byte(b, i)
        if x ~= y then
            return x < y
        end
        i = i + 1
    end
    return la < lb
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
