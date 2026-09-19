-- The rewrite at the heart of the header lift: the iOS release of an availability macro, in each spelling the SDK uses,
-- comes down to the target, and nothing else in the line moves.
function failures(opt)
    local lift = import("apple.lift", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local cases = {
        {"API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0))", "API_AVAILABLE(macos(10.9), ios(6.0), watchos(2.0), tvos(9.0))"},
        {"API_AVAILABLE(ios(8.2));", "API_AVAILABLE(ios(6.0));"},
        {"API_DEPRECATED(\"Use x\", macos(10.9, 10.15), ios(7.0, 13.0)) NS_REFINED_FOR_SWIFT;",
         "API_DEPRECATED(\"Use x\", macos(10.9, 10.15), ios(6.0, 13.0)) NS_REFINED_FOR_SWIFT;"},
        {"NS_AVAILABLE(10_9, 7_0);", "NS_AVAILABLE(10_9, 6_0);"},
        {"NS_CLASS_AVAILABLE(10_9, 7_0)", "NS_CLASS_AVAILABLE(10_9, 6_0)"},
        {"NS_AVAILABLE_IOS(7_0);", "NS_AVAILABLE_IOS(6_0);"},
        {"__IOS_AVAILABLE(7.0)", "__IOS_AVAILABLE(6.0)"},
        {"CF_EXPORT", "CF_EXPORT"}
    }
    for _, case in ipairs(cases) do
        local got = lift.lift_macro(case[1], "6.0")
        if got ~= case[2] then
            table.insert(found, string.format("%s became %s, not %s", case[1], got, case[2]))
        end
    end

    -- The redeclaration of a member the SDK gives only as a protocol requirement, from the nodes clang dumps for
    -- UITraitEnvironment: a property whose type carries a nested availability macro (ios(8.0) has parens inside parens),
    -- and a method whose selector part pairs with its parameter.
    local declarations = {
        {{kind = "ObjCPropertyDecl", type = {qualType = "API_AVAILABLE(ios(8.0)) UITraitCollection *"}}, "traitCollection", "6.0",
         "@property (nonatomic, readonly) UITraitCollection * traitCollection API_AVAILABLE(ios(6.0));"},
        {{kind = "ObjCMethodDecl", returnType = {qualType = "void"},
          inner = {{kind = "ParmVarDecl", name = "previousTraitCollection", type = {qualType = "UITraitCollection * _Nullable"}}}},
         "traitCollectionDidChange:", "6.0",
         "- (void)traitCollectionDidChange:(UITraitCollection * _Nullable)previousTraitCollection API_AVAILABLE(ios(6.0));"},
        {{kind = "ObjCMethodDecl", returnType = {qualType = "BOOL"},
          inner = {{kind = "ParmVarDecl", name = "date", type = {qualType = "NSDate *"}},
                   {kind = "ParmVarDecl", name = "options", type = {qualType = "NSUInteger"}}}},
         "isDate:options:", "5.0", "- (BOOL)isDate:(NSDate *)date options:(NSUInteger)options API_AVAILABLE(ios(5.0));"},
        {{kind = "ObjCMethodDecl", returnType = {qualType = "id"}}, "copy", "6.0", "- (id)copy API_AVAILABLE(ios(6.0));"},
    }
    for _, case in ipairs(declarations) do
        local got = lift.protocol_member_declaration(case[1], case[2], case[3])
        if got ~= case[4] then
            table.insert(found, string.format("%s was redeclared as %s, not %s", case[2], got, case[4]))
        end
    end
    return found
end
