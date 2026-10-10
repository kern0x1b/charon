-- `input`: the constant record of a framework, spec/<F>/constants.tsv (committed data, one row per constant the 6.1.3 ledger lists as
-- missing and the port has to export), and measured.held-caches.tsv when --measured names the gate's release-split output. It is the
-- port of tools/gen.py cmd_input, which is the oracle during the port; design-spec-driven.md "Records" and the report say where the two
-- differ. Each row is read from the source that owns the fact:
--   * the declaration shard (the extractor's IR): the variable's type, its introduced release (the iOS field of its availability) and
--     the declaration hash the record keeps as declhash;
--   * the extractor's doc text (decls --doc, doc_text.lua): the declaration as written, from which the record takes the text before the
--     name (what the record hashes) and the availability macros written after it;
--   * the coordination corpus: the ledger (the constants 6.1.3 lacks, in ledger order) and the iOS 26.2 cache's constants table (the value
--     of each string constant, and where it came from);
--   * the registry: a constant a registry row names is owned, and its value is not read;
--   * the host oracle (probe.lua): the macOS value of each string constant the iOS table does not answer for;
--   * the SDK's .tbd (exported or not), and the typedefs of the shards (the string and CFString shapes).
-- The record is written through emit, which rewrites the file only when its bytes change.

