-- Reads each row of tools/corpus/cfconst.tsv back out of the dyld cache it names, and compares it with the initializer the row carries.
-- Usage: CHARON_ROOT=<worktree> xmake l tools/corpus/cfconst-check.lua
--
-- The cache is CACHE_ROOT/<release>/dyld_shared_cache_<arch> (CACHE_ROOT defaults to ~/.charon/dyld). Its symbols are read by
-- tools/corpus/cache-value.lua, which goes through the project's reader (modules/apple/dyld.lua). One call per cache: the rows that name
-- it are asked together, and cache-value answers with one line per symbol, or with dashes for a symbol no image of the cache exports.
--
-- A string row (@"..." or CFSTR("...")) is judged when its text is printable ASCII and the reader resolved the pointer: the text the cache
-- holds must equal the initializer's text. A number row is judged on the four bytes of the cache value: its float32 bits must equal the
-- number's. A struct row is not judged: the reader does not read a struct, and the facts file says what the symbol holds instead. A row
-- is reported by name, with what the cache held, when it differs, when no image exports it, or when the reader gave no value.
--
-- Exits 1 when any row differs or is absent, or when no row was judged at all (a check that judged nothing proves nothing).

local cfconst = import("gen.cfconst", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})

local root = os.getenv("CHARON_ROOT") or path.join(os.scriptdir(), "..", "..")
local cache_root = os.getenv("CACHE_ROOT") or path.join(os.getenv("HOME"), ".charon", "dyld")
local cache_value = path.join(os.scriptdir(), "cache-value.lua")

-- The file of a cache named "<release> <arch>", as the held ladder keeps it.
local function cache_file(cache)
    local release, arch = string.match(cache, "^(%S+) (%S+)$")
    assert(release ~= nil, "the cache named in the table is not '<release> <arch>': " .. cache)
    return path.join(cache_root, release, "dyld_shared_cache_" .. arch)
end

-- What a row's initializer says it holds: {kind = "string", text = ...}, {kind = "number", value = ...}, or {kind = "struct"}, or nil.
local function expected_of(initializer)
    local quoted = string.match(initializer, '^@"(.*)"$') or string.match(initializer, '^CFSTR%("(.*)"%)$')
    if quoted ~= nil then
        return {kind = "string", text = (string.gsub(string.gsub(quoted, '\\"', '"'), "\\\\", "\\"))}
    end
    if string.sub(initializer, 1, 1) == "{" then
        return {kind = "struct"}
    end
    local number = tonumber(initializer)
    if number ~= nil then
        return {kind = "number", value = number}
    end
    return nil
end

-- The symbol file cache-value reads: name, width ("p" for a pointer-sized value, "0" for a struct), pointer and text flags.
local function symbol_line(row, expected)
    if expected.kind == "string" then
        return string.format("%s\tp\tp\ts", row.name)
    elseif expected.kind == "number" then
        return string.format("%s\tp\t-\t-", row.name)
    end
    return string.format("%s\t0\t-\t-", row.name)
end

-- Reads the values of one cache's rows. Returns name -> the reader's fields, or nil for a symbol no image exports.
local function read_cache(cache, rows)
    local file = cache_file(cache)
    local symbols = os.tmpfile() .. ".cfconst"
    local lines = {}
    for _, row in ipairs(rows) do
        table.insert(lines, symbol_line(row, row.expected))
    end
    io.writefile(symbols, table.concat(lines, "\n") .. "\n")
    local out, err = os.iorunv("xmake", {"l", cache_value, file, symbols}, {envs = {CHARON_ROOT = root}})
    os.rm(symbols)
    assert(out ~= nil and out ~= "", "the reader gave no output for " .. file .. ": " .. tostring(err))
    local found = {}
    for line in string.gmatch(out, "[^\n]+") do
        local fields = {}
        for field in string.gmatch(line .. "\t", "([^\t]*)\t") do
            table.insert(fields, field)
        end
        if fields[1] ~= "#cache" then
            if fields[2] == "-" then
                found[fields[1]] = false
            else
                found[fields[1]] = fields
            end
        end
    end
    return found
end

function main()
    local rows = cfconst.table_rows(root)
    local by_cache, caches = {}, {}
    for _, row in ipairs(rows) do
        row.expected = expected_of(row.initializer)
        if row.expected == nil then
            print(string.format("UNJUDGED\t%s\t%s\tthe initializer %s is not a string, a number or a struct", row.object, row.name, row.initializer))
        elseif row.expected.kind == "struct" then
            print(string.format("UNJUDGED\t%s\t%s\tthe reader does not read a struct; the facts file records the symbol's own bytes", row.object, row.name))
        elseif row.expected.kind == "string" and string.find(row.expected.text, "[^\32-\126]") then
            print(string.format("UNJUDGED\t%s\t%s\tthe initializer is not printable ASCII, and the reader prints a non-ASCII byte as a dot", row.object, row.name))
        else
            if by_cache[row.cache] == nil then
                by_cache[row.cache] = {}
                table.insert(caches, row.cache)
            end
            table.insert(by_cache[row.cache], row)
        end
    end
    local judged, failed = 0, 0
    for _, cache in ipairs(caches) do
        local found = read_cache(cache, by_cache[cache])
        for _, row in ipairs(by_cache[cache]) do
            local fields = found[row.name]
            if not fields then
                print(string.format("ABSENT\t%s\t%s\tthe reader answered for no symbol of %s", row.object, row.name, cache))
                failed = failed + 1
            elseif fields == false then
                print(string.format("ABSENT\t%s\t%s\tno image of %s exports it", row.object, row.name, cache))
                failed = failed + 1
            elseif row.expected.kind == "string" then
                local text = fields[9]
                if fields[8] == "-" or text == "-" then
                    print(string.format("UNREAD\t%s\t%s\tthe reader gave no string for it in %s", row.object, row.name, cache))
                    failed = failed + 1
                elseif text ~= row.expected.text then
                    print(string.format("DIFFERS\t%s\t%s\texpected %q, %s holds %q", row.object, row.name, row.expected.text, cache, text))
                    failed = failed + 1
                else
                    judged = judged + 1
                end
            else
                local bits = string.unpack("<I4", string.pack("<f", row.expected.value))
                local held = tonumber(fields[5])
                if held ~= bits then
                    print(string.format("DIFFERS\t%s\t%s\texpected %s (float32 bits %d), %s holds %d", row.object, row.name, row.initializer, bits, cache, held))
                    failed = failed + 1
                else
                    judged = judged + 1
                end
            end
        end
    end
    print(string.format("cfconst-check: %d rows judged, %d not judged, %d failed", judged, #rows - judged - failed, failed))
    assert(judged > 0, "cfconst-check judged no row, so it proves nothing")
    if failed > 0 then
        os.exit(1)
    end
end
