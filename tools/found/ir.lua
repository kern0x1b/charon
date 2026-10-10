-- The declaration IR of the iOS SDK (section 5.1 of coordination/wave-2026-10-03/design-foundation.md): one row per declaration,
-- read by the decls extractor (libclang) from every framework of the SDK and every framework nested in one (Accelerate's vImage
-- and vecLib; the helper bundles outside Frameworks/ are not followed). Each framework is one translation unit, parsed one at a time
-- under a timeout.
--
-- What is committed is the spec's shard per framework, packages/a/apple-backports/spec/<Framework>/declarations.tsv (a nested
-- framework's is spec/<Outer>/<Inner>/declarations.tsv): only the columns the generator reads (SHARD_NAMES), uncompressed, with a
-- header line that records the libclang and the SDK that made it. The full 18-column IR, for documentation, is a build product: write
-- it to IR_FULL when that is set.
--
-- usage (from the repository root): IR_SDK=<iPhoneOS26.2.sdk> [IR_MODE=write|check|conflicts] xmake l ./tools/found/ir.lua
--   IR_MODE=write (default) regenerates the shards whose content changed, removes the shards of frameworks decls no longer lists,
--                 and rewrites tools/found/unparsed.tsv. It fails, and writes nothing, when decls fails on a framework (a timeout or a
--                 crash; decls' own unparsed row is a result, not a failure), when a framework decls still lists has a committed shard
--                 and no shard this run gives it, or when a conflict is not listed in tools/found/conflicts.tsv (or a listed one is no
--                 longer a conflict).
--   IR_MODE=check the same regeneration in memory: it fails naming the difference when decls fails, when the extractor's libclang
--                 differs from the one the shards record (a re-pin is a reviewed event), when a shard differs, when a shard is stale,
--                 or on a conflict list mismatch.
--   IR_MODE=conflicts prints every conflict the extractor found, for review, and writes nothing.
--   IR_MODE=gaps prints each framework of IR_SNAPSHOT (one folder per framework) that has no shard, with the category the
--                 extractor's own result gives it, and writes nothing.
--   IR_MODE=docs runs the doc-time pass (decls --doc) over every framework and prints its rows to stdout, one line per declaration,
--                 and writes nothing; the last line is a # comment with the counts and the time. The doc generator reads the same
--                 rows from decls directly; this mode is the measurement of the pass over the whole SDK.
--   IR_SPEC    the spec folder (default packages/a/apple-backports/spec).
--   IR_CONFLICTS and IR_UNPARSED the reviewed conflict list and the unparsed list (default tools/found/conflicts.tsv and
--                 tools/found/unparsed.tsv; the tests use their own).
--   IR_FULL    if set, the full 17-column IR is written there (a build product, not committed).
--   IR_DECLS   the extractor binary (default: the xmake build product of tools/found).
--   IR_TIMEOUT seconds per framework (default 300).
--   IR_CONFIG  the extractor's configuration folder (usr-modules.tsv and fallback.tsv), read by decls from the repository root
--                 (default tools/found/config). The usr/include modules are derived from the SDK's module maps, less that list.
--   IR_REPIN   if set, write mode re-records the shards whose libclang identity differs from this machine's (the version, the
--                 digest of the dylib it loads, and the target). Without it a difference is refused in both modes: a re-pin is a
--                 reviewed event (review F8).
--   IR_NO_OWN  the reviewed list of the frameworks with no shard whose headers declare nothing of their own (default
--                 tools/found/config/no-own.tsv). write and check fail on a framework with no shard that is neither in the unparsed list nor
--                 in this one, and on a row that names a framework with a shard or no framework of the SDK (coordinator ruling 5).
local SDK = os.getenv("IR_SDK")
if not SDK then raise("IR_SDK must name the iPhoneOS SDK (for example .../iPhoneOS26.2.sdk)") end
SDK = path.absolute(SDK)
local MODE = os.getenv("IR_MODE") or "write"
local SPEC = os.getenv("IR_SPEC") or "packages/a/apple-backports/spec"
local FULL = os.getenv("IR_FULL")
local DECLS = os.getenv("IR_DECLS") or "build/macosx/arm64/release/decls"
local TIMEOUT = os.getenv("IR_TIMEOUT") or "300"
local CONFLICTS = os.getenv("IR_CONFLICTS") or path.join("tools", "found", "conflicts.tsv")
local UNPARSED = os.getenv("IR_UNPARSED") or path.join("tools", "found", "unparsed.tsv")
local stream = import("gen.stream", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
-- decls, through a pipe (no temporary file): the lines it printed. A run that exits non-zero raises with its own message, so a failed
-- extractor never reaches a write. decls' exit codes: 2 for a configuration, file system or refusal error (each names its path), 1 for
-- a doc-mode parse failure.
local function decls_run(args)
    local lines = {}
    local status, errors = stream.run("/usr/bin/env", table.join({"IR_SDK=" .. SDK, DECLS}, args), function (line)
        table.insert(lines, line)
    end)
    return lines, status, (errors:gsub("%s+$", ""))
end
local function decls(args)
    local lines, status, errors = decls_run(args)
    if status ~= 0 then
        raise(string.format("decls %s exited %d: %s", table.concat(args, " "), status, errors))
    end
    return lines
end
local NO_OWN = os.getenv("IR_NO_OWN") or path.join("tools", "found", "config", "no-own.tsv")
-- the target the extractor compiles for (decls owns it: decls --target)
local TRIPLE = (decls({"--target"})[1]:gsub("%s+$", ""))
local COLUMNS = 18
-- The columns a shard keeps: kind, usr, container, name, side, type (typedef rows only), avail, message, declhash, value (an enum constant's
-- value as clang evaluates it: the other rows leave it "-", ruling 2). The IR's other columns are derived or are
-- build products: framework is the folder, availhash is derived from avail, header and line are for documentation, decl is for the
-- docs (ruling D8: re-derived from clang at doc time), and type, params, nullab, attrs and value are inside the declaration hash.
-- name and side are stored only where the USR does not give them (shard.lua). avail and message are rendered by the generator
-- (avail.lua, ruling D7).
local SHARD_NAMES = "kind,usr,container,name,side,type,params,attrs,availability,message,declhash,value"
local shard = import("shard", {rootdir = path.join(os.curdir(), "tools", "found")})
local avail = import("avail", {rootdir = path.join(os.curdir(), "tools", "found")})
-- the one atomic writer of the generators (tools/atomic.lua, shared with tools/gen/emit.lua)
local atomic = import("atomic", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
local SDK_NAME  -- the SDK's name without its path or .sdk suffix, as the shards record it

SDK = path.absolute(SDK)
SPEC = path.absolute(SPEC)
if MODE ~= "write" and MODE ~= "check" and MODE ~= "conflicts" and MODE ~= "gaps" and MODE ~= "docs" then
    raise("IR_MODE must be write, check, conflicts, gaps or docs, not " .. MODE)
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The tab-separated cells of one line.
local function cells_of(line)
    local out = {}
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(out, cell) end
    return out
end

-- The redacted SDK path is what the rows carry: the rows must not depend on where the SDK is installed.
local function redact(s)
    return (s:gsub(SDK:gsub("%p", "%%%0"), "<sdk>"))
end

-- The rows of one framework (COLUMNS cells each, newline-terminated), or the extractor's own unparsed row. A run of decls that fails
-- (a timeout ends it by SIGALRM, a crash, a usage error) raises in every mode: it is not a result, and nothing is written after it.
-- A run that prints no rows at all raises for the same reason.
local function parse(f)
    local lines, status, errors = decls_run({"--timeout", TIMEOUT, f.name})
    if status ~= 0 then
        raise(string.format("%s: decls did not finish (status %d)%s", f.name, status, errors ~= "" and (": " .. redact(errors)) or ""))
    end
    if #lines == 0 then raise(f.name .. ": decls printed no rows") end
    for _, line in ipairs(lines) do
        if #cells_of(line) ~= COLUMNS then raise(f.name .. ": a row has " .. #cells_of(line) .. " columns, not " .. COLUMNS) end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- The extractor writes one row of kind unparsed, instead of rows, for a framework that does not parse.
local function is_unparsed(out)
    return cells_of(out:match("^[^\n]*"))[2] == "unparsed"
end

local function unparsed_row(name, reason)
    local row = {name, "unparsed", "-", "-", redact(reason)}
    for _ = #row + 1, COLUMNS do table.insert(row, "-") end
    return table.concat(row, "\t") .. "\n"
end

-- The header line of a shard: what made it, so a re-pin is visible in the file.
local function shard_header(libclang)
    return "#libclang=" .. libclang .. "\tsdk=" .. SDK_NAME .. "\tcolumns=" .. SHARD_NAMES .. "\n"
end

local function shard_path(label)
    return path.join(SPEC, label, "declarations.tsv")
end

-- The reviewed conflicts: key -> the cells of its line in tools/found/conflicts.tsv. The key is the first seven cells of a line.
local function listed_conflicts()
    local listed = {}
    if not os.isfile(CONFLICTS) then return listed end
    for line in io.lines(CONFLICTS) do
        if line:find("^[^#]") and not line:find("^framework\t") then
            local c = cells_of(line)
            listed[table.concat(c, "\t", 1, 7)] = c
        end
    end
    return listed
end

local started = os.mclock()
-- decls resolves the SDK from IR_SDK, so every extractor run below sees the absolute path the sweep uses
os.setenv("IR_SDK", SDK)
-- the identity of the extractor: its libclang version, the digest of the dylib it loads, and the target (decls --version)
local libclang = (decls({"--version"})[1]:gsub("%s+$", ""))
SDK_NAME = (path.basename(SDK):gsub("%.sdk$", ""))

-- The frameworks the sweep covers, as decls lists them (its name and its root): the one code path for the list, the headers and the
-- doc mode.
local frameworks = {}
for _, line in ipairs(decls({"--list"})) do
    local name, root = line:match("^([^\t]+)\t(.+)$")
    table.insert(frameworks, {name = name, root = root})
end
-- The doc-time rows of one framework (decls --doc), or nil when the extractor does not parse it (its own status is an error).
local function doc_rows(f)
    local out
    try {
        function () out = table.concat(decls({"--doc", "--timeout", TIMEOUT, f.name}), "\n") .. "\n" end,
        catch {
            function () out = nil end
        }
    }
    return out
end

-- The doc-time pass over the SDK (IR_MODE=docs): the rows of every framework that parses, on stdout; nothing is written.
if MODE == "docs" then
    local started = os.mclock()
    local seen, parsed, rows, bytes = 0, 0, 0, 0
    for _, f in ipairs(frameworks) do
        local out = doc_rows(f)
        seen = seen + 1
        if out then
            parsed = parsed + 1
            bytes = bytes + #out
            for _ in out:gmatch("\n") do rows = rows + 1 end
            io.write(out)
        end
    end
    print(string.format("# doc frameworks %d, parsed %d, rows %d, bytes %d, %.1f s", seen, parsed, rows, bytes,
        (os.mclock() - started) / 1000))
    return
end

local parsed, rows = 0, 0
local full = {table.concat({"-", "meta", "-", "-", "-", "-", "-", "-", "-", "-", "libclang=" .. libclang, "triple=" .. TRIPLE,
    "sdk=" .. SDK_NAME, "-", "-", "-", "-", "-"}, "\t") .. "\n"}
local shards, unparsed, conflicts = {}, {}, {}
local census_of = {}  -- framework -> {own, foreign}: the extractor's count of the declarations its translation unit reaches
for _, f in ipairs(frameworks) do
    local out = parse(f)
    if not is_unparsed(out) then
        parsed = parsed + 1
        local lines = {shard_header(libclang):sub(1, -2)}
        local order, group, marks = {}, {}, {}
        for line in out:gmatch("[^\n]+") do
            local c = cells_of(line)
            if c[2] == "census" then
                census_of[f.name] = {own = tonumber(c[5]:match("own=(%d+)")), foreign = tonumber(c[11]:match("foreign=(%d+)"))}
                table.insert(full, line .. "\n")
            elseif c[2] == "conflict" then
                -- the marker names the key (kind, usr, container, name, side) and how the extractor resolved it
                table.insert(marks, {key = table.concat({c[1], c[7], c[3], c[4], c[5], c[6], c[9]}, "\t"), resolution = c[9],
                    variants = c[11], entity = table.concat({c[7], c[3], c[4], c[5], c[6]}, "\t")})
            else
                local key = table.concat(c, "\t", 2, 6)
                if not group[key] then
                    group[key] = {}
                    table.insert(order, key)
                end
                table.insert(group[key], c)
            end
        end
        local resolution_of = {}
        for _, mark in ipairs(marks) do resolution_of[mark.entity] = mark.resolution end
        -- one row per declaration: the variants of a key are merged by the rule of avail.lua, and only a key marked merged has any
        local written, result_of = {}, {}
        for _, key in ipairs(order) do
            local variants = group[key]
            local row = variants[1]
            if #variants > 1 then
                if resolution_of[key] ~= "merged" then raise(f.name .. ": " .. key .. " has several rows and no merged conflict") end
                local input = {}
                for _, v in ipairs(variants) do table.insert(input, {avail = v[9], message = v[18]}) end
                local m = avail.merge(input)
                row = {}
                for i = 1, COLUMNS do row[i] = variants[1][i] end
                row[9], row[18] = m.avail, m.message
                row[16] = (decls({"--digest", m.avail})[1]:gsub("%s+$", ""))
            end
            result_of[key] = row[9]
            table.insert(written, row)
        end
        for _, mark in ipairs(marks) do
            if not result_of[mark.entity] then raise(f.name .. ": a conflict marks a key with no row: " .. mark.entity) end
            table.insert(conflicts, {key = mark.key, variants = mark.variants, result = result_of[mark.entity]})
        end
        for _, row in ipairs(written) do
            rows = rows + 1
            local kind, usr, name, side = row[2], row[3], row[5], row[6]
            local stored_name, stored_side = shard.encode(kind, usr, name, side)
            local back_name, back_side = shard.decode(kind, usr, stored_name, stored_side)
            if back_name ~= name or back_side ~= side then
                raise(f.name .. ": the name or side of a " .. kind .. " row does not round trip: " .. usr)
            end
            -- an accessor is derived from its property, so the shards leave it out; the full IR keeps it
            -- the typed set: a column is in a shard only when a committed stage reads it (ruling of 2026-10-10, per column). The type is
            -- the return type of a method or a function, the field or variable type (with its qualifiers), the underlying type of a
            -- typedef; the parameters are the parameter types and names, which the trace stubs read (the NSError ** detection, named by
            -- v-gen); the attributes are the property's, which the property stubs read. The nullability has no committed
            -- reader and stays in the full IR; the value is an enum constant's (ruling 2); decl and the locations are not in a shard.
            -- the value is an enum constant's (the constants record reads it); a row of any other kind has none, and the write refuses one
            -- that has (the declaration hash covers the value cell as written, so the file must not leave out a value the hash covers)
            if kind ~= "enumconst" and row[14] ~= "-" then
                raise(f.name .. ": a " .. kind .. " row has a value; only an enum constant has one: " .. usr)
            end
            local value = kind == "enumconst" and row[14] or "-"
            if kind ~= "accessor" then
                table.insert(lines, table.concat({kind, usr, row[4], stored_name, stored_side, row[11], row[12], row[13], row[9],
                    row[18], row[15], value}, "\t"))
            end
            table.insert(full, table.concat(row, "\t") .. "\n")
        end
        if #lines > 1 then shards[f.name] = table.concat(lines, "\n") .. "\n" end
    else
        local reason = cells_of(out:match("^[^\n]*"))[5]
        table.insert(unparsed, {f.name, reason})
        table.insert(full, unparsed_row(f.name, reason))
    end
end

-- The contract (ruling 5): every framework of the sweep with no shard is classified, none silently: it is in the unparsed list (the
-- extractor's reason) or in no-own.tsv (its class and reason). A listed name must be a framework of the sweep with no shard.
if MODE == "write" or MODE == "check" then
    local classified = {}
    for _, u in ipairs(unparsed) do classified[u[1]] = "unparsed" end
    local no_own = {}
    for line in (os.isfile(NO_OWN) and io.readfile(NO_OWN) or ""):gmatch("[^\n]+") do
        local name = line:match("^([^\t#][^\t]*)\t")
        if name then no_own[name] = true end
    end
    local unclassified, stale, both = {}, {}, {}
    local swept = {}
    for _, f in ipairs(frameworks) do
        swept[f.name] = true
        if no_own[f.name] and classified[f.name] then table.insert(both, f.name) end
        if not shards[f.name] and not classified[f.name] and not no_own[f.name] then table.insert(unclassified, f.name) end
    end
    for name in pairs(no_own) do
        if not swept[name] or shards[name] then table.insert(stale, name) end
    end
    table.sort(unclassified); table.sort(stale); table.sort(both)
    if #unclassified > 0 then
        raise("a framework with no shard is neither unparsed nor in " .. NO_OWN .. ": " .. table.concat(unclassified, " "))
    end
    if #stale > 0 then raise(NO_OWN .. " names a framework that has a shard or is not in the sweep: " .. table.concat(stale, " ")) end
    if #both > 0 then raise(NO_OWN .. " and the unparsed list both name: " .. table.concat(both, " ")) end
end

-- The gaps: each framework of the snapshot (IR_SNAPSHOT, one folder per framework) that has no shard, named with the extractor's own
-- result: not an SDK framework, no public header, Swift only, skipped by the extractor (its parse failed, with the reason), or parsed
-- with no declaration of its own (its translation unit reaches declarations of other frameworks, or none at all).
if MODE == "gaps" then
    local snapshot = os.getenv("IR_SNAPSHOT") or raise("IR_SNAPSHOT must name the snapshot folder whose frameworks are classified")
    local skipped, sdk_framework = {}, {}
    for _, u in ipairs(unparsed) do skipped[u[1]] = u[2] end
    for _, f in ipairs(frameworks) do sdk_framework[f.name] = f end
    local names = {}
    for _, dir in ipairs(os.dirs(path.join(snapshot, "*"))) do
        local name = path.filename(dir)
        if not os.isfile(shard_path(name)) then table.insert(names, name) end
    end
    table.sort(names)
    local tally = {}
    for _, name in ipairs(names) do
        local f = sdk_framework[name]
        local category, count, detail
        if not f then
            local usr_headers = #os.files(path.join(SDK, "usr", "include", name, "**.h"))
            local swift_stdlib = os.isdir(path.join(SDK, "usr", "lib", "swift", name .. ".swiftmodule"))
            category = "not-an-sdk-framework"
            count = usr_headers
            detail = "usr/include headers " .. usr_headers .. ", Swift stdlib module " .. (swift_stdlib and "yes" or "no")
        else
            -- a framework with no header is a row of the extractor's unparsed list, with its reason (decls writes that row)
            local reason = skipped[name]
            local no_header = reason ~= nil and (reason:find("Swift interface only", 1, true) ~= nil
                or reason:find("no public header", 1, true) ~= nil or reason:find("no module map header", 1, true) ~= nil)
            count = census_of[name] and census_of[name].own or 0
            local swift = #os.dirs(path.join(f.root, "Modules", "*.swiftmodule")) > 0
            if no_header then
                category = reason:find("Swift interface only", 1, true) and "swift-only" or "no-public-header"
                detail = reason
            elseif skipped[name] then
                category = "skipped-by-extractor"
                detail = skipped[name]
            elseif census_of[name] and census_of[name].own == 0 then
                if census_of[name].foreign > 0 then
                    category = "imports-other-frameworks"
                    detail = "no declaration of its own; " .. census_of[name].foreign .. " declarations of other SDK headers reach its unit"
                else
                    category = swift and "swift-only" or "no-declaration-reaches-target"
                    detail = "parsed clean; no declaration of its own or of another SDK header reaches the arm64 iOS unit"
                end
            else
                category = "unexplained"
                detail = "the extractor parsed it, and its census disagrees with its shard status"
            end
        end
        tally[category] = (tally[category] or 0) + 1
        print(string.format("%s\t%s\t%d\t%s", name, category, count, detail))
    end
    for category, n in pairs(tally) do print(string.format("summary\t%s\t%d", category, n)) end
    return
end

-- The conflicts: every one must be listed, and every listed one must be a conflict.
local listed = listed_conflicts()
if MODE == "conflicts" then
    for _, c in ipairs(conflicts) do print(c.key .. "\t" .. c.variants .. "\t" .. c.result) end
    print(string.format("%d conflicts", #conflicts))
    return
end
local found = {}
local unlisted, wrong = {}, {}
for _, c in ipairs(conflicts) do
    found[c.key] = true
    local line = listed[c.key]
    if not line then
        table.insert(unlisted, c.key .. "\t" .. c.variants .. "\t" .. c.result)
    elseif line[9] ~= c.result then
        table.insert(wrong, c.key .. ": the list says [" .. line[9] .. "], the rule gives [" .. c.result .. "]")
    end
end
local stale = {}
for key in pairs(listed) do
    if not found[key] then table.insert(stale, key) end
end
if #unlisted > 0 or #stale > 0 or #wrong > 0 then
    raise(string.format("%d conflicts are not listed in %s, %d listed conflicts are gone, %d listed results differ from the rule:\n%s%s%s",
        #unlisted, CONFLICTS, #stale, #wrong, table.concat(unlisted, "\n"), #stale > 0 and ("\nstale: " .. table.concat(stale, "\nstale: ")) or "",
        #wrong > 0 and ("\n" .. table.concat(wrong, "\n")) or ""))
end

-- The shards that exist now. The shard of a framework decls no longer lists is stale. A committed shard of a framework decls still
-- lists is never removed here: when this run gives that framework no shard, the change is raised, and a reviewed change removes it.
local listed_names = {}
for _, f in ipairs(frameworks) do listed_names[f.name] = true end
local existing = {}
if os.isdir(SPEC) then
    for _, file in ipairs(os.files(path.join(SPEC, "**", "declarations.tsv"))) do
        existing[file] = true
    end
end
local stale_shards, without_shard = {}, {}
for file in pairs(existing) do
    local label = file:sub(#SPEC + 2, #file - #"/declarations.tsv")
    if not listed_names[label] then
        table.insert(stale_shards, file)
    elseif not shards[label] then
        table.insert(without_shard, label)
    end
end
table.sort(stale_shards)
table.sort(without_shard)
if #without_shard > 0 then
    raise(string.format("decls gives no shard for %s, but a committed shard is there: a framework decls still lists keeps its committed "
        .. "shard, so its removal is a reviewed change (delete the shard by hand)", table.concat(without_shard, ", ")))
end

local changed, largest, largest_name, total_bytes = {}, 0, "", 0
for label, text in pairs(shards) do
    total_bytes = total_bytes + #text
    if #text > largest then
        largest, largest_name = #text, label
    end
    local file = shard_path(label)
    local old = os.isfile(file) and io.readfile(file) or nil
    if old ~= text then table.insert(changed, label) end
end
table.sort(changed)

local unparsed_text = {"# the frameworks of the SDK with no declaration the extractor reads, and why: one line each"}
for _, u in ipairs(unparsed) do table.insert(unparsed_text, u[1] .. "\t" .. redact(u[2])) end
unparsed_text = table.concat(unparsed_text, "\n") .. "\n"

-- The identity the shards record must be this machine's: every committed shard is compared, in both modes (review F8). A difference
-- is refused, unless write mode is re-recording with IR_REPIN (the reviewed re-pin).
if MODE == "check" or MODE == "write" then
    local differs = {}
    for file in pairs(existing) do
        local recorded = io.readfile(file):match("libclang=([^\t\n]*)")
        if recorded and recorded ~= libclang then
            table.insert(differs, file:sub(#SPEC + 2, #file - #"/declarations.tsv"))
        end
    end
    table.sort(differs)
    if #differs > 0 and (MODE == "check" or not os.getenv("IR_REPIN")) then
        raise(string.format("libclang identity differs in %d shards (%s): this machine has [%s]%s", #differs,
            table.concat(differs, ", "), libclang, MODE == "check" and "" or "; re-record with IR_REPIN=1 as a reviewed re-pin"))
    end
end

if MODE == "check" then
    if #changed > 0 or #stale_shards > 0 then
        raise(string.format("%d shards differ from the regenerated ones (%s), %d shards are stale (%s)", #changed,
            table.concat(changed, ", "), #stale_shards, table.concat(stale_shards, ", ")))
    end
    local old_unparsed = os.isfile(UNPARSED) and io.readfile(UNPARSED) or nil
    if old_unparsed ~= unparsed_text then raise(UNPARSED .. " differs from the regenerated list") end
    print("check ok: " .. SPEC)
else
    for _, label in ipairs(changed) do
        atomic.write(shard_path(label), shards[label])
    end
    for _, file in ipairs(stale_shards) do os.rm(file) end
    atomic.write(UNPARSED, unparsed_text)
    print(string.format("wrote %d shards, removed %d stale shards", #changed, #stale_shards))
end

if FULL then
    atomic.write(FULL, table.concat(full))
end

print(string.format("frameworks %d, parsed %d, rows %d (shard rows), unparsed %d, conflicts %d, %.1f s", #frameworks, parsed,
    rows, #unparsed, #conflicts, (os.mclock() - started) / 1000))
local shard_count = 0
for _ in pairs(shards) do shard_count = shard_count + 1 end
print(string.format("shards %d, bytes %d in all, largest %d (%s)", shard_count, total_bytes, largest, largest_name))
