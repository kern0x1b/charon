-- Names asked for by the prefix a group of them shares give what each name's own query gives: lift() of a fixture SDK, run with the
-- groups and without (opt.grouped = false), writes the same headers. The fixture has the two things that could tell them apart: a
-- constant an enumeration's name contains (found only below a declaration the group's query prints whole), and functions of one prefix.
-- Runs lift() with the real clang and swiftc.
function failures(opt)
    local lift = import("apple.lift", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local function expect(what, got, wanted)
        if got ~= wanted then
            table.insert(found, string.format("%s was %s, not %s", what, tostring(got), tostring(wanted)))
        end
    end
    -- The run's own folder, like every other fixture folder in these suites: two runs writing and then removing
    -- one folder is a race, and the loser answers with the fixture missing (measured in lift_test, 2026-10-04).
    local root = path.join(os.tmpdir(), "lift_groups_test-" .. os.getpid())
    os.tryrm(root)
    local sdk = path.join(root, "sdk")
    local header = path.join("System", "Library", "Frameworks", "Fix.framework", "Headers", "Fix.h")
    -- the macros in a header of their own, as the SDK has them: the location of a use that names a file only where it differs from the last
    io.writefile(path.join(sdk, path.directory(header), "Avail.h"), "#define ios(version) ios, introduced=version\n" ..
                 "#define API_AVAILABLE(...) __attribute__((availability(__VA_ARGS__)))\n")
    io.writefile(path.join(sdk, header), table.concat({
        "@protocol NSObject @end", "@protocol NSCopying @end", "__attribute__((objc_root_class)) @interface NSObject <NSObject> @end",
        '#include "Avail.h"',
        "enum FixFlagsKind { FixFlagsKindA API_AVAILABLE(ios(8.0)) = 1, FixFlagsKindB API_AVAILABLE(ios(9.0)) = 2 };",
        "void FixOpenAlpha(void) API_AVAILABLE(ios(8.0));",
        "void FixOpenBeta(void) API_AVAILABLE(ios(9.0));",
        "void FixOpenGamma(void) API_AVAILABLE(ios(10.0));", ""}, "\n"))
    local entries = {}
    for _, name in ipairs({"FixFlagsKindA", "FixFlagsKindB", "FixOpenAlpha", "FixOpenBeta", "FixOpenGamma"}) do
        table.insert(entries, string.format('{"api": "%s", "kind": "function", "introduced": "8.0", "minimum": "6.0", "status": "implemented"}', name))
    end
    io.writefile(path.join(root, "registry", "Fix.json"), "[" .. table.concat(entries, ",") .. "]")
    local function lifted(grouped)
        local out = path.join(root, grouped and "grouped" or "alone")
        local result, failure
        try {function ()
            result = lift.lift({clang = opt.clang, swiftc = path.join(opt.swift, "bin", "swiftc"), sdk = sdk, triple = "armv7-apple-ios6.1.3",
                                minimum = "6.1.3", registry = root, outputdir = out, expected = false, grouped = grouped})
        end, catch {function (why) failure = tostring(why) end}}
        local file = path.join(out, "headers", header)
        return result, failure, os.isfile(file) and io.readfile(file) or nil
    end
    local _, failure, alone = lifted(false)
    expect("a lift with every name asked on its own", failure, nil)
    local _, failure_grouped, grouped = lifted(true)
    expect("a lift with the names grouped", failure_grouped, nil)
    expect("the lifted header, names asked on their own, was written", alone ~= nil, true)
    expect("the headers of the two", grouped, alone)
    -- and what they hold is the lowered releases: nothing of the SDK's 8.0, 9.0 or 10.0 is left, all five name 6.1.3
    for _, release in ipairs({"8.0", "9.0", "10.0"}) do
        expect("the header left at iOS " .. release, grouped and grouped:find("ios(" .. release .. ")", 1, true), nil)
    end
    local _, lowered = (grouped or ""):gsub("6%.1%.3", "")
    expect("the five names lowered to 6.1.3", lowered, 5)
    os.tryrm(root)
    return found
end
