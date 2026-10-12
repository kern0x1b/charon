-- sdk_verbatim_test.lua: tools/sdk-verbatim.lua reports a comment line that occurs verbatim in an SDK header
-- (red), reports nothing for a source written in its own words (green), and FAILS rather than passing when
-- it has nothing to compare: an unreadable SDK root, or no file at all.
--
-- The fixture is sdk-verbatim/: a fake SDK header under sdk/, a source whose line 3 is a line of that
-- header (red/), and the same source with its comment in other words (green/). None of it is Apple's text.
function failures(opt)
    local found = {}
    local tool = import("sdk-verbatim", {rootdir = path.join(opt.modules, "..", "tools"), anonymous = true})
    local fixture = path.join(opt.modules, "..", "tests", "addon", "sdk-verbatim")
    local sdk = path.join(fixture, "sdk")
    local red = path.join(fixture, "red", "Source.m")
    local green = path.join(fixture, "green", "Source.m")

    local function check(ok, what)
        if not ok then table.insert(found, what) end
    end

    local r = tool.scan(sdk, {red})
    check(#r.errors == 0, "red: the scan reported " .. table.concat(r.errors, "; "))
    check(#r.hits == 1 and r.hits[1] == red .. ":3", "red: expected one hit at line 3, got " .. table.concat(r.hits, " "))

    local g = tool.scan(sdk, {green})
    check(#g.errors == 0, "green: the scan reported " .. table.concat(g.errors, "; "))
    check(#g.hits == 0, "green: expected no hit, got " .. table.concat(g.hits, " "))

    local bad_root = tool.scan(path.join(fixture, "no-such-sdk"), {green})
    check(#bad_root.errors > 0, "an unreadable SDK root was not reported as a failure")

    local none = tool.scan(sdk, {})
    check(#none.errors > 0, "a scan that compared no comment line was not reported as a failure")

    return found
end
