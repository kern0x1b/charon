-- One lift, measured: `xmake l tools/lift-remeasure/measure.lua <run dir> <output dir> <registry dir>`. The driver
-- (tools/lift-remeasure.lua) runs it once per SDK, through coordination/heavy.sh, with the SDK, clang, swiftc and the job count
-- in LIFT_SDK, LIFT_CLANG, LIFT_SWIFTC and LIFT_JOBS. The lift reads the frozen modules/ of the run directory, so the tree can
-- move under a long run without changing what is measured. What it leaves alone is written to <output dir>/left-alone.txt.

-- The target the committed sets were measured for: the armv7 release the swift-runtime build lifts for (its minimum is the
-- deployment of apple-ios, 6.1.3). A set is only ever checked against this target, never against a later one.
local TRIPLE = "armv7-apple-ios6.1.3"
local MINIMUM = "6.1.3"

function main(run_dir, outputdir, registry)
    local sdk, clang, swiftc = os.getenv("LIFT_SDK"), os.getenv("LIFT_CLANG"), os.getenv("LIFT_SWIFTC")
    assert(sdk and clang and swiftc, "measure: LIFT_SDK, LIFT_CLANG and LIFT_SWIFTC are needed")
    local lift = import("apple.lift", {rootdir = path.join(run_dir, "modules"), anonymous = true})
    -- expected = false: a measurement, not a check against a set. keep = nil: the lift is run, not handed back from a kept result,
    -- so the time it takes is the time of a lift.
    local result = lift.lift({clang = clang, swiftc = swiftc, sdk = sdk, triple = TRIPLE, minimum = MINIMUM,
                              registry = registry, outputdir = outputdir, jobs = tonumber(os.getenv("LIFT_JOBS") or "1"),
                              expected = false})
    print(string.format("measure: %d marks in %d headers for %d implemented API; left alone: %d classes, %d other names, %d undeclared members",
                        result.lifted, result.headers, result.implemented, #result.classes, #result.unmatched, #result.undeclared))
end
