-- `input`: the constant record of a framework, spec/<F>/constants.tsv (committed data, one row per constant the 6.1.3 ledger lists as
-- missing and the port has to export), and measured.held-caches.tsv when --measured names the gate's release-split output. It is the
-- port of the input stage of tools/gen.py, the oracle until its deletion: the record's rows equal the oracle's constant rows, byte for
-- byte, with the oracle's "decl" column named "type" (the proof is in the round-15 report). Each row is read from the source that owns
-- the fact:
--   * the declaration shard (spec/<F>/declarations.tsv, the extractor's IR): the typedefs, which give the string and CFString shapes
--     and the constant pointer typedefs (`typedef NSString *const X`, whose constants are const);
--   * the extractor's doc text (decls --doc, doc_text.lua): the declaration as written. The record's type is the text before the name
--     with its macros dropped (declared_type); its hash is the digest of that type and the availability macros the declaration writes;
--   * the coordination corpus: the ledger (the constants 6.1.3 lacks, in ledger order) and the iOS 26.2 cache's constants table (the value
--     of each string constant, and where it came from);
--   * the owned.tsv snapshot and the registry: a constant either names is owned, and its value is not read;
--   * the host oracle (probe.lua): the macOS value of each string constant the iOS table does not answer for;
--   * the SDK's .tbd (exported or not).
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

-- The record's columns, in the order the file holds them.
local COLUMNS = {"kind", "api", "cls", "key", "introduced", "type", "availability", "hash", "value_status", "value", "host_value",
                 "value_source", "owned", "tbd", "shape", "measured"}
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

-- The text before a name: what the declaration writes before its first whole-word occurrence of the name, or nil when it has none.
local function text_before(text, name)
    local from = 1
    while true do
        local s, e = string.find(text, name, from, true)
        if s == nil then
            return nil
        end
        local before, after = string.sub(text, s - 1, s - 1), string.sub(text, e + 1, e + 1)
        if not string.find(before, "[%w_]") and not string.find(after, "[%w_]") then
            return string.sub(text, 1, s - 1)
        end
        from = e + 1
    end
end

