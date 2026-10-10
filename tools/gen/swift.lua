-- The Swift bucket: the rows of the 26.2 surface that are Swift, that no registry row names and that the 6.1.3 ledger misses, with what
-- the 26.2 Swift interface table says of each. The table has names, kinds and availability and no types, so nothing is written from
-- it beyond those. The surface is read through surface.lua (the only reader of that table), in the order the table first names each
-- row; the interface table is streamed a line at a time, keeping only the rows the bucket names.

local layout = import("layout", {anonymous = true})
local surface = import("surface", {anonymous = true})
local order = import("order", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local files = import("files", {anonymous = true})

local INTERFACE_FILE = "cache-26.2/swiftinterface-26.2.tsv"
local LEDGER_RELEASE = "ledger-w45"
local BUCKET_FILE = "swift/bucket.tsv"
local SWIFT_LANG = "swift"
local HEADER_OK = "header-ok"
local BUCKET_STATE = "swift: needs the Swift interface source"
local NO_VALUE = "-"
local BUCKET_KINDS = {method = true, property = true, constant = true}
local COLUMNS = {"framework", "kind", "api", "introduced", "unavailable", "via", "table_match", "table_kind", "table_introduced",
                 "table_unavailable", "demand_rank", "demand_apps", "impl_lead", "state"}

-- The name -> column index of a header line's cells.
local function index_of(header)
    local out = {}
    for i, name in ipairs(header) do
        out[name] = i
    end
    return out
end

-- A cell as the bucket writes it: an empty cell or a missing one is "-".
local function dash(value)
    if value == nil or value == "" then
        return NO_VALUE
    end
    return value
end

-- The bucket candidates, in the oracle's order: the frameworks sorted by bytes, and within each the surface rows in the order the
-- table first names them. A candidate is a method, property or constant row that is Swift, that the ledger lists with a status other
-- than header-ok, and whose api no registry row names.
local function bucket_candidates(tree, corpus)
    local out = {}
    for _, fw in ipairs(order.strings(surface.surface_frameworks(corpus))) do
        if os.isfile(path.join(corpus, LEDGER_RELEASE, fw .. ".tsv")) then
            local led6 = surface.ledger_status(corpus, fw, LEDGER_RELEASE)
            local registry = nil
            for _, row in ipairs(surface.ordered_rows(corpus, fw)) do
                local status = BUCKET_KINDS[row.kind] and row.lang == SWIFT_LANG and led6[surface.key(row.kind, row.api)]
                if status and status ~= HEADER_OK then
                    if registry == nil then
                        registry = surface.registry_entries(tree, fw)
                    end
                    if registry[row.api] == nil then
                        table.insert(out, row)
                    end
                end
            end
        end
    end
    return out
end

-- The first row of each (module, api) the Swift interface table holds, for the keys wanted (a set of "module\tapi").
local function table_matches(corpus, wanted)
    local matched = {}
    local index = nil
    for line in io.lines(path.join(corpus, INTERFACE_FILE)) do
        if line ~= "" then
            local cells = tsv.fields(line)
            if index == nil then
                index = index_of(cells)
            else
                local k = cells[index.module] .. "\t" .. cells[index.api]
                if wanted[k] and matched[k] == nil then
                    matched[k] = {kind = cells[index.kind], introduced = cells[index.introduced],
                                  unavailable = cells[index.unavailable]}
                end
            end
        end
    end
    return matched
end

-- Escapes every non-ASCII character of a text the way Python writes str.encode("ascii", "backslashreplace"): \xNN below 0x100,
-- \uNNNN below 0x10000, \UNNNNNNNN above. The text is UTF-8.
function ascii_escape(text)
    if not string.find(text, "[\128-\255]") then
        return text
    end
    local out = {}
    local pos = 1
    while pos <= #text do
        local c = string.byte(text, pos)
        local size = c < 0x80 and 1 or c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC0 and 2 or nil
        assert(size, "not UTF-8 text")
        if size == 1 then
            table.insert(out, string.char(c))
        else
            local code = c & (0xFF >> (size + 1))
            for i = 1, size - 1 do
                local continuation = string.byte(text, pos + i)
                assert(continuation and continuation >= 0x80 and continuation < 0xC0, "not UTF-8 text")
                code = (code << 6) | (continuation & 0x3F)
            end
            if code < 0x100 then
                table.insert(out, string.format("\\x%02x", code))
            elseif code < 0x10000 then
                table.insert(out, string.format("\\u%04x", code))
            else
                table.insert(out, string.format("\\U%08x", code))
            end
            pos = pos + size - 1
        end
        pos = pos + 1
    end
    return table.concat(out)
end

-- The bucket: rows (each a list of the cells COLUMNS names), the number of rows the interface table matched, and the number of
-- frameworks the rows are in. tree is the package tree (the registry is read from it); corpus is the corpus folder.
function bucket(tree, corpus)
    local candidates = bucket_candidates(tree, corpus)
    local wanted = {}
    for _, row in ipairs(candidates) do
        wanted[row.framework .. "\t" .. row.api] = true
    end
    local matched = table_matches(corpus, wanted)
    local rows, matches, frameworks = {}, 0, {}
    for _, row in ipairs(candidates) do
        local match = matched[row.framework .. "\t" .. row.api]
        if match then
            matches = matches + 1
        end
        frameworks[row.framework] = true
        table.insert(rows, {row.framework, row.kind, row.api, row.introduced, dash(row.unavailable), row.via,
                            match and "yes" or "no", match and match.kind or NO_VALUE,
                            match and match.introduced or NO_VALUE,
                            match and dash(match.unavailable) or NO_VALUE, dash(row["demand-rank"]),
                            dash(row["demand-apps"]), dash(row["impl-lead"]), BUCKET_STATE})
    end
    local count = 0
    for _ in pairs(frameworks) do
        count = count + 1
    end
    return rows, matches, count
end

-- The text of the bucket file: the header, then one line per row, in ASCII.
function bucket_text(rows)
    return ascii_escape(tsv.table_text(COLUMNS, rows))
end

-- The path of the bucket file under the package tree.
function bucket_path(tree)
    return path.join(tree, layout.constants().SNAP_ROOT, BUCKET_FILE)
end

-- The bucket rows of a framework, as the generator wrote them (bucket.tsv read back): framework -> list of records keyed by the
-- COLUMNS names. Empty when the file is not generated yet.
function read_bucket(tree)
    local out = {}
    local text = files.read_text(bucket_path(tree))
    if text == nil then
        return out
    end
    for _, row in ipairs(tsv.records(text)) do
        out[row.framework] = out[row.framework] or {}
        table.insert(out[row.framework], row)
    end
    return out
end
