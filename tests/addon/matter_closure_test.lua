-- The emit rule's output must match its inputs and the committed Matter objects (v-matter12). The rule is in
-- tools/matter-closure.lua: a generated class is emitted only when the real stack does not carry it (class-overlap.tsv
-- says no) and it is in the closure of the app-usable SDK 26.2 Matter API. facts/Matter/emit-closure.tsv is that rule's
-- output, one row per generator input class. This suite fails when the file is stale against class-overlap.tsv (its
-- digest), when a row disagrees with class-overlap or with the rule, and when a committed Matter/CharonMatter*.m implements
-- a class the rule does not emit and that is not pending. The 23 pending classes are the committed objects the rule says
-- must not exist; the coordinator rules on them, and this list only shrinks. Pure Lua: it reads committed files and runs
-- no clang. The corpus and the SDK headers are outside the repository: re-run tools/matter-closure.lua to check them.

-- The committed objects the emit rule does not emit yet: three base classes the real stack carries (the 20 subclass
-- them) and the 20 generator-only classes that are unavailable in SDK 26.2. The coordinator rules on each (v-matter12 report).
local pending = {
    MTRBaseClusterAppleDeviceInformation = true,
    MTRBaseClusterAppleLockCluster = true,
    MTRBaseClusterTimer = true,
    MTRCluster = true,
    MTRClusterAppleDeviceInformation = true,
    MTRClusterAppleLockCluster = true,
    MTRClusterTimer = true,
    MTRDoorLockClusterAppleAliroCredentialStruct = true,
    MTRDoorLockClusterAppleAliroLockOperationErrorEvent = true,
    MTRDoorLockClusterAppleAliroLockOperationEvent = true,
    MTRDoorLockClusterAppleAliroLockUserChangeEvent = true,
    MTRDoorLockClusterAppleClearAliroCredentialParams = true,
    MTRDoorLockClusterAppleClearAliroReaderConfigParams = true,
    MTRDoorLockClusterAppleGetAliroCredentialStatusParams = true,
    MTRDoorLockClusterAppleSetAliroCredentialParams = true,
    MTRDoorLockClusterAppleSetAliroReaderConfigParams = true,
    MTRGenericBaseCluster = true,
    MTRGenericCluster = true,
    MTRGroupcastClusterExpireGracePeriodParams = true,
    MTRTimerClusterAddTimeParams = true,
    MTRTimerClusterReduceTimeParams = true,
    MTRTimerClusterResetTimerParams = true,
    MTRTimerClusterSetTimerParams = true,
}

-- The same digest as tools/matter-closure.lua (32-bit, over the bytes in order).
local function digest(text)
    local h = 0
    for k = 1, #text, 4096 do
        for _, b in ipairs({text:byte(k, math.min(k + 4095, #text))}) do
            h = (h * 31 + b) % 4294967296
        end
    end
    return string.format("%08x", h)
end

local function cells_of(line)
    local out = {}
    for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
        out[#out + 1] = cell
    end
    return out
end

function failures(opt)
    local byteorder = import("byteorder", {rootdir = opt.modules})
    local root = path.join(opt.modules, "..")
    local apple = path.join(root, "packages", "a", "apple-backports")
    local facts = path.join(apple, "facts", "Matter")
    local closure = path.join(facts, "emit-closure.tsv")
    local overlap = path.join(facts, "class-overlap.tsv")
    local objects = path.join(apple, "Matter")
    local out = {}
    if not os.isfile(closure) or not os.isfile(overlap) then
        return {"no emit-closure.tsv or class-overlap.tsv under " .. facts}
    end

    -- the generator input and the real stack's verdict, from class-overlap.tsv
    local overlap_text = io.readfile(overlap)
    local real, input = {}, 0
    local first = true
    for line in overlap_text:gmatch("[^\n]+") do
        if first then
            first = false
        else
            local cells = cells_of(line)
            if cells[1] then
                real[cells[1]] = cells[2]
                input = input + 1
            end
        end
    end

    local lines = {}
    for line in io.lines(closure) do
        lines[#lines + 1] = line
    end
    local stamp = lines[1] or ""
    local have = stamp:match("^# inputs: class%-overlap%.tsv (%x+);")
    local want = digest(overlap_text)
    if have ~= want then
        out[#out + 1] = "emit-closure.tsv is stale: its class-overlap.tsv digest is " .. tostring(have)
            .. ", the file's is " .. want .. " (re-run tools/matter-closure.lua)"
    end
    if lines[2] ~= "class\treal-stack\tin-closure\treason\temit" then
        out[#out + 1] = "emit-closure.tsv has no column line in its second row"
    end

    local emit, rows, prev = {}, 0, nil
    for index = 3, #lines do
        local cells = cells_of(lines[index])
        local name, real_col, closure_col, reason, emit_col = cells[1], cells[2], cells[3], cells[4], cells[5]
        rows = rows + 1
        if prev and not byteorder.less(prev, name) then
            out[#out + 1] = "row " .. index .. " (" .. tostring(name) .. ") is not in byte order after " .. prev
        end
        prev = name
        if real[name] == nil then
            out[#out + 1] = name .. " is not a generator input (not in class-overlap.tsv)"
        elseif real_col ~= real[name] then
            out[#out + 1] = name .. " real-stack is " .. tostring(real_col) .. ", class-overlap says " .. real[name]
        end
        if closure_col ~= "yes" and closure_col ~= "no" then
            out[#out + 1] = name .. " in-closure is not yes or no"
        elseif (closure_col == "yes") == (reason == "none") then
            out[#out + 1] = name .. " in-closure " .. closure_col .. " disagrees with its reason"
        end
        local expect = (real[name] == "no" and closure_col == "yes") and "yes" or "no"
        if emit_col ~= expect then
            out[#out + 1] = name .. " emit is " .. tostring(emit_col) .. ", the rule says " .. expect
        end
        emit[name] = emit_col
    end
    if rows ~= input then
        out[#out + 1] = "emit-closure.tsv has " .. rows .. " rows for " .. input .. " generator input classes"
    end

    -- the committed objects: a class the rule does not emit must be pending
    local seen = {}
    for _, file in ipairs(os.files(path.join(objects, "CharonMatter*.m"))) do
        local impl = io.readfile(file):match("@implementation%s+([%w_]+)")
        local shown = path.filename(file)
        if not impl then
            out[#out + 1] = shown .. " defines no class"
        elseif emit[impl] == nil then
            out[#out + 1] = shown .. " defines " .. impl .. ", which is not a generator input"
        else
            seen[impl] = true
            if emit[impl] == "no" and not pending[impl] then
                out[#out + 1] = shown .. " defines " .. impl .. ", which the emit rule does not emit (emit-closure.tsv no)"
            end
        end
    end
    -- and the pending list only shrinks: every pending class is still committed and still not emitted
    for name in pairs(pending) do
        if not seen[name] then
            out[#out + 1] = "pending " .. name .. " has no committed object: drop it from the pending list"
        elseif emit[name] ~= "no" then
            out[#out + 1] = "pending " .. name .. " is emit " .. tostring(emit[name]) .. ": drop it from the pending list"
        end
    end
    return out
end
