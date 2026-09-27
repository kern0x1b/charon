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
    local function lifted(lines, registry, expected)
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
                                minimum = "6.1.3", registry = root, outputdir = path.join(root, "out"), expected = expected or false})
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
    -- what the lift leaves alone is compared with the set measured for the SDK: the exact set passes, a set with a line more or a line less, or none, fails naming it
    local header = {"void FixOwnLift(void) API_AVAILABLE(ios(9.0));"}
    local registry = {FixOwnLift = "implemented", FixNowhere = "implemented"}
    local measured = ""
    result, failure = lifted(header, registry)
    expect("a lift with expected = false", failure, nil)
    measured = io.readfile(path.join(root, "out", "left-alone.txt"))
    expect("what it leaves alone has the name no header declares", measured:find("unmatched\tFixNowhere\tfunction\n", 1, true) ~= nil, true)
    local function against(expected)
        local _, why = lifted(header, registry, expected)
        return why
    end
    expect("the exact set passes", against("# a comment\n" .. measured), nil)
    local none = against("")
    expect("no set fails naming the name and saying there is none", none and none:find("new: unmatched FixNowhere function", 1, true) ~= nil and none:find("no set is measured", 1, true) ~= nil, true)
    local more = against(measured .. "unmatched\tFixGone\tfunction\n")
    expect("a set with a name that is gone fails naming it", more and more:find("no longer found: unmatched FixGone function", 1, true) ~= nil and more:find("no set is measured", 1, true) == nil, true)
    local less = against("unmatched\tFixOther\tfunction\n")
    expect("a set of another name fails with both", less and less:find("new: unmatched FixNowhere function", 1, true) ~= nil and less:find("no longer found: unmatched FixOther function", 1, true) ~= nil, true)

    -- a framework with no umbrella header that keeps generations of its API in folders (OpenGLES's ES1, ES2, ES3): the newest is read, and a
    -- name only it declares is lowered there; the older one is not read, so a name in it is left alone, and its copy is not written
    os.tryrm(root)
    local other = path.join(root, "sdk", "System", "Library", "Frameworks", "Other.framework", "Headers")
    io.writefile(path.join(other, "Avail.h"), "#define ios(version) ios, introduced=version\n#define API_AVAILABLE(...) __attribute__((availability(__VA_ARGS__)))\n")
    io.writefile(path.join(other, "Top.h"), "@protocol NSObject @end\n@protocol NSCopying @end\n__attribute__((objc_root_class)) @interface NSObject <NSObject> @end\nvoid FixTop(void);\n")
    io.writefile(path.join(other, "G2", "gl.h"), '#include <Other/Avail.h>\nvoid FixGenTwo(void) API_AVAILABLE(ios(9.0));\n')
    io.writefile(path.join(other, "G3", "gl.h"), '#include <Other/Avail.h>\nvoid FixGenThree(void) API_AVAILABLE(ios(9.0));\n')
    io.writefile(path.join(root, "registry", "Other.json"), '[{"api": "FixGenThree", "kind": "function", "introduced": "9.0", "minimum": "6.0", "status": "implemented"},' ..
                 '{"api": "FixGenTwo", "kind": "function", "introduced": "9.0", "minimum": "6.0", "status": "implemented"}]')
    local generations, failure
    try {function ()
        generations = lift.lift({clang = opt.clang, swiftc = path.join(opt.swift, "bin", "swiftc"), sdk = path.join(root, "sdk"), triple = "armv7-apple-ios6.1.3",
                                 minimum = "6.1.3", registry = root, outputdir = path.join(root, "out"), expected = false})
    end, catch {function (why) failure = tostring(why) end}}
    expect("a lift of a framework with generations of its API: " .. tostring(failure), failure, nil)
    local copy = path.join(root, "out", "headers", "System", "Library", "Frameworks", "Other.framework", "Headers", "G3", "gl.h")
    expect("the newest generation's header is lowered", os.isfile(copy) and io.readfile(copy):find("ios(6.1.3)", 1, true) ~= nil, true)
    expect("the older generation's is not read", os.isfile(path.join(root, "out", "headers", "System", "Library", "Frameworks", "Other.framework", "Headers", "G2", "gl.h")), false)
    local left = {}
    for _, name in ipairs(generations and generations.unmatched or {}) do
        if name:find("^Fix") then
            table.insert(left, name)
        end
    end
    expect("what only the older declares is left alone", table.concat(left, ","), "FixGenTwo")
    os.tryrm(root)
    return found
end