local layout = import("layout", {anonymous = true})
local files = import("files", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local emit = import("emit", {anonymous = true})
local digest = import("digest", {anonymous = true})
local headers = import("headers", {anonymous = true})
local doc_text = import("doc_text", {anonymous = true})
local probe = import("probe", {anonymous = true})
local tbd = import("tbd", {anonymous = true})
local stream = import("stream", {anonymous = true})
local surface = import("surface", {anonymous = true})
local order = import("order", {anonymous = true})
local strings = import("strings", {anonymous = true})
local json = import("core.base.json")

-- The record's columns, in the order the file holds them (the declaration hash last).
local COLUMNS = {"kind", "api", "cls", "key", "introduced", "type", "availability", "hash", "value_status", "value", "host_value",
                 "value_source", "owned", "tbd", "shape", "measured", "declhash"}
local STRING_TYPES = {NSString = true, CFStringRef = true}
local LINKAGE = {extern = true}
local NULLABILITY = {_Nonnull = true, __nonnull = true, _Nullable = true, __nullable = true}
local IOS_TABLE = "cache-26.2/constants-26.2.tsv.gz"
local IOS_CACHE = {}  -- the table's values, read once per process: name -> value, and the names it holds with conflicting values

-- The name as the key of the record: its non-alphanumeric runs as one underscore, without the ones at the ends (the spec's key).
local function key_of(api)
    local key = string.gsub(api, "[^%w]+", "_")
    key = string.gsub(key, "^_+", "")
    return (string.gsub(key, "_+$", ""))
end

-- The declaration of a constant before its name, as the record holds it: the words before the name (its first whole-word occurrence),
-- without a linkage word at the start (extern, FOUNDATION_EXPORT) and the nullability words, one space between words.
local function declared_before(text, name)
    local from = 1
    while true do
        local s, e = string.find(text, name, from, true)
        if s == nil then
            return "-"
        end
        local before, after = string.sub(text, s - 1, s - 1), string.sub(text, e + 1, e + 1)
        if not string.find(before, "[%w_]") and not string.find(after, "[%w_]") then
            local head = string.gsub(string.sub(text, 1, s - 1), "^%s*", "")
            local first = string.match(head, "^([%w_]*)")
            if LINKAGE[first] or (first ~= "" and (string.find(first, "EXTERN", 1, true) or string.find(first, "EXPORT", 1, true))) then
                head = string.gsub(head, "^[%w_]*%s*", "", 1)
            end
            local words = {}
            for word in string.gmatch(head, "%S+") do
                if not NULLABILITY[word] then
                    table.insert(words, word)
                end
            end
            return table.concat(words, " ")
        end
        from = e + 1
    end
end

-- The availability macros of a declaration: each identifier that names AVAILABLE, DEPRECATED or OBSOLETED and its parenthesised
-- arguments (nested parentheses balanced), in the text's order, joined by one space.
local function availability_of(text)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(text, "[%w_]+", pos)
        if s == nil then
            break
        end
        local word = string.sub(text, s, e)
        local marked = string.find(word, "AVAILABLE", 1, true) or string.find(word, "DEPRECATED", 1, true)
                       or string.find(word, "OBSOLETED", 1, true)
        local open = string.match(string.sub(text, e + 1), "^%s*()%(")
        if marked and open then
            local at, depth = e + open, 0
            repeat
                local ch = string.sub(text, at, at)
                if ch == "(" then
                    depth = depth + 1
                elseif ch == ")" then
                    depth = depth - 1
                end
                at = at + 1
            until depth == 0 or at > #text
            table.insert(out, string.sub(text, s, at - 1))
            pos = at
        else
            pos = e + 1
        end
    end
    local joined = string.gsub(table.concat(out, " "), "%s+", " ")
    return (string.gsub(joined, "^%s*(.-)%s*$", "%1"))
end

-- The iOS release a shard row introduces its declaration in: the ios field of its availability ("ios=8.0/-/-/0", the platforms comma
-- separated, the field's first part the introduced release), or nil when the row names no iOS introduction.
local function ios_introduced(availability)
    for field in string.gmatch(availability or "", "[^,]+") do
        local release = string.match(field, "^ios=([^/]+)")
        if release ~= nil and release ~= "-" then
            return release
        end
    end
    return nil
end

-- The first identifier of a declaration's words that is not const or volatile: the type the shape reads ("NSString" when none).
local function base_of(decl)
    for word in string.gmatch(decl, "[%a_][%w_]*") do
        if word ~= "const" and word ~= "volatile" then
            return word
        end
    end
    return "NSString"
end

-- Whether a declaration names a string type: one of the words is NSString or CFStringRef, or a typedef of the shards that is.
local function is_string(decl, typedefs)
    for word in string.gmatch(decl, "[%a_][%w_]*") do
        if STRING_TYPES[word] or typedefs[word] then
            return true
        end
    end
    return false
end

-- The text as the body of an ObjC string literal, ASCII only, escaped as gen.py's objc_escape escapes it. The iOS table is read as
-- ASCII with errors="replace" (ios_constants), so each byte above 0x7f has already become one U+FFFD: every such byte is one \uFFFD here.
local function objc_escape(text)
    local out = {}
    for i = 1, #text do
        local byte = string.byte(text, i)
        local ch = string.sub(text, i, i)
        if ch == "\\" then
            table.insert(out, "\\\\")
        elseif ch == "\"" then
            table.insert(out, "\\\"")
        elseif ch == "\t" then
            table.insert(out, "\\t")
        elseif ch == "\n" then
            table.insert(out, "\\n")
        elseif byte >= 0x20 and byte < 0x7f then
            table.insert(out, ch)
        else
            table.insert(out, "\\uFFFD")
        end
    end
    return table.concat(out)
end

-- The iOS 26.2 cache's constants table: name -> value for every cfstring row, the first value a name has; names with two values are
-- in conflicts. Read through gzip's pipe, once per process.
local function ios_constants(path)
    if IOS_CACHE.values ~= nil then
        return IOS_CACHE.values, IOS_CACHE.conflicts
    end
    local values, conflicts, header = {}, {}, nil
    local status, err = stream.lines("gzip", {"-dc", path}, function (line)
        local cells = tsv.fields(line)
        if header == nil then
            header = {}
            for i, name in ipairs(cells) do
                header[name] = i
            end
            return
        end
        if cells[header.value_kind] == "cfstring" then
            local symbol = cells[header.symbol]
            local name = string.sub(symbol, 1, 1) == "_" and string.sub(symbol, 2) or symbol
            local value = cells[header.value]
            if values[name] ~= nil and values[name] ~= value then
                conflicts[name] = true
            end
            values[name] = values[name] or value
        end
    end)
    assert(status == 0, "gzip failed on " .. path .. ": " .. tostring(err))
    IOS_CACHE.values, IOS_CACHE.conflicts = values, conflicts
    return values, conflicts
end

-- The measured release of each symbol the gate's release-split output names (object, symbol, release), with the symbol's leading
-- underscore removed; a MIXED-RELEASES line is not a symbol.
local function measured_releases(path)
    local out = {}
    for _, line in ipairs(strings.lines(files.read_text(path) or "")) do
        local cells = tsv.fields(line)
        if #cells == 3 and string.sub(cells[2], 1, 1) == "_" and cells[2] ~= "_MIXED-RELEASES" then
            out[string.sub(cells[2], 2)] = cells[3]
        end
    end
    return out
end

-- The ledger rows the record covers: the constants that are missing at 6.1.3, lifted (code+lift), in the ledger's order.
local function ledger_constants(corpus, fw)
    local out = {}
    local text = files.read_text(surface.ledger_file(corpus, surface.ledger_6_1_3(), fw))
    for _, row in ipairs(tsv.records(text or "")) do
        if row.kind == "constant" and row.lang == "objc" and row.status == "missing" and row.needs == "code+lift" then
            table.insert(out, row)
        end
    end
    return out
end

-- The registry's owned constants: name -> the registry file that names it, the first file (in name order, the framework's own
-- single file last) that names it, as registry_constants has it.
local function owned_constants(tree, fw)
    local out = {}
    local candidates = files.glob(path.join(tree, layout.registry_dir(fw), "*.json"))
    table.sort(candidates, order.less)
    local single = path.join(tree, layout.constants().REGISTRY, fw .. ".json")
    if os.isfile(single) then
        table.insert(candidates, single)
    end
    for _, filepath in ipairs(candidates) do
        local data = json.decode(files.read_text(filepath))
        local relative = filepath == single and path.join(layout.constants().REGISTRY, fw .. ".json")
                         or path.join(layout.registry_dir(fw), path.filename(filepath))
        for _, entry in ipairs(data.entries or data) do
            if entry.kind == "constant" and out[entry.api] == nil then
                out[entry.api] = relative
            end
        end
    end
    return out
end

-- The typedefs of the shards that name a string type (string) and a CFStringRef (cf), read over the framework and the two it is
-- built on, as tools/gen.py string_typedefs and cf_typedefs read them.
local function typedefs_of(tree, fws)
    local string_names, cf_names = {}, {}
    for _, fw in ipairs(fws) do
        for _, r in ipairs(headers.shard_records(tree, fw)) do
            if r.kind == "typedef" then
                local name = string.match(r.usr or "", "([^@]+)$")
                local base = base_of(r.type or "")
                if name ~= nil and STRING_TYPES[base] then
                    string_names[name] = true
                    if base == "CFStringRef" then
                        cf_names[name] = true
                    end
                end
            end
        end
    end
    return string_names, cf_names
end

-- Writes the record of one framework (and measured.held-caches.tsv when measured is given). Returns the counts for the summary.
local function write_framework(args, fw)
    local tree, sdk = args.tree, args.sdk
    local ledger = ledger_constants(args.coordination, fw)
    local docs = doc_text.rows(tree, fw, sdk) or {usr = {}, api = {}}
    local shard_vars = {}
    for _, r in ipairs(headers.shard_value_records(tree, fw)) do
        if r.kind == "var" then
            local name = string.match(r.usr or "", "^c:@([^@]+)$")
            if name ~= nil then
                shard_vars[name] = r
            end
        end
    end
    local typedefs, cf_typedefs = typedefs_of(tree, {fw, "Foundation", "CoreFoundation"})
    local _, security_cf = typedefs_of(tree, {"Security"})
    for name in pairs(security_cf) do
        cf_typedefs[name] = true
    end
    local symbols = tbd.exports(sdk, fw)
    if fw ~= "Foundation" then
        local foundation_symbols = tbd.exports(sdk, "Foundation")
        for name in pairs(foundation_symbols) do
            symbols[name] = true
        end
    end
    local owned = owned_constants(tree, fw)
    local ios, ios_conflicts = ios_constants(path.join(args.coordination, IOS_TABLE))
    local conflicting = 0
    for _ in pairs(ios_conflicts) do
        conflicting = conflicting + 1
    end
    local measured = args.measured and measured_releases(args.measured) or {}

    local decls = {}
    for _, row in ipairs(ledger) do
        local doc = docs.usr["c:@" .. row.api]
        local decl = doc and doc.decl or "-"
        if decl ~= "-" then
            decls[row.api] = {decl = declared_before(decl, row.api), avail = availability_of(decl)}
        end
    end
    local strings_to_probe = {}
    for _, row in ipairs(ledger) do
        local d = decls[row.api]
        if owned[row.api] == nil and d ~= nil and is_string(d.decl, typedefs) then
            table.insert(strings_to_probe, row.api)
        end
    end
    local host = #strings_to_probe > 0 and probe.probe(tree, fw, strings_to_probe) or {}

    local lines, differences, disagreements = {table.concat(COLUMNS, "\t")}, {}, {}
    for _, row in ipairs(ledger) do
        local api = row.api
        local d = decls[api] or {decl = "", avail = ""}
        local var = shard_vars[api]
        local ir_ios = var and ios_introduced(var.availability)
        local introduced = ir_ios or row.introduced
        if ir_ios and ir_ios ~= row.introduced then
            table.insert(disagreements, {api, row.introduced, ir_ios})
        end
        local avail_column = d.avail ~= "" and d.avail or "-"
        local status, value = "-", "-"
        if owned[api] ~= nil then
            status, value = "owned:registry:" .. owned[api], "-"
        elseif d.decl == "" then
            status, value = "undeclared", "-"
        elseif not is_string(d.decl, typedefs) then
            status, value = "numeric", "-"
        else
            local found = host[api] or {"missing", "-"}
            status, value = found[1], found[2]
        end
        local host_value, source = value, "host-macos"
        if status == "found" and ios[api] ~= nil then
            value, source = objc_escape(ios[api]), "ios-26.2-cache"
            if value ~= host_value then
                table.insert(differences, {api, host_value, value})
            end
        elseif status ~= "found" and owned[api] == nil and ios[api] ~= nil and d.decl ~= "" and is_string(d.decl, typedefs) then
            -- the host does not carry the framework (AddressBookUI is iOS-only): the iOS cache is the only oracle, and it is the expectation
            status, value, host_value, source = "found", objc_escape(ios[api]), "-", "ios-26.2-cache (no host value)"
        end
        if status ~= "found" then
            value, host_value = "-", "-"
        end
        local cls_shape = (base_of(d.decl) == "CFStringRef" or cf_typedefs[base_of(d.decl)]) and "cf" or "ns"
        local record = {kind = "constant", api = api, cls = "-", key = key_of(api), introduced = introduced,
                        type = var and var.type or "-", availability = avail_column,
                        hash = digest.digest("constant", api, d.decl, d.avail), value_status = status, value = value,
                        host_value = host_value, value_source = source, owned = owned[api] and ("registry:" .. owned[api]) or "-",
                        tbd = symbols[api] and "exported" or "not-exported", shape = cls_shape,
                        measured = measured[api] or "-", declhash = var and var.declhash or "-"}
        local cells = {}
        for i, column in ipairs(COLUMNS) do
            cells[i] = record[column]
        end
        table.insert(lines, table.concat(cells, "\t"))
    end
    emit.file(layout.constant_record_path(tree, fw), table.concat(lines, "\n") .. "\n")
    if args.measured then
        local rows = {}
        for name, release in pairs(measured) do
            table.insert(rows, name .. "\t" .. release)
        end
        table.sort(rows, order.less)
        emit.file(path.join(layout.snap_dir(tree, fw), "measured.held-caches.tsv"),
                  "symbol\trelease\n" .. (#rows > 0 and table.concat(rows, "\n") .. "\n" or ""))
    end
    return #ledger, differences, disagreements, conflicting
end

-- Returns the exit status. --framework F writes one record; --all writes every surface framework that has a ledger.
function run(args)
    assert(args.sdk, "input needs --sdk: the iPhoneOS SDK the declarations are read from")
    assert(args.coordination, "input needs --coordination: the corpus folder (the ledgers and the iOS constants table)")
    local targets = args.all and surface.surface_frameworks(args.coordination) or {args.framework}
    local written, skipped = 0, 0
    for _, fw in ipairs(targets) do
        if surface.has_ledger(args.coordination, surface.ledger_6_1_3(), fw) then
            local rows, differences, disagreements, conflicting = write_framework(args, fw)
            written = written + 1
            print(string.format("input %s: %d constants, %d differ from the host (the iOS value wins), %d cache symbols with conflicting values, %d introduced releases differ from the ledger (the IR wins)",
                fw, rows, #differences, conflicting, #disagreements))
            for _, d in ipairs(disagreements) do
                print(string.format("  introduced %s: ledger %s, IR %s", d[1], d[2], d[3]))
            end
        else
            skipped = skipped + 1
        end
    end
    print(string.format("input: %d record(s) written, %d framework(s) without a ledger", written, skipped))
    -- a run that wrote nothing (a --framework with no ledger) checked nothing, and is not a pass
    return written > 0 and 0 or 1
end
