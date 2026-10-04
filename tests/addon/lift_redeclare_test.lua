-- A member the SDK declares only in a protocol its class adopts is redeclared in the class's own @interface (Swift's importer takes the
-- protocol's requirement over a category's redeclaration), before that @interface's @end; where clang does not place the @end at the text,
-- or a language reads the class from another @interface, the lift fails by name; a lift that edits nothing still writes an overlay clang reads.
-- Runs lift() with the real clang and swiftc on a fixture SDK.
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
    local root = path.join(os.tmpdir(), "lift_redeclare_test-" .. os.getpid())
    local function lifted(header)
        os.tryrm(root)
        local sdk = path.join(root, "sdk")
        -- Foundation's umbrella, which the umbrella lift() generates imports first, and where this fixture's NSObject is
        -- declared: one translation unit cannot declare a protocol twice, so the Fix.h below reaches it there
        io.writefile(path.join(sdk, "System", "Library", "Frameworks", "Foundation.framework", "Headers", "Foundation.h"),
                     "@protocol NSObject @end\n@protocol NSCopying @end\n__attribute__((objc_root_class)) @interface NSObject <NSObject> @end\n")
        io.writefile(path.join(sdk, "System", "Library", "Frameworks", "Fix.framework", "Headers", "Fix.h"), header)
        io.writefile(path.join(root, "registry", "Fix.json"), '[{"api": "-[FixView traitDidChange:]", "kind": "method", "introduced": "8.0", "minimum": "6.0", "status": "implemented"}]')
        local result, failure
        try {function ()
            result = lift.lift({clang = opt.clang, swiftc = path.join(opt.swift, "bin", "swiftc"), sdk = sdk, triple = "armv7-apple-ios6.1.3",
                                minimum = "6.1.3", registry = root, outputdir = path.join(root, "out"), expected = false})
        end, catch {function (why) failure = tostring(why) end}}
        local text = os.isfile(path.join(root, "out", "headers", "System", "Library", "Frameworks", "Fix.framework", "Headers", "Fix.h"))
                     and io.readfile(path.join(root, "out", "headers", "System", "Library", "Frameworks", "Fix.framework", "Headers", "Fix.h")) or nil
        return result, failure, text
    end
    -- what the lift writes for a lowered release is the SDK's own macro; the fixture SDK spells it the way os/availability.h does in effect
    local prelude = "#define ios(version) ios, introduced=version\n#define API_AVAILABLE(...) __attribute__((availability(__VA_ARGS__)))\n" ..
                    "#import <Foundation/Foundation.h>\n" ..
                    "@protocol FixEnv\n- (void)traitDidChange:(id)previous __attribute__((availability(ios,introduced=8.0)));\n@end\n"

    -- the member goes into the @interface, before its @end, and no category is made for it
    local result, failure, text = lifted(prelude .. "@interface FixView : NSObject <FixEnv>\n- (void)draw;\n@end\n")
    expect("a lift of a class that adopts the protocol", failure, nil)
    expect("the member is in the @interface before its @end", text and text:find("@interface FixView : NSObject <FixEnv>\n[^@]*traitDidChange:[^@]*@end") ~= nil, true)
    expect("no category is made for it", text and text:find("(CharonLifted)", 1, true), nil)
    expect("the member is not left alone", result and #result.undeclared, 0)

    -- an @end that a macro spells has no place in the text: the lift says so, by the class
    result, failure = lifted("#define CLOSE @end\n" .. prelude .. "@interface FixView : NSObject <FixEnv>\n- (void)draw;\nCLOSE\n")
    expect("an @end that is not where clang places it fails by name", failure and failure:find("the @end of the @interface of FixView", 1, true) ~= nil, true)

    -- an @end with a gap after the @ has an offset, but the text there does not read "@end": the check on the text, not the missing offset, refuses it
    result, failure = lifted(prelude .. "@interface FixView : NSObject <FixEnv>\n- (void)draw;\n@ end\n")
    expect("an @end spelled with a gap fails by name", failure and failure:find("the @end of the @interface of FixView", 1, true) ~= nil, true)

    -- a language another @interface of the class is given by the header's own #if
    result, failure = lifted(prelude .. "#ifdef __cplusplus\n@interface FixView : NSObject <FixEnv>\n- (void)draw;\n@end\n#else\n@interface FixView : NSObject <FixEnv>\n- (void)draw;\n@end\n#endif\n")
    expect("a language that reads the class from another @interface fails by name", failure and failure:find("reads the class FixView", 1, true) ~= nil, true)

    -- a lift that edits nothing (the registry names a member no header declares) still writes an overlay clang reads: `"roots": []`
    result, failure = lifted(prelude .. "@interface Other : NSObject\n- (void)draw;\n@end\n")
    expect("a lift with no edit at all", failure, nil)
    local overlay = result and io.readfile(result.vfs) or ""
    expect("its overlay has an empty array of roots", overlay:find('"roots":[]', 1, true) ~= nil, true)
    os.tryrm(root)
    return found
end
