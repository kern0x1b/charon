-- What the driver checks after it writes the sets: lift_test (tests/addon/lift_test.lua, the lift on fixtures, no SDK), and the two
-- sets the lift is checked against by the swift-runtime build, whose headers must say what their bodies hold. The sets are read
-- from the worktree as they now stand. Returns the failures, one line each; none is a pass.

local assemble = import("assemble", {anonymous = true})

-- The two SDK folders whose sets the build reads, by the name the build reads them under.
local SETS = {"iPhoneOS16.4.sdk", "iPhoneOS26.2.sdk"}

function failures(worktree)
    local found = {}
    local lift_test = import("lift_test", {rootdir = path.join(worktree, "tests", "addon"), anonymous = true})
    for _, failure in ipairs(lift_test.failures({modules = path.join(worktree, "modules")})) do
        table.insert(found, "lift_test: " .. failure)
    end
    for _, name in ipairs(SETS) do
        local set = path.join(worktree, "packages", "s", "swift-runtime", "lift", name .. ".txt")
        local text = os.isfile(set) and io.readfile(set) or nil
        if not text then
            table.insert(found, name .. ".txt: no set at " .. set)
        else
            for _, mismatch in ipairs(assemble.mismatches(text)) do
                table.insert(found, name .. ".txt: " .. mismatch)
            end
        end
    end
    return found
end
