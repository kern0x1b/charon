-- `check`: regenerates a framework in memory from its snapshot and compares the result with the committed manifest of digests,
-- with the member record, with the spec's hash defines, and with the build directory. A drift, a stale pin, or a manifest that
-- does not match the generator fails the check; a removed override is a warning.

local layout = import("layout", {anonymous = true})
local snapshot = import("spec", {anonymous = true})
local render = import("render", {anonymous = true})
local digest = import("digest", {anonymous = true})
local files = import("files", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local gen = import("cmd_gen", {anonymous = true})

-- The data lines of a table's text: every line after the header that is not empty.
local function data_lines(text)
    local out = {}
    local all = tsv.lines(text)
    for i = 2, #all do
        if all[i] ~= "" then
            table.insert(out, all[i])
        end
    end
    return out
end

-- The problems and warnings of one framework, in the order the report prints them.
local function diagnose(tree, fw)
    local emitted = render.render(tree, fw)
    local base = layout.gen_dir(tree, fw)
    local names = {}
    for name in pairs(emitted) do
        table.insert(names, name)
    end
    table.sort(names)
    local problems, warnings = {}, {}
    local manifest = snapshot.manifest(tree, fw)
    if manifest == nil then
        table.insert(problems, "no manifest committed in the snapshot: run gen --record")
    else
        for _, name in ipairs(names) do
            if manifest[name] ~= digest.digest_of(emitted[name]) then
                table.insert(problems, "snapshot manifest differs from what the generator emits: " .. name)
            end
        end
        local recorded = {}
        for name in pairs(manifest) do
            table.insert(recorded, name)
        end
        table.sort(recorded)
        for _, name in ipairs(recorded) do
            if emitted[name] == nil then
                table.insert(problems, "manifest names a file the generator no longer emits: " .. name)
            end
        end
    end
    for _, name in ipairs(names) do
        local text = files.read_text(path.join(base, name))
        if text == nil then
            table.insert(warnings, "not in the build directory yet: " .. name .. " (run gen)")
        elseif text ~= emitted[name] then
            table.insert(problems, "build directory differs from the generator: " .. name)
        end
    end
    for _, name in ipairs(gen.stale_constants(base, fw, emitted)) do
        table.insert(problems, "build directory holds a constants object the generator no longer emits: " .. name)
    end
    local changes = gen.member_changes(tree, fw)
    if changes == nil then
        table.insert(problems, "no member record committed: run gen --record")
    else
        for _, change in ipairs(changes.changed) do
            table.insert(problems, string.format("member %s changed: declaration hash %s (recorded) -> %s (now)", change[1], change[2], change[3]))
        end
        for _, api in ipairs(changes.new) do
            table.insert(warnings, "member with no record yet: " .. api)
        end
        for _, api in ipairs(changes.removed) do
            table.insert(warnings, "recorded member the spec no longer holds: " .. api)
        end
    end
    local defined = {}
    for key in string.gmatch(emitted["spec.h"], "CHARON_SPEC_HASH_([%w_]+)") do
        defined[key] = true
    end
    for _, r in ipairs(snapshot.load(tree, fw)) do
        if not defined[r.key] then
            table.insert(problems, "spec member without a hash define: " .. r.api)
        end
    end
    local stale = data_lines(emitted["stale.tsv"])
    local removed = data_lines(emitted["removed.tsv"])
    local new = data_lines(emitted["new.tsv"])
    for _, line in ipairs(stale) do
        table.insert(problems, "stale pin: " .. string.gsub(line, "\t", "  "))
    end
    for _, line in ipairs(removed) do
        table.insert(warnings, "removed override: " .. string.gsub(line, "\t", "  "))
    end
    return problems, warnings, #removed, #new
end

-- Returns the exit status: 1 when any framework has a problem.
function run(args)
    local targets = args.all and gen.frameworks(args.tree) or {args.framework}
    local failed = 0
    for _, fw in ipairs(targets) do
        local problems, warnings, removed, new = diagnose(args.tree, fw)
        for _, line in ipairs(problems) do
            print("CHECK " .. fw .. ": " .. line)
        end
        for _, line in ipairs(warnings) do
            print("WARN " .. fw .. ": " .. line)
        end
        print(string.format("check %s: drift and stale %d, removed (warned) %d, members without an override (new) %d",
            fw, #problems, removed, new))
        if #problems > 0 then
            failed = failed + 1
        end
    end
    return failed > 0 and 1 or 0
end