-- Whether a word is a macro the type drops (gen.py's strip_macros): one that names AVAILABLE, DEPRECATED or OBSOLETED, an API_, NS_,
-- OS_, CF_ or __ macro in capitals, or __attribute__.
local function is_macro(word)
    return string.find(word, "AVAILABLE", 1, true) ~= nil or string.find(word, "DEPRECATED", 1, true) ~= nil
        or string.find(word, "OBSOLETED", 1, true) ~= nil or word == "__attribute__"
        or string.match(word, "^API_?%u[%u%d_]*$") ~= nil or string.match(word, "^NS_?%u[%u%d_]*$") ~= nil
        or string.match(word, "^OS_?%u[%u%d_]*$") ~= nil or string.match(word, "^CF_?%u[%u%d_]*$") ~= nil
        or string.match(word, "^__%u[%u%d_]*$") ~= nil
end

-- The position after the parenthesised group that opens at `at` (nested parentheses balanced), or after the text.
local function after_group(text, at)
    local depth = 0
    repeat
        local ch = string.sub(text, at, at)
        if ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
        end
        at = at + 1
    until depth == 0 or at > #text
    return at
end

-- The type a declaration writes before a name, as gen.py's declared_type writes it: the macros and their argument lists dropped
-- (availability, attributes, and the all-capitals project macros such as MTL_EXTERN), the linkage and nullability words dropped, and
-- one space between the words that remain.
local function declared_type(before)
    local out, pos = {}, 1
    while true do
        local s, e = string.find(before, "[%a_][%w_]*", pos)
        if s == nil then
            break
        end
        table.insert(out, string.sub(before, pos, s - 1))
        local word = string.sub(before, s, e)
        pos = e + 1
        if is_macro(word) then
            local open = string.match(string.sub(before, e + 1), "^%s*()%(")
            if open ~= nil then
                pos = after_group(before, e + open)
            end
        else
            table.insert(out, word)
        end
    end
    table.insert(out, string.sub(before, pos))
    local text = string.gsub(table.concat(out), "%f[%w_][%u][%u%d]*_[%u%d_]+%f[^%w_]", " ")
    local words = {}
    for word in string.gmatch(text, "%S+") do
        local linkage = string.match(word, "^[%w_]*$") ~= nil and (string.find(word, "EXTERN", 1, true) ~= nil
                        or string.find(word, "EXPORT", 1, true) ~= nil)
        if not LINKAGE[word] and not NULLABILITY[word] and not linkage then
            table.insert(words, word)
        end
    end
    return table.concat(words, " ")
end

-- The declared type with "const " in front when it names a constant pointer typedef and does not say const itself: a constant of
-- `typedef NSString *const X` is const (gen.py's constant_decls prepends it).
local function with_const(decl, const_typedefs)
    local words = {}
    for word in string.gmatch(decl, "%S+") do
        if word == "const" then
            return decl
        end
        table.insert(words, word)
    end
    for _, word in ipairs(words) do
        if const_typedefs[word] then
            return "const " .. decl
        end
    end
    return decl
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

-- The text as the body of an ObjC string literal, ASCII only, escaped as gen.py@52253c0650's objc_escape escapes it. The iOS table is read as
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

-- The measured release of each symbol: the gate's release-split output names (object, symbol, release), with the symbol's leading
-- underscore removed, and a MIXED-RELEASES line is not a symbol; or a measured.held-caches.tsv snapshot (symbol, release), whose
-- header line is not a symbol. The snapshot is the file the writer makes from the gate's output, so reading it back reproduces it.
local function measured_releases(path)
    local out = {}
    for _, line in ipairs(strings.lines(files.read_text(path) or "")) do
        local cells = tsv.fields(line)
        if #cells == 3 and string.sub(cells[2], 1, 1) == "_" and cells[2] ~= "_MIXED-RELEASES" then
            out[string.sub(cells[2], 2)] = cells[3]
        elseif #cells == 2 and cells[1] ~= "symbol" then
            out[cells[1]] = cells[2]
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

-- The owned constants: name -> the label of the decision that owns it. The registry gives "registry:<file>": the first file (in
-- name order, the framework's own single file last) that names it, as registry_constants has it. The snapshot owned.tsv (name,
-- branch) in the framework's spec folder gives the branch: a constant a live branch owns, whose commit is not in this tree
-- (AVFAudio's info-dictionary keys, v-avmidi), so the record reproduces the owner the oracle was given with --owned.
local function owned_constants(tree, fw)
    local out = {}
    -- the snapshot first: gen.py's cmd_input reads owned.tsv, then adds the registry's names it does not hold
    for _, line in ipairs(strings.lines(files.read_text(path.join(layout.snap_dir(tree, fw), "owned.tsv")) or "")) do
        local cells = tsv.fields(line)
        if #cells == 2 and out[cells[1]] == nil then
            out[cells[1]] = cells[2]
        end
    end
    -- the registry files in full-path order (gen.py's registry_constants sorts them as paths: the framework's single file sorts first)
    local found = {}
    for _, filepath in ipairs(files.glob(path.join(tree, layout.registry_dir(fw), "*.json"))) do
        table.insert(found, {full = filepath, relative = path.join(layout.registry_dir(fw), path.filename(filepath))})
    end
    local single = path.join(tree, layout.constants().REGISTRY, fw .. ".json")
    if os.isfile(single) then
        table.insert(found, {full = single, relative = path.join(layout.constants().REGISTRY, fw .. ".json")})
    end
    table.sort(found, function (a, b) return order.less(a.full, b.full) end)
    for _, file in ipairs(found) do
        local data = json.decode(files.read_text(file.full))
        for _, entry in ipairs(data.entries or data) do
            if entry.kind == "constant" and out[entry.api] == nil then
                out[entry.api] = "registry:" .. file.relative
            end
        end
    end
    return out
end

-- The typedefs of the shards that name a string type (string), a CFStringRef (cf), and a constant NSString pointer (const, the
-- `NSString *const` shape), read over the framework and the two it is built on, as gen.py's string_typedefs, cf_typedefs and
-- const_typedefs read them.
local function typedefs_of(tree, fws)
    local string_names, cf_names, const_names = {}, {}, {}
    for _, fw in ipairs(fws) do
        for _, r in ipairs(headers.shard_records(tree, fw)) do
            if r.kind == "typedef" then
                local name = string.match(r.usr or "", "([^@]+)$")
                local base = base_of(r.type or "")
                if name ~= nil and STRING_TYPES[base] then
                    string_names[name] = true
                    if base == "CFStringRef" then
                        cf_names[name] = true
                    elseif string.find(r.type or "", "%*%s*const%s*$") then
                        const_names[name] = true
                    end
                end
            end
        end
    end
    return string_names, cf_names, const_names
end

-- Writes the record of one framework (and measured.held-caches.tsv when measured is given). Returns the counts for the summary.
local function write_framework(args, fw)
    local tree, sdk = args.tree, args.sdk
    local ledger = ledger_constants(args.coordination, fw)
    -- a framework the extractor does not list has no declarations to read: its constants would all come out "undeclared", so it fails
    local docs, reason = doc_text.rows(tree, fw, sdk)
    assert(docs ~= nil, string.format("input %s: %s, so its constants cannot be read", fw, reason))
    local typedefs, cf_typedefs, const_typedefs = typedefs_of(tree, {fw, "Foundation", "CoreFoundation"})
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
    -- An enumerator the shard holds is declared, and its value is the one clang evaluates: the shard's value column (round 16, the
    -- owner's rule; gen.py's cmd_input reads the same column). The first row a name has wins, as in the oracle.
    local enum_values = {}
    for _, r in ipairs(headers.shard_value_records(tree, fw)) do
        local name = r.kind == "enumconst" and string.match(r.usr, "@([^@]+)$")
        if name and enum_values[name] == nil then
            enum_values[name] = r.value
        end
    end
    local ios, ios_conflicts = ios_constants(path.join(args.coordination, IOS_TABLE))
    local conflicting = 0
    for _ in pairs(ios_conflicts) do
        conflicting = conflicting + 1
    end
    -- The measured releases: the --measured file, or the committed measured.held-caches.tsv of a framework that has one (the read-back
    -- of its last release split). Without the default, input --all on a clean checkout dropped the measured column of those records
    -- (Round 14: the data commit's regeneration passed the snapshot by hand). Only --measured writes the snapshot back. Under --all
    -- the --measured file is neither read nor written, as the oracle's cmd_input_all passes measured=None.
    local held = path.join(layout.snap_dir(tree, fw), "measured.held-caches.tsv")
    local measured = {}
    if args.measured and not args.all then
        measured = measured_releases(args.measured)
    elseif os.isfile(held) then
        measured = measured_releases(held)
    end

    local decls = {}
    for _, row in ipairs(ledger) do
        local doc = docs.usr["c:@" .. row.api]
        local before = doc and doc.decl and text_before(doc.decl, row.api)
        if before ~= nil then
            decls[row.api] = {decl = with_const(declared_type(before), const_typedefs), avail = availability_of(doc.decl)}
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

    local lines, differences = {table.concat(COLUMNS, "\t")}, {}
    for _, row in ipairs(ledger) do
        local api = row.api
        local d = decls[api] or {decl = "", avail = ""}
        local avail_column = d.avail ~= "" and d.avail or "-"
        local status, value = "-", "-"
        if owned[api] ~= nil then
            status, value = "owned:" .. owned[api], "-"
        elseif d.decl == "" and enum_values[api] ~= nil and enum_values[api] ~= "-" and enum_values[api] ~= "" then
            status, value = "found", enum_values[api]
        elseif d.decl == "" then
            status, value = "undeclared", "-"
        elseif not is_string(d.decl, typedefs) then
            status, value = "numeric", "-"
        else
            local found = host[api] or {"missing", "-"}
            status, value = found[1], found[2]
        end
        local host_value, source = value, "host-macos"
        if status == "found" and d.decl == "" then
            -- an enumerator is read from the SDK's declaration, not probed on the host: it has no host value
            host_value, source = "-", "sdk-enum-value"
        end
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
        local record = {kind = "constant", api = api, cls = "-", key = key_of(api), introduced = row.introduced,
                        type = d.decl ~= "" and d.decl or "-", availability = avail_column,
                        hash = digest.digest("constant", api, d.decl, d.avail), value_status = status, value = value,
                        host_value = host_value, value_source = source, owned = owned[api] or "-",
                        tbd = symbols[api] and "exported" or "not-exported", shape = cls_shape,
                        measured = measured[api] or "-"}
        local cells = {}
        for i, column in ipairs(COLUMNS) do
            cells[i] = record[column]
        end
        table.insert(lines, table.concat(cells, "\t"))
    end
    -- A framework with no constant has no record: check fails on a record that holds no rows, so none is written.
    if #lines > 1 then
        emit.file(layout.constant_record_path(tree, fw), table.concat(lines, "\n") .. "\n")
    end
    if args.measured and not args.all then
        local rows = {}
        for name, release in pairs(measured) do
            table.insert(rows, name .. "\t" .. release)
        end
        table.sort(rows, order.less)
        emit.file(path.join(layout.snap_dir(tree, fw), "measured.held-caches.tsv"),
                  "symbol\trelease\n" .. (#rows > 0 and table.concat(rows, "\n") .. "\n" or ""))
    end
    return #ledger, differences, conflicting
end

-- Returns the exit status. --framework F writes one record; --all writes every surface framework that has a ledger.
function run(args)
    assert(args.sdk, "input needs --sdk: the iPhoneOS SDK the declarations are read from")
    assert(args.coordination, "input needs --coordination: the corpus folder (the ledgers and the iOS constants table)")
    -- a required input that is not there fails with its path named, before anything is written: a missing --measured file would
    -- otherwise write a header-only snapshot
    assert(os.isdir(args.sdk), "input: the --sdk folder is not found: " .. args.sdk)
    assert(os.isdir(args.coordination), "input: the --coordination folder is not found: " .. args.coordination)
    if args.measured and not args.all then
        assert(os.isfile(args.measured), "input: the --measured file is not found: " .. args.measured)
    end
    -- the committed skip ledger (spec/input-skips.tsv): a skip it names stays named; a skip it does not name fails the run. Only the
    -- names decide: a reason is a note, with the SDK folder written as <sdk>.
    local known_skips = args.all and surface.skip_ledger(args.tree) or {}
    local targets = args.all and surface.surface_frameworks(args.coordination) or {args.framework}
    local written, without_ledger = 0, 0
    -- a framework the inputs cannot read is named and skipped under --all (the oracle's cmd_input_all: "a framework the inputs
    -- cannot read is named in the scope, not hidden"); a single --framework run fails with the error. A skip the ledger does not
    -- name fails the run: the known skips are the committed ones, and a new one is a regression.
    local unreadable, unknown = {}, {}
    for _, fw in ipairs(targets) do
        if surface.has_ledger(args.coordination, surface.ledger_6_1_3(), fw) then
            local rows, differences, conflicting
            if args.all then
                local failure = nil
                try {
                    function()
                        rows, differences, conflicting = write_framework(args, fw)
                    end,
                    catch {
                        function(e)
                            failure = e
                        end
                    }
                }
                if failure then
                    local first = string.match(tostring(failure), "^[^\n]*") or ""
                    table.insert(unreadable, string.format("%s (%s)", fw, string.sub(first, 1, 80)))
                    if known_skips[fw] == nil then
                        table.insert(unknown, fw)
                    end
                    print(string.format("input %s: skipped: %s", fw, first))
                    goto continue
                end
            else
                rows, differences, conflicting = write_framework(args, fw)
            end
            written = written + 1
            print(string.format("input %s: %d constants, %d differ from the host (the iOS value wins), %d cache symbols with conflicting values",
                fw, rows, #differences, conflicting))
        else
            without_ledger = without_ledger + 1
        end
        ::continue::
    end
    if args.all then
        print(string.format("input --all: %d built, %d skipped (%s), %d without a ledger", written, #unreadable,
            table.concat(unreadable, ", "), without_ledger))
        if #unknown > 0 then
            print(string.format("input --all: %d skipped framework(s) are not on the skip ledger (spec/input-skips.tsv): %s",
                #unknown, table.concat(unknown, ", ")))
        end
    else
        print(string.format("input: %d record(s) written, %d framework(s) without a ledger", written, without_ledger))
    end
    -- a skip the ledger does not name fails the run; so does a run that wrote nothing (a --framework with no ledger checked nothing)
    if #unknown > 0 then
        return 1
    end
    return written > 0 and 0 or 1
end
