-- Writes the header of the URL expectations (run.sh runs the diff, then this): the JSON the diff wrote, read back with its
-- key order, written as one C string literal in 160-character lines. The text is the one Python's json.dumps made of the
-- same data with ensure_ascii and the separators "," and ":": the same escapes (lower-case hex, \u007f for DEL, a surrogate
-- pair above U+FFFF), so the committed header is reproduced byte for byte.
-- Usage: xmake l ./embed.lua <expectations.json> <out.h>

local NULL = {}

local short_escapes = { [0x22] = '\\"', [0x5C] = "\\\\", [0x08] = "\\b", [0x0C] = "\\f", [0x0A] = "\\n", [0x0D] = "\\r", [0x09] = "\\t" }
local simple_escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- Parses the file's text. An object is {object = true, keys = {...}, values = {...}} with its keys in file order; an array
-- is {array = true, items = {...}}; an integer is {integer = "<digits>"}; a string is kept as its UTF-8 bytes (lone
-- surrogates from \u escapes included). A float is refused: nothing of the expectations is one, and a silent rounding
-- would be the worst kind of wrong.
local function parse(text)
    local pos = 1

    local function fail(what)
        raise(string.format("embed.lua: %s at byte %d", what, pos))
    end

    local function skip()
        pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
    end

    local value

    local function read_string()
        pos = pos + 1
        local parts = {}
        while true do
            local stop = text:find('["\\]', pos)
            if not stop then
                fail("unterminated string")
            end
            parts[#parts + 1] = text:sub(pos, stop - 1)
            if text:sub(stop, stop) == '"' then
                pos = stop + 1
                break
            end
            local escape = text:sub(stop + 1, stop + 1)
            pos = stop + 2
            if escape == "u" then
                local digits = text:sub(pos, pos + 3)
                if not digits:find("^%x%x%x%x$") then
                    fail("bad \\u escape")
                end
                local code = tonumber(digits, 16)
                pos = pos + 4
                if code >= 0xD800 and code <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then
                    local low_digits = text:sub(pos + 2, pos + 5)
                    local low = low_digits:find("^%x%x%x%x$") and tonumber(low_digits, 16)
                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        pos = pos + 6
                    end
                end
                parts[#parts + 1] = utf8.char(code)
            else
                local decoded = simple_escapes[escape]
                if not decoded then
                    fail("bad escape")
                end
                parts[#parts + 1] = decoded
            end
        end
        return table.concat(parts)
    end

    local function read_number()
        local lexeme = text:match("^-?%d+", pos)
        if not lexeme then
            fail("bad number")
        end
        pos = pos + #lexeme
        local after = text:sub(pos, pos)
        if after == "." or after == "e" or after == "E" then
            fail("a float, which the expectations never carry")
        end
        if lexeme == "-0" then
            lexeme = "0"
        end
        return { integer = lexeme }
    end

    local function read_array()
        pos = pos + 1
        local items = {}
        skip()
        if text:sub(pos, pos) == "]" then
            pos = pos + 1
            return { array = true, items = items }
        end
        while true do
            skip()
            items[#items + 1] = value()
            skip()
            local separator = text:sub(pos, pos)
            pos = pos + 1
            if separator == "]" then
                return { array = true, items = items }
            elseif separator ~= "," then
                fail("expected , or ]")
            end
        end
    end

    local function read_object()
        pos = pos + 1
        local object = { object = true, keys = {}, values = {} }
        local index = {}
        skip()
        if text:sub(pos, pos) == "}" then
            pos = pos + 1
            return object
        end
        while true do
            skip()
            if text:sub(pos, pos) ~= '"' then
                fail("expected a key")
            end
            local key = read_string()
            skip()
            if text:sub(pos, pos) ~= ":" then
                fail("expected :")
            end
            pos = pos + 1
            skip()
            local item = value()
            -- A repeated key keeps its first place in the order and takes the later value, as a Python dict does.
            if index[key] then
                object.values[index[key]] = item
            else
                object.keys[#object.keys + 1] = key
                object.values[#object.values + 1] = item
                index[key] = #object.keys
            end
            skip()
            local separator = text:sub(pos, pos)
            pos = pos + 1
            if separator == "}" then
                return object
            elseif separator ~= "," then
                fail("expected , or }")
            end
        end
    end

    value = function()
        local first = text:sub(pos, pos)
        if first == "{" then
            return read_object()
        elseif first == "[" then
            return read_array()
        elseif first == '"' then
            return read_string()
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return NULL
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        end
        return read_number()
    end

    local data = value()
    skip()
    if pos <= #text then
        fail("data after the value")
    end
    return data
end

-- The ASCII text of a string, escaped as Python's json.dumps(ensure_ascii=True) escapes it: every character outside
-- space to tilde is written as a \u escape, DEL included, and a character above U+FFFF as a surrogate pair.
local function encode_string(bytes)
    local out = { '"' }
    for _, code in utf8.codes(bytes, true) do
        if short_escapes[code] then
            out[#out + 1] = short_escapes[code]
        elseif code >= 0x20 and code <= 0x7E then
            out[#out + 1] = string.char(code)
        elseif code < 0x10000 then
            out[#out + 1] = string.format("\\u%04x", code)
        else
            local rest = code - 0x10000
            out[#out + 1] = string.format("\\u%04x\\u%04x", 0xD800 + (rest >> 10), 0xDC00 + (rest & 0x3FF))
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function encode(value)
    if value == NULL then
        return "null"
    elseif value == true then
        return "true"
    elseif value == false then
        return "false"
    elseif type(value) == "string" then
        return encode_string(value)
    elseif value.integer then
        return value.integer
    elseif value.array then
        local items = {}
        for i, item in ipairs(value.items) do
            items[i] = encode(item)
        end
        return "[" .. table.concat(items, ",") .. "]"
    end
    local members = {}
    for i, key in ipairs(value.keys) do
        members[i] = encode_string(key) .. ":" .. encode(value.values[i])
    end
    return "{" .. table.concat(members, ",") .. "}"
end

function main(inPath, outPath)
    local input = assert(io.open(inPath, "rb"))
    local text = encode(parse(input:read("a")))
    input:close()
    local output = assert(io.open(outPath, "w"))
    output:write("static const char url_expectations[] =\n")
    for start = 1, #text, 160 do
        local chunk = text:sub(start, start + 159)
        chunk = chunk:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%?", "\\?")
        output:write(string.format('    "%s"\n', chunk))
    end
    output:write(";\n")
    output:close()
end
