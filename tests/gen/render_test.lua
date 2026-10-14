-- The definition of a string constant (tools/gen/render.lua constant_definition): the const qualifiers of its declared type spelled as the
-- declaration spells them. A const before the pointer's star qualifies the string (the SDK's `NSString const *`, `const NSString *`), a
-- const after it qualifies the variable (`NSString *const`, and a typedef's `NSErrorDomain const`, which has no star at all). The three
-- NetworkExtension rows of spec/NetworkExtension/constants.tsv with a pointer to const are the case the old emitter got wrong: it wrote
-- `NSString *const` for any const, and the 6.1.3 gate failed on the redefinition with a different type (round 21, B1).
-- Run: xmake l tests/gen/render_test.lua

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

function main()
    local render = import("gen.render", {rootdir = TOOLS, anonymous = true})
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local function definition(api, decl, shape)
        return render.constant_definition({api = api, type = decl, shape = shape or "ns", value = "Value"})
    end

    -- the three rows the 6.1.3 gate refused (spec/NetworkExtension/constants.tsv), and the SDK's own spelling of them
    check(definition("NEFilterProviderRemediationMapRemediationURLs", "NSString const *")
        == 'const NSString * NEFilterProviderRemediationMapRemediationURLs = @"Value";',
        "a pointer to a const string is defined as const NSString * (NSString const * in the SDK)")
    check(definition("kNEHotspotHelperOptionDisplayName", "const NSString *")
        == 'const NSString * kNEHotspotHelperOptionDisplayName = @"Value";',
        "a leading const before the pointer's star is kept in front of the string")

    -- the variable is const: the star comes before const, as in the SDK's NSString * const declarations
    check(definition("NEVPNErrorDomain", "NSString * const") == 'NSString *const NEVPNErrorDomain = @"Value";',
        "NSString * const defines a const variable")
    check(definition("NEVPNErrorDomain", "NSString *const") == 'NSString *const NEVPNErrorDomain = @"Value";',
        "NSString *const, without a space, defines a const variable")
    check(definition("NEAppPushErrorDomain", "NSErrorDomain const") == 'NSString *const NEAppPushErrorDomain = @"Value";',
        "a typedef with a const in front (NSErrorDomain const, no star) defines a const variable")

    -- neither qualifier: a plain string pointer
    check(definition("NEFooKey", "NSString *") == 'NSString * NEFooKey = @"Value";', "NSString * defines a plain string pointer")

    -- both: the string and the variable are const
    check(definition("NEBothKey", "const NSString * const") == 'const NSString *const NEBothKey = @"Value";',
        "a const pointee and a const variable are both spelled")

    -- CoreFoundation shape: the typedef already holds the pointee const, so only a leading const is the variable's
    check(definition("kCFFoo", "CFStringRef", "cf") == 'CFStringRef kCFFoo = (__bridge CFStringRef)@"Value";',
        "a CFStringRef constant has no const")
    check(definition("kCFBar", "const CFStringRef", "cf") == 'const CFStringRef kCFBar = (__bridge CFStringRef)@"Value";',
        "a const CFStringRef constant is a const variable")

    print("render test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)))
    if failures > 0 then
        os.exit(1)
    end
end
