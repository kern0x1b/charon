-- A kept entry (in the registry, not implemented) is asked over the overlay to see the lift did not lower it too, but only where the overlay
-- can move what it answers: one of its marks is where the lift edited, or it is a member of a class the lift redeclares members on. The
-- fixture has a kept name of each kind and one of neither: the two that share a mark with an implemented name or a class are asked (the
-- shared mark is lowered with it, and the lift fails naming the kept name); the one whose mark no edit touches is not asked, and is counted.
-- Runs lift() with the real clang and swiftc on a fixture SDK.
function failures(opt)
    local lift = import("apple.lift", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local function expect(what, got, wanted)
        if got ~= wanted then
            table.insert(found, string.format("%s was %s, not %s", what, tostring(got), tostring(wanted)))
        end
    end
    local root = path.join(os.tmpdir(), "lift_overlay_test")
    local folder = path.join("System", "Library", "Frameworks", "Fix.framework", "Headers")
    local function lifted(lines, registry)
        os.tryrm(root)
        local sdk = path.join(root, "sdk")
        -- the macros in a header of their own, as the SDK has them: the location of a use that names a file only where it differs from the last
        io.writefile(path.join(sdk, folder, "Avail.h"), "#define ios(version) ios, introduced=version\n" ..
                     "#define API_AVAILABLE(...) __attribute__((availability(__VA_ARGS__)))\n")
        io.writefile(path.join(sdk, folder, "Fix.h"), table.concat({
            "@protocol NSObject @end", "@protocol NSCopying @end", "__attribute__((objc_root_class)) @interface NSObject <NSObject> @end",
            '#include "Avail.h"', "@protocol FixEnv", "- (void)traitDidChange:(id)previous API_AVAILABLE(ios(8.0));", "@end",
            unpack(lines)}, "\n") .. "\n")
        local entries = {}
        for api, status in pairs(registry) do
            table.insert(entries, string.format('{"api": "%s", "kind": "%s", "introduced": "8.0", "minimum": "6.0", "status": "%s"%s}', api,
                                                api:find("^[-+]") and "method" or api:find(".", 1, true) and "method" or "function", status,
                                                status == "implemented" and "" or ', "effect": "a fixture entry", "reason": "a fixture entry the backports do not carry"'))
        end
        table.sort(entries)
        io.writefile(path.join(root, "registry", "Fix.json"), "[" .. table.concat(entries, ",") .. "]")
        local result, failure
        try {function ()
            result = lift.lift({clang = opt.clang, swiftc = path.join(opt.swift, "bin", "swiftc"), sdk = sdk, triple = "armv7-apple-ios6.1.3",
                                minimum = "6.1.3", registry = root, outputdir = path.join(root, "out"), expected = false})
        end, catch {function (why) failure = tostring(why) end}}
        return result, failure
    end
    local function skipped(lines, registry, count, what)
        local result, failure = lifted(lines, registry)
        expect(what .. ": the lift", failure, nil)
        expect(what .. ": the kept entries not asked over the overlay", result and result.skipped, count)
    end

    -- two names one macro use marks: the kept one is lowered with the implemented one, which the check over the overlay tells
    local result, failure = lifted({"API_AVAILABLE(ios(9.0)) extern int FixSharedLift, FixSharedKeep;"},
                                   {FixSharedLift = "implemented", FixSharedKeep = "absent"})
    expect("a kept name that shares a mark with an implemented one fails: " .. tostring(failure), failure and failure:find("FixSharedKeep is absent and was lowered from iOS 9.0", 1, true) ~= nil, true)

    -- a kept name whose mark no edit touches is not asked, and the implemented one beside it is lowered as ever
    skipped({"void FixOwnLift(void) API_AVAILABLE(ios(9.0));", "void FixFarKeep(void) API_AVAILABLE(ios(9.0));"},
            {FixOwnLift = "implemented", FixFarKeep = "absent"}, 1, "a kept name of its own mark")

    -- a kept member of a class the lift redeclares a member on is asked, though no mark of its own is edited: what the redeclaration adds may match it
    skipped({"@interface FixView : NSObject <FixEnv>", "- (void)draw;", "- (void)keep API_AVAILABLE(ios(9.0));", "@end"},
            {["-[FixView traitDidChange:]"] = "implemented", ["-[FixView keep]"] = "absent"}, 0, "a kept member of a redeclared class")
    -- a method spelled Class.selector: is read by nothing that lowers: the lift refuses it by name, and a set of what it leaves alone cannot hold it
    result, failure = lifted({"@interface FixView : NSObject", "- (void)draw:(int)value;", "@end"}, {["FixView.draw:"] = "implemented"})
    expect("a method spelled Class.selector: is refused by name", failure and failure:find("FixView.draw: is a method not spelled", 1, true) ~= nil, true)
    result, failure = lifted({"@interface FixView : NSObject", "- (void)draw:(int)value API_AVAILABLE(ios(9.0));", "@end"}, {["-[FixView draw:]"] = "implemented"})
    expect("the same method spelled -[Class selector:] is lifted", failure, nil)
    os.tryrm(root)
    return found
end
