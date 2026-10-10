-- The extractor's libclang identity rule (review F8), through tools/found/ir.lua on the extractor's fixture SDK: a shard whose recorded
-- identity (the version, the digest of the dylib, the target) is not this machine's is refused by check and by write, and write
-- re-records it only with IR_REPIN. The golden shard of the fixture is copied into a folder under .agent-work/runs, its digest is
-- changed, and the four runs are checked. Run from the repository root: xmake l tests/gen/ir_identity_test.lua (exits 1 on failure).

local ROOT = "tools/found/tests"
local FIXTURE_SDK = path.join(ROOT, "fixture", "sdk")
local FIXTURE_CONFIG = path.join(ROOT, "fixture", "config")
local CONFLICTS = path.join(ROOT, "conflicts.tsv")
local GOLDEN = path.join(ROOT, "expected", "Fixture", "declarations.tsv")
local RUN = path.join(".agent-work", "runs", "ir-identity-" .. tostring(os.time()))
local SPEC = path.join(RUN, "spec")
local SHARD = path.join(SPEC, "Fixture", "declarations.tsv")
local FOREIGN = "dylib-sha256=" .. string.rep("0", 64)

-- Runs ir.lua in a mode with the fixture's inputs. Returns true, or false and the message the run raised.
local function run_ir(mode, repin)
    local envs = {IR_SDK = FIXTURE_SDK, IR_CONFIG = FIXTURE_CONFIG, IR_MODE = mode, IR_SPEC = SPEC, IR_CONFLICTS = CONFLICTS,
                  IR_UNPARSED = path.join(RUN, "unparsed.tsv"), IR_NO_OWN = path.join(FIXTURE_CONFIG, "no-own.tsv")}
    if repin then
        envs.IR_REPIN = "1"
    end
    local ok, message = true, ""
    try {
        function () os.iorunv("xmake", {"l", "./tools/found/ir.lua"}, {envs = envs}) end,
        catch {
            function (errors)
                ok = false
                message = tostring(errors)
            end
        }
    }
    return ok, message
end

function main()
    local failures, count = 0, 0
    local function check(ok, label)
        count = count + 1
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local golden = io.readfile(GOLDEN)
    local foreign, replaced = golden:gsub("dylib%-sha256=%x+", FOREIGN, 1)
    check(replaced == 1, "the golden shard records a dylib digest to change")
    os.mkdir(path.directory(SHARD))
    io.writefile(SHARD, foreign)

    local ok, message = run_ir("check", false)
    check(not ok and string.find(message, "libclang identity differs", 1, true) ~= nil,
          "check refuses a shard recorded by another libclang identity (" .. message:sub(1, 120) .. ")")

    ok, message = run_ir("write", false)
    check(not ok and string.find(message, "libclang identity differs", 1, true) ~= nil,
          "write refuses it without IR_REPIN (" .. message:sub(1, 120) .. ")")
    check(io.readfile(SHARD) == foreign, "the refused write left the shard as it was")

    ok, message = run_ir("write", true)
    check(ok, "write with IR_REPIN re-records the shard (" .. message:sub(1, 160) .. ")")
    check(io.readfile(SHARD) == golden, "the re-recorded shard equals the golden shard, byte for byte")

    os.rm(RUN)
    local verdict = failures == 0 and "OK" or ("FAIL " .. failures)
    print(string.format("ir identity test: %s (%d checks)", verdict, count))
    if failures > 0 then
        os.exit(1)
    end
end
