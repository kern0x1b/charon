-- The header embed.py writes for a records file, in xmake lua, so that the host tests need no python.
--
--     xmake lua tests/backports/host/foundation2/embed.lua <records.json> <header.h>
--
-- The records are read as JSON, written back compact with the escapes json.dumps uses for ASCII text, and cut into
-- 160-character string literals that escape `"`, `\` and `?`, as embed.py does. embed.py keeps the records' own key
-- order; this port sorts the keys, which is the same for a file the recorder wrote with sorted keys (every records
-- file here is). Text that is not ASCII is refused: json.dumps writes it as \u escapes, which this port does not write.
import("core.base.json")

local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}

local function escape(character)
    return escapes[character] or string.format("\\u%04x", character:byte())
end

local function encode(value)
    local kind = type(value)
    if kind == "string" then
        if value:find("[\128-\255]") then
            raise("embed.lua: non-ASCII text is not ported, and json.dumps would write it as \\u escapes")
        end
        return '"' .. (value:gsub('[%z\1-\31"\\]', escape)) .. '"'
    elseif kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        if #value > 0 then
            local items = {}
            for index, item in ipairs(value) do
                items[index] = encode(item)
            end
            return "[" .. table.concat(items, ",") .. "]"
        end
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then
                raise("embed.lua: a key of type " .. type(key) .. " is not a JSON object key")
            end
            table.insert(keys, key)
        end
        table.sort(keys)
        local members = {}
        for index, key in ipairs(keys) do
            members[index] = encode(key) .. ":" .. encode(value[key])
        end
        return "{" .. table.concat(members, ",") .. "}"
    end
    raise("embed.lua: a " .. kind .. " value is not ported")
end

function main(records, header)
    local text = encode(json.decode(io.readfile(records)))
    local lines = {"static const char foundation2_expectations[] ="}
    for start = 1, #text, 160 do
        local chunk = text:sub(start, start + 159):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%?", "\\?")
        table.insert(lines, '    "' .. chunk .. '"')
    end
    table.insert(lines, ";")
    io.writefile(header, table.concat(lines, "\n") .. "\n")
end
