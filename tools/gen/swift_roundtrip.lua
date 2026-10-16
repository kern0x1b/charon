-- The round trip of the Swift skeleton (swift_render.lua), the proof that the rendered text means what the SDK means: a module
-- rendered from the SDK's model is compiled with xcrun swiftc under its own name, dumped with the digester (its folder ahead of the
-- SDK on the search path) and the model of that dump is compared with the SDK's on the key (kind, usr, container, name, side) and
-- the signature cells. A module that does not compile may give no dump: the digester cannot load a module with an unresolved type
-- (an error type), so its first error is the result and no row is compared. The build products are never committed.

local stream = import("stream", {anonymous = true})
local json = import("core.base.json")

local NO_VALUE = "-"
-- The cells a declaration's signature is made of, besides its key. The model's own cells: the digester's, read from the dump.
local SIGNATURE = {"type", "params", "generic_sig", "conformances", "superclass", "throwing", "async", "mutating", "attributes",
                   "accessors", "storage", "is_let", "is_open", "requirement", "in_extension", "owner_module", "raw", "alias",
                   "overriding", "init_kind", "availability"}
-- The tab joins the key's cells: no declaration name holds one.
local KEY_SEPARATOR = "\t"

-- The key of a row: its kind, usr, container, name and side.
local function key_of(row)
    return table.concat({row.kind, row.usr, row.container, row.name, row.side}, KEY_SEPARATOR)
end

-- A row's label for a report: its kind and its api (container and name, or the name).
local function label_of(row)
    local api = row.container ~= NO_VALUE and (row.container .. "." .. row.name) or row.name
    return row.kind .. " " .. api
end

-- The diagnostics of a compiler's output: how many errors it printed and the first one, or 0 and nil.
function diagnostics(text)
    local count, first = 0, nil
    for line in string.gmatch(text or "", "[^\n]+") do
        if string.find(line, ": error: ", 1, true) then
            count = count + 1
            first = first or line
        end
    end
    return count, first
end

-- Compiles a rendered source under its module name into module_dir, through heavy.sh. The compiler admits a module with errors
-- (so the dump can still be read when the errors are not error types), and its output is read whole. Returns the number of
-- errors, the first one and the exit status.
function compile(heavy, triple, sdk, source, module_dir, name)
    local status, out = stream.text(heavy, {"/bin/sh", "-c", 'exec "$0" "$@" 2>&1', "xcrun", "swiftc", "-parse-as-library",
                                             "-Xfrontend", "-experimental-allow-module-with-compiler-errors", "-emit-module",
                                             "-module-name", name, "-target", triple, "-sdk", sdk,
                                             "-emit-module-path", path.join(module_dir, name .. ".swiftmodule"), source})
    local count, first = diagnostics(out)
    return count, first, status
end

-- The digester's dump of a module compiled into module_dir, with that folder ahead of the SDK. Returns the JSON root, or nil and the
-- reason: the digester's exit status and the tail of its error output (a crash on an error type is one of these).
function dump(heavy, triple, sdk, module_dir, name)
    local json_path = path.join(module_dir, "dump.json")
    local status, _, errors = stream.text(heavy, {"xcrun", "swift-api-digester", "-dump-sdk", "-module", name, "-I", module_dir,
                                                   "-target", triple, "-sdk", sdk, "-avoid-location", "-avoid-tool-args",
                                                   "-o", json_path})
    if status ~= 0 then
        return nil, string.format("the digester exited %s: %s", tostring(status), string.sub(errors or "", -200))
    end
    local handle = io.open(json_path, "rb")
    if handle == nil then
        return nil, "the digester wrote no dump"
    end
    local payload = json.decode(handle:read("a"))
    handle:close()
    if payload == nil or payload.ABIRoot == nil then
        return nil, "the digester wrote no ABI root"
    end
    return payload.ABIRoot
end

-- Compares the SDK's model rows with ours. Returns a result: the row counts, the rows equal on every signature cell, the rows
-- missing from ours, the count of ours with no SDK row, the rows that differ, counted per cell, and one example per cell.
function compare(sdk_rows, our_rows)
    local ours, duplicates = {}, 0
    for _, row in ipairs(our_rows) do
        local key = key_of(row)
        if ours[key] then
            duplicates = duplicates + 1
        else
            ours[key] = row
        end
    end
    local result = {sdk = #sdk_rows, ours = #our_rows, equal = 0, missing = {}, extra = 0, duplicates = duplicates,
                    causes = {}, examples = {}}
    local matched = {}
    for _, row in ipairs(sdk_rows) do
        local key = key_of(row)
        local other = ours[key]
        if other == nil then
            table.insert(result.missing, label_of(row))
        else
            matched[key] = true
            local differs = false
            for _, cell in ipairs(SIGNATURE) do
                if row[cell] ~= other[cell] then
                    differs = true
                    result.causes[cell] = (result.causes[cell] or 0) + 1
                    if result.examples[cell] == nil then
                        result.examples[cell] = string.format("%s: sdk %s, ours %s", label_of(row), tostring(row[cell]),
                                                              tostring(other[cell]))
                    end
                end
            end
            if not differs then
                result.equal = result.equal + 1
            end
        end
    end
    for key in pairs(ours) do
        if not matched[key] then
            result.extra = result.extra + 1
        end
    end
    return result
end
