-- The rewrite at the heart of the header lift: the iOS release an availability macro spells as ios(...) comes down to the
-- target, and nothing else in the line moves; any other spelling is left for its expansion.
local function expect_equal(found, what, got, wanted)
    if got ~= wanted then
        table.insert(found, string.format("%s was %s, not %s", what, tostring(got), tostring(wanted)))
    end
end

function failures(opt)
    local lift = import("apple.lift", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local cases = {
        {"API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0))", "API_AVAILABLE(macos(10.9), ios(6.0), watchos(2.0), tvos(9.0))"},
        {"API_AVAILABLE(ios(8.2));", "API_AVAILABLE(ios(6.0));"},
        {"API_DEPRECATED(\"Use x\", macos(10.9, 10.15), ios(7.0, 13.0)) NS_REFINED_FOR_SWIFT;",
         "API_DEPRECATED(\"Use x\", macos(10.9, 10.15), ios(6.0, 13.0)) NS_REFINED_FOR_SWIFT;"},
        {"NS_AVAILABLE(10_9, 7_0);", "NS_AVAILABLE(10_9, 7_0);"},
        {"NS_CLASS_AVAILABLE(10_9, 7_0)", "NS_CLASS_AVAILABLE(10_9, 7_0)"},
        {"NS_AVAILABLE_IOS(7_0);", "NS_AVAILABLE_IOS(7_0);"},
        {"__IOS_AVAILABLE(7.0)", "__IOS_AVAILABLE(7.0)"},
        -- a release passed by position is no ios(...) in the text: each of these is left to its expansion
        {"CF_EXPORT", "CF_EXPORT"},
        -- several releases in one call are not one availability macro: lift_macro leaves them to the expansion
        {"DISPATCH_OPTIONS(f, unsigned long, A DISPATCH_ENUM_API_AVAILABLE(ios(8.0)) = 1, B DISPATCH_ENUM_API_AVAILABLE(ios(8.0)) = 2)",
         "DISPATCH_OPTIONS(f, unsigned long, A DISPATCH_ENUM_API_AVAILABLE(ios(8.0)) = 1, B DISPATCH_ENUM_API_AVAILABLE(ios(8.0)) = 2)"},
        -- UICollectionViewListCell's own declaration: an otherwise-dotted API_AVAILABLE whose ios() argument is
        -- spelled with an underscore. The character class has to eat the whole token, dot or underscore, or it stops
        -- at the underscore and leaves it behind (ios(14_0) -> ios(6.1.3_0), a release clang cannot parse).
        {"API_AVAILABLE(ios(14_0), tvos(14.0), watchos(7.0)) NS_SWIFT_UI_ACTOR",
         "API_AVAILABLE(ios(6.0), tvos(14.0), watchos(7.0)) NS_SWIFT_UI_ACTOR"},
        -- memset_s/openat/unlinkat's own spelling pastes named platform constants into a macro name: no argument to
        -- rewrite in place, so lift_macro leaves it to the expansion
        {"__OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0)", "__OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0)"}
    }
    for _, case in ipairs(cases) do
        local got = lift.lift_macro(case[1], "6.0")
        if got ~= case[2] then
            table.insert(found, string.format("%s became %s, not %s", case[1], got, case[2]))
        end
    end

    -- A call no lift_macro branch rewrites in place is replaced by its own expansion, with the iOS release lowered:
    -- IMAGEIO_AVAILABLE_STARTING(10.14, 12.0) and __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_12, __MAC_10_13,
    -- __IPHONE_10_0, __IPHONE_11_0) as clang -E writes them for an iOS triple. An expansion with no iOS release
    -- (__IPHONE_NA pastes to a macro that expands to nothing iOS) is refused, not guessed at.
    local expansions = {
        {"__attribute__((availability(macos,introduced=10.14))) __attribute__((availability(ios,introduced=12.0)))",
         "__attribute__((availability(macos,introduced=10.14))) __attribute__((availability(ios,introduced=6.0)))"},
        {"__attribute__((availability(ios,introduced=10.0,deprecated=11.0)))",
         "__attribute__((availability(ios,introduced=6.0,deprecated=11.0)))"},
        {"__attribute__((availability(ios,unavailable)))", nil},
        -- __CLOCK_AVAILABILITY where time.h uses it: four platforms, the macOS one first
        {"__attribute__((availability(macosx,introduced=10.12))) __attribute__((availability(ios,introduced=10.0))) "
         .. "__attribute__((availability(tvos,introduced=10.0))) __attribute__((availability(watchos,introduced=3.0)))",
         "__attribute__((availability(macosx,introduced=10.12))) __attribute__((availability(ios,introduced=6.0))) "
         .. "__attribute__((availability(tvos,introduced=10.0))) __attribute__((availability(watchos,introduced=3.0)))"},
        -- DISPATCH_OPTIONS: one release per enumerator, lowered only when every enumerator is ours
        {"A __attribute__((availability(ios,introduced=8.0))) = 1, B __attribute__((availability(ios,introduced=8.0))) = 2",
         "A __attribute__((availability(ios,introduced=6.0))) = 1, B __attribute__((availability(ios,introduced=6.0))) = 2", 2},
        {"A __attribute__((availability(ios,introduced=8.0))) = 1, B __attribute__((availability(ios,introduced=8.0))) = 2", nil, 1},
    }
    for _, case in ipairs(expansions) do
        local got = lift.lift_expansion(case[1], "6.0", case[3] or 1)
        if got ~= case[2] then
            table.insert(found, string.format("the expansion %s became %s, not %s", case[1], tostring(got), tostring(case[2])))
        end
    end

    -- The use of a macro a mark's site starts, in the SDK's own spellings: a call whose ios(...) is a line below its
    -- name (CADisplayLink.h), an object-like macro after an enumerator (time.h) and before a declaration on the next line
    -- (os/lock.h), and a call that never closes, which is no use at all.
    local uses = {
        {{"@property(nonatomic) NSInteger preferredFramesPerSecond",
          "  API_DEPRECATED_WITH_REPLACEMENT (\"preferredFrameRateRange\",",
          "                                   ios(10.0, API_TO_BE_DEPRECATED));"}, 2, 3,
         "API_DEPRECATED_WITH_REPLACEMENT (\"preferredFrameRateRange\",\n                                   ios(10.0, API_TO_BE_DEPRECATED))", 2},
        {{"_CLOCK_REALTIME __CLOCK_AVAILABILITY = 0,"}, 1, 17, "__CLOCK_AVAILABILITY", 1},
        {{"OS_UNFAIR_LOCK_AVAILABILITY", "OS_EXPORT OS_NOTHROW OS_NONNULL_ALL", "void os_unfair_lock_lock(os_unfair_lock_t lock);"},
         1, 1, "OS_UNFAIR_LOCK_AVAILABILITY", 1},
        {{"API_AVAILABLE(ios(8.0)"}, 1, 1, nil, nil},
    }
    for _, case in ipairs(uses) do
        local use, count = lift.macro_use(case[1], case[2], case[3])
        if use ~= case[4] or count ~= case[5] then
            table.insert(found, string.format("the use at %d:%d of %s was %s over %s lines, not %s over %s", case[2], case[3],
                         table.concat(case[1], "\\n"), tostring(use), tostring(count), tostring(case[4]), tostring(case[5])))
        end
    end

    -- The redeclaration of a member the SDK gives a class only in a protocol it conforms to or in a superclass, and of a
    -- setter apart from its property, from the nodes clang dumps for them (-ast-dump=json of iPhoneOS16.4.sdk; a
    -- property's attributes are the ones clang says it has, inferred ones included, all of which compile together as
    -- written here, with and without ARC). UITraitEnvironment: a property whose type carries a nested availability macro
    -- (ios(8.0) has parens inside parens), and a method whose selector part pairs with its parameter.
    local declarations = {
        {{kind = "ObjCPropertyDecl", readonly = true, nonatomic = true, type = {qualType = "API_AVAILABLE(ios(8.0)) UITraitCollection *"}},
         "traitCollection", "6.0", "@property (nonatomic, readonly) UITraitCollection * traitCollection API_AVAILABLE(ios(6.0));"},
        {{kind = "ObjCMethodDecl", instance = true, returnType = {qualType = "void"},
          inner = {{kind = "ParmVarDecl", name = "previousTraitCollection", type = {qualType = "UITraitCollection * _Nullable"}}}},
         "traitCollectionDidChange:", "6.0",
         "- (void)traitCollectionDidChange:(UITraitCollection * _Nullable)previousTraitCollection API_AVAILABLE(ios(6.0));"},
        {{kind = "ObjCMethodDecl", instance = true, returnType = {qualType = "BOOL"},
          inner = {{kind = "ParmVarDecl", name = "date", type = {qualType = "NSDate *"}},
                   {kind = "ParmVarDecl", name = "options", type = {qualType = "NSUInteger"}}}},
         "isDate:options:", "5.0", "- (BOOL)isDate:(NSDate *)date options:(NSUInteger)options API_AVAILABLE(ios(5.0));"},
        {{kind = "ObjCMethodDecl", instance = true, returnType = {qualType = "id"}}, "copy", "6.0", "- (id)copy API_AVAILABLE(ios(6.0));"},
        -- NSItemProviderReading: a class method (instance is false) and a class property
        {{kind = "ObjCMethodDecl", instance = false, returnType = {qualType = "instancetype _Nullable"},
          inner = {{kind = "ParmVarDecl", name = "data", type = {qualType = "NSData * _Nonnull"}},
                   {kind = "ParmVarDecl", name = "typeIdentifier", type = {qualType = "NSString * _Nonnull"}},
                   {kind = "ParmVarDecl", name = "outError", type = {qualType = "NSError * _Nullable * _Nullable"}}}},
         "objectWithItemProviderData:typeIdentifier:error:", "6.1.3",
         "+ (instancetype _Nullable)objectWithItemProviderData:(NSData * _Nonnull)data typeIdentifier:(NSString * _Nonnull)typeIdentifier error:(NSError * _Nullable * _Nullable)outError API_AVAILABLE(ios(6.1.3));"},
        {{kind = "ObjCPropertyDecl", class = true, readonly = true, copy = true, nonatomic = true, type = {qualType = "NSArray<NSString *> * _Nonnull"}},
         "readableTypeIdentifiersForItemProvider", "6.1.3",
         "@property (class, nonatomic, readonly, copy) NSArray<NSString *> * _Nonnull readableTypeIdentifiersForItemProvider API_AVAILABLE(ios(6.1.3));"},
        -- GCDevice's handlerQueue, readwrite, and UIControl's enabled, whose getter has a name of its own
        {{kind = "ObjCPropertyDecl", readwrite = true, nonatomic = true, strong = true, type = {qualType = "dispatch_queue_t _Nonnull"}},
         "handlerQueue", "6.1.3", "@property (nonatomic, readwrite, strong) dispatch_queue_t _Nonnull handlerQueue API_AVAILABLE(ios(6.1.3));"},
        {{kind = "ObjCPropertyDecl", readwrite = true, nonatomic = true, assign = true, unsafe_unretained = true,
          getter = {kind = "ObjCMethodDecl", name = "isEnabled"}, type = {qualType = "BOOL"}},
         "enabled", "6.1.3", "@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isEnabled) BOOL enabled API_AVAILABLE(ios(6.1.3));"},
        -- refused: a block property needs a declarator around its name, and a type that keeps another macro's attribute
        -- would lose it
        {{kind = "ObjCPropertyDecl", copy = true, nonatomic = true, type = {qualType = "void (^)(void)"}}, "handler", "6.1.3", nil},
        {{kind = "ObjCMethodDecl", instance = true, returnType = {qualType = "API_DEPRECATED(\"use x\", ios(8.0, 9.0)) NSString *"}},
         "name", "6.1.3", nil},
    }
    for _, case in ipairs(declarations) do
        local got = lift.member_declaration(case[1], case[2], case[3])
        if got ~= case[4] then
            table.insert(found, string.format("%s was redeclared as %s, not %s", case[2], tostring(got), tostring(case[4])))
        end
    end
    -- The text a use stands for in the five languages that read the lifted headers. clang -E of the SDK's
    -- UIKIT_CLASS_AVAILABLE_IOS_ONLY(13.0) (UISearchTextField.h) through UIKIT_EXTERN is extern in C, Objective-C and
    -- Swift's importer and extern "C" in C++ and Objective-C++; NS_CLASS_AVAILABLE_IOS(8_0) is one text in all five, and
    -- spaces between the same tokens tell no two apart. Which macros each predefines is clang -dM's for the same
    -- languages (armv7-apple-ios6.1.3): __cplusplus in C++ and Objective-C++, __OBJC__ in Objective-C, Objective-C++ and
    -- Swift, __swift__ in Swift alone.
    local uikit = " __attribute__((visibility (\"default\"))) __attribute__((availability(ios,introduced=13.0))) "
                  .. "__attribute__((availability(watchos,unavailable))) __attribute__((availability(tvos,unavailable)))"
    local class = "__attribute__((visibility(\"default\"))) __attribute__((availability(ios,introduced=8_0)))"
    local predefined = {C = {}, ["Objective-C"] = {__OBJC__ = true}, ["C++"] = {__cplusplus = true},
                        ["Objective-C++"] = {__cplusplus = true, __OBJC__ = true}, Swift = {__OBJC__ = true, __swift__ = true}}
    local function five(c, objc, cxx, objcxx, swift)
        return {{language = "C", text = c}, {language = "Objective-C", text = objc}, {language = "C++", text = cxx},
                {language = "Objective-C++", text = objcxx}, {language = "Swift", text = swift}}
    end
    local linkage = five("extern" .. uikit, "extern" .. uikit, "extern \"C\"" .. uikit, "extern \"C\"" .. uikit, "extern" .. uikit)
    local split = {{"!defined(__cplusplus)", "extern" .. uikit}, {"defined(__cplusplus)", "extern \"C\"" .. uikit}}
    local languages = {
        -- one text where all agree
        {five(class, class, class, class, class), {"__cplusplus", "__OBJC__", "__swift__"}, class},
        {{{language = "C", text = class}, {language = "C++", text = (class:gsub(" ", "\n  "))}}, {"__cplusplus"}, class},
        -- the linkage splits on __cplusplus, the fewest macros that tell it apart, whichever the SDK tests more
        {linkage, {"__cplusplus", "__OBJC__", "__swift__"}, split},
        {linkage, {"__OBJC__", "__swift__", "__cplusplus"}, split},
        -- three texts no one macro tells apart: two, and a combination no language has is left to refuse
        {{{language = "C", text = "a"}, {language = "Objective-C", text = "b"}, {language = "Swift", text = "c"}},
         {"__OBJC__", "__swift__"},
         {{"!defined(__OBJC__) && !defined(__swift__)", "a"}, {"defined(__OBJC__) && !defined(__swift__)", "b"},
          {"defined(__OBJC__) && defined(__swift__)", "c"}}, true},
        -- C and Objective-C differ, and no macro given tells them apart: refused
        {five("a", "b", "a", "a", "a"), {"__cplusplus"}, nil},
    }
    for index, case in ipairs(languages) do
        local got, why = lift.by_language(case[1], predefined, case[2])
        local shown = got
        if type(got) == "table" then
            local parts = {}
            for _, branch in ipairs(got.branches) do
                table.insert(parts, branch.condition .. " => " .. branch.text)
            end
            shown = table.concat(parts, " | ") .. (got.rest and " | rest" or "")
        end
        local wanted = case[3]
        if type(wanted) == "table" then
            local parts = {}
            for _, branch in ipairs(wanted) do
                table.insert(parts, branch[1] .. " => " .. branch[2])
            end
            wanted = table.concat(parts, " | ") .. (case[4] and " | rest" or "")
        end
        if shown ~= wanted or (got == nil) ~= (why ~= nil) then
            table.insert(found, string.format("languages %d gave %s (%s), not %s", index, tostring(shown), tostring(why), tostring(wanted)))
        end
    end
    -- and the text written for the split: each branch lowered on lines of its own, and a combination no language has
    -- stopped with the use's name
    local lowered = uikit:gsub("introduced=13%.0", "introduced=6.1.3")
    local conditionals = {
        {lift.by_language(linkage, predefined, {"__cplusplus"}), "\n#if !defined(__cplusplus)\nextern" .. lowered
         .. "\n#elif defined(__cplusplus)\nextern \"C\"" .. lowered .. "\n#endif\n"},
        {{branches = {{condition = "!defined(__OBJC__)", text = "extern" .. uikit}}, rest = true},
         "\n#if !defined(__OBJC__)\nextern" .. lowered .. "\n#else\n#error \"the lifted UIKIT_CLASS_AVAILABLE_IOS_ONLY was "
         .. "expanded for no language with these macros\"\n#endif\n"},
        -- a branch with no iOS release is not lowered, and neither is the use
        {{branches = {{condition = "defined(__cplusplus)", text = "extern"}}}, nil},
    }
    for index, case in ipairs(conditionals) do
        local got = lift.language_conditional(case[1], "6.1.3", 1, "UIKIT_CLASS_AVAILABLE_IOS_ONLY(13.0)")
        if got ~= case[2] then
            table.insert(found, string.format("conditional %d was %s, not %s", index, tostring(got), tostring(case[2])))
        end
    end

    -- Where a declaration inside a #pragma clang attribute region (API_AVAILABLE_BEGIN) takes an availability of its own.
    -- The header below and the nodes are clang 23.1.1's dump of it for armv7-apple-ios6.1.3 against iPhoneOS16.4.sdk (the
    -- file, line and column fields left out). Each placement is the one measured to work: the same header with the
    -- attribute written there dumps ios 6.1.3 for that declaration alone - ZzLvlB, -[NSObject c] and the field f keep the
    -- region's 8.
    local header = table.concat({
        "#import <Foundation/Foundation.h>",
        "API_AVAILABLE_BEGIN(macos(10.13), ios(8), tvos(10))",
        "@class ZzCls;",
        "typedef NS_ENUM(NSInteger, ZzLvl) {",
        "    ZzLvlA = 1,",
        "    ZzLvlB = 2,",
        "};",
        "@protocol ZzProto",
        "- (void)p;",
        "@end",
        "@interface ZzCls : NSObject",
        "- (void)m:(int)x;",
        "@property (nonatomic) int prop;",
        "@end",
        "@interface NSObject (ZzCat)",
        "- (void)c;",
        "@end",
        "typedef struct ZzRec {",
        "    int f;",
        "} ZzRecT;",
        "extern NSString *const ZzKey;",
        "void zzFunction(void);",
        "API_AVAILABLE_END",
        ""}, "\n")
    local A = "__attribute__((availability(ios,introduced=6.1.3)))"
    local forward_class = {kind = "ObjCInterfaceDecl", name = "ZzCls", loc = {offset = 93, tokLen = 5},
                           range = {begin = {offset = 86, tokLen = 1}, ["end"] = {offset = 93, tokLen = 5}}}
    local forward_enum = {kind = "EnumDecl", name = "ZzLvl", loc = {spellingLoc = {offset = 127, tokLen = 5}, expansionLoc = {offset = 108, tokLen = 7}},
                          range = {begin = {spellingLoc = {offset = 7456, tokLen = 4}, expansionLoc = {offset = 108, tokLen = 7}},
                                   ["end"] = {spellingLoc = {offset = 116, tokLen = 9}, expansionLoc = {offset = 108, tokLen = 7}}}}
    local enum = {kind = "EnumDecl", name = "ZzLvl", loc = {spellingLoc = {offset = 127, tokLen = 5}, expansionLoc = {offset = 108, tokLen = 7}},
                  range = {begin = {spellingLoc = {offset = 7503, tokLen = 4}, expansionLoc = {offset = 108, tokLen = 7}},
                           ["end"] = {offset = 168, tokLen = 1}}}
    local placements = {
        {{kind = "TypedefDecl", name = "ZzLvl", loc = {spellingLoc = {offset = 127, tokLen = 5}, expansionLoc = {offset = 108, tokLen = 7}},
          range = {begin = {offset = 100, tokLen = 7}, ["end"] = {spellingLoc = {offset = 127, tokLen = 5}, expansionLoc = {offset = 108, tokLen = 7}}}},
         A .. " typedef NS_ENUM(NSInteger, ZzLvl) {"},
        {{kind = "EnumConstantDecl", name = "ZzLvlA", loc = {offset = 140, tokLen = 6},
          range = {begin = {offset = 140, tokLen = 6}, ["end"] = {offset = 149, tokLen = 1}}}, "    ZzLvlA " .. A .. " = 1,"},
        {enum, "} " .. A .. ";"},
        {{kind = "ObjCProtocolDecl", name = "ZzProto", loc = {offset = 181, tokLen = 7},
          range = {begin = {offset = 171, tokLen = 1}, ["end"] = {offset = 201, tokLen = 3}}}, A .. " @protocol ZzProto"},
        {{kind = "ObjCMethodDecl", name = "p", loc = {offset = 189, tokLen = 1},
          range = {begin = {offset = 189, tokLen = 1}, ["end"] = {offset = 198, tokLen = 1}}}, "- (void)p " .. A .. ";"},
        {{kind = "ObjCInterfaceDecl", name = "ZzCls", loc = {offset = 216, tokLen = 5},
          range = {begin = {offset = 205, tokLen = 1}, ["end"] = {offset = 284, tokLen = 3}}}, A .. " @interface ZzCls : NSObject"},
        {{kind = "ObjCMethodDecl", name = "m:", loc = {offset = 233, tokLen = 1},
          range = {begin = {offset = 233, tokLen = 1}, ["end"] = {offset = 249, tokLen = 1}}}, "- (void)m:(int)x " .. A .. ";"},
        {{kind = "ObjCPropertyDecl", name = "prop", loc = {offset = 277, tokLen = 4},
          range = {begin = {offset = 251, tokLen = 1}, ["end"] = {offset = 277, tokLen = 4}}}, "@property (nonatomic) int prop " .. A .. ";"},
        {{kind = "ObjCCategoryDecl", name = "ZzCat", interface = {name = "NSObject"}, loc = {offset = 299, tokLen = 8},
          range = {begin = {offset = 288, tokLen = 1}, ["end"] = {offset = 328, tokLen = 3}}}, A .. " @interface NSObject (ZzCat)"},
        {{kind = "RecordDecl", name = "ZzRec", loc = {offset = 347, tokLen = 5},
          range = {begin = {offset = 340, tokLen = 6}, ["end"] = {offset = 366, tokLen = 1}}}, "} " .. A .. " ZzRecT;"},
        {{kind = "TypedefDecl", name = "ZzRecT", loc = {offset = 368, tokLen = 6},
          range = {begin = {offset = 332, tokLen = 7}, ["end"] = {offset = 368, tokLen = 6}}}, A .. " typedef struct ZzRec {"},
        {{kind = "VarDecl", name = "ZzKey", loc = {offset = 399, tokLen = 5},
          range = {begin = {offset = 376, tokLen = 6}, ["end"] = {offset = 399, tokLen = 5}}}, A .. " extern NSString *const ZzKey;"},
        {{kind = "FunctionDecl", name = "zzFunction", loc = {offset = 411, tokLen = 10},
          range = {begin = {offset = 406, tokLen = 4}, ["end"] = {offset = 426, tokLen = 1}}}, A .. " void zzFunction(void);"},
        -- a forward declaration takes none: @class, and the enum X : T X NS_ENUM writes before the definition
        {forward_class, nil},
        {forward_enum, nil},
        -- nor does a declaration whose name is not where the dump says: a location one byte off, and a method node
        -- whose name is not the selector its text spells
        {{kind = "VarDecl", name = "ZzKey", loc = {offset = 400, tokLen = 5},
          range = {begin = {offset = 376, tokLen = 6}, ["end"] = {offset = 399, tokLen = 5}}}, nil},
        {{kind = "ObjCMethodDecl", name = "q", loc = {offset = 189, tokLen = 1},
          range = {begin = {offset = 189, tokLen = 1}, ["end"] = {offset = 198, tokLen = 1}}}, nil},
    }
    for _, case in ipairs(placements) do
        local offset, text = lift.declared_at(header, case[1], "6.1.3")
        local got
        if offset then
            local placed = header:sub(1, offset) .. text .. header:sub(offset + 1)
            local line_start = offset
            while line_start > 0 and placed:sub(line_start, line_start) ~= "\n" do
                line_start = line_start - 1
            end
            got = placed:sub(line_start + 1):match("^[^\n]*")
        end
        if got ~= case[2] then
            table.insert(found, string.format("%s %s took its own availability as %s, not %s", case[1].kind, case[1].name,
                         tostring(got), tostring(case[2])))
        end
    end

    -- The declaration a use reaches is the latest of those that redeclare each other: of NS_ENUM's forward enum and its
    -- definition (previousDecl, the ids of the same dump) the definition, of @class and @interface the @interface, and a
    -- declaration nothing redeclares stands.
    local redeclarations = {
        {{{id = "0x7b3143f9d8", kind = "EnumDecl"}, {id = "0x7b3143ff98", kind = "EnumDecl", previousDecl = "0x7b3143f9d8"}},
         {"0x7b3143ff98"}},
        {{{id = "0x7b3143f8f8", kind = "ObjCInterfaceDecl"}, {id = "0x7b31440d78", kind = "ObjCInterfaceDecl", previousDecl = "0x7b3143f8f8"},
          {id = "0x7b31440788", kind = "ObjCProtocolDecl"}}, {"0x7b31440d78", "0x7b31440788"}},
    }
    for index, case in ipairs(redeclarations) do
        local ids = {}
        for _, node in ipairs(lift.latest(case[1])) do
            table.insert(ids, node.id)
        end
        if table.concat(ids, ",") ~= table.concat(case[2], ",") then
            table.insert(found, string.format("redeclarations %d: the latest were %s, not %s", index, table.concat(ids, ","),
                         table.concat(case[2], ",")))
        end
    end
    -- The typedefs a declaration's type goes through, from clang 23.1.1's text dump with -ast-dump-decl-types of
    -- dispatch/object.h's dispatch_qos_class_t and sys/qos.h's qos_class_self (ids and the SDK's path shortened): the
    -- typedef dispatch_qos_class_t names, and the return type of qos_class_self, both qos_class_t.
    local listing = table.concat({
        "Dumping dispatch_qos_class_t:",
        "TypedefDecl 0x1 <<sdk>/usr/include/dispatch/object.h:190:1, col:21> col:21 referenced dispatch_qos_class_t 'qos_class_t':'enum qos_class_t'",
        "`-TypedefType 0x1 'qos_class_t' sugar",
        "  |-Typedef 0x1 'qos_class_t'",
        "  `-EnumType 0x1 'enum qos_class_t' owns_tag enum",
        "    `-Enum 0x1 <<sdk>/usr/include/sys/qos.h:121:45, col:71>",
        "TypedefType 0x1 'dispatch_qos_class_t' sugar",
        "|-Typedef 0x1 'dispatch_qos_class_t'",
        "`-TypedefType 0x1 'qos_class_t' sugar",
        "  |-Typedef 0x1 'qos_class_t'",
        "  `-EnumType 0x1 'enum qos_class_t' owns_tag enum",
        "    `-Enum 0x1 <<sdk>/usr/include/sys/qos.h:121:45, col:71>",
        "",
        "Dumping qos_class_self:",
        "FunctionDecl 0x1 <<sdk>/usr/include/AvailabilityInternal.h:4461:28, <sdk>/usr/include/sys/qos.h:172:20> col:1 qos_class_self 'qos_class_t (void)' external-linkage",
        "|-AvailabilityAttr 0x1 <<sdk>/usr/include/AvailabilityInternal.h:4461:43, col:84> macos 10.10 0 0 \"\" \"\" 0",
        "`-AvailabilityAttr 0x1 <col:43, col:84> ios 8.0 0 0 \"\" \"\" 0",
        "FunctionProtoType 0x1 'qos_class_t (void)' cdecl",
        "`-TypedefType 0x1 'qos_class_t' sugar",
        "  |-Typedef 0x1 'qos_class_t'",
        "  `-EnumType 0x1 'enum qos_class_t' owns_tag enum",
        "    `-Enum 0x1 <<sdk>/usr/include/sys/qos.h:121:45, col:71>",
        ""}, "\n")
    local sections = lift.listing_sections(listing)
    local expected_sections = {{"dispatch_qos_class_t", "qos_class_t,dispatch_qos_class_t,qos_class_t"}, {"qos_class_self", "qos_class_t"}}
    for index, case in ipairs(expected_sections) do
        local section = sections[index] or {typedefs = {}}
        if section.heading ~= case[1] or table.concat(section.typedefs, ",") ~= case[2] or #sections ~= #expected_sections then
            table.insert(found, string.format("dump section %d was %s through %s, not %s through %s", index, tostring(section.heading),
                         table.concat(section.typedefs, ","), case[1], case[2]))
        end
    end

    -- Where a type's uses are looked for: a header with its comments and the insides of its literals blanked, every byte in
    -- place, and in it the words the declaration a use stands in could declare - sys/qos.h's return type on the line above
    -- qos_class_self, dispatch/object.h's typedef under #if, AVCaptureDevice.h's documentation naming the type.
    local source = table.concat({
        "/*!",
        " @enum AVAuthorizationStatus",
        " */",
        "// qos_class_t in a comment",
        "__API_AVAILABLE(macos(10.10), ios(8.0))",
        "qos_class_t",
        "qos_class_self(void);",
        "#if __has_include(<sys/qos.h>)",
        "typedef qos_class_t dispatch_qos_class_t;",
        "#endif",
        "API_DEPRECATED_WITH_REPLACEMENT(\"qos_class_t\", ios(8.0, 9.0)) extern const char c; // don't",
        "void f(int a,",
        "       qos_class_t b);",
        ""}, "\n")
    local blanked = lift.code_of(source)
    local _, newlines = blanked:gsub("\n", "")
    local _, uses = blanked:gsub("%f[%w_]qos_class_t%f[^%w_]", "")
    if #blanked ~= #source or newlines ~= 13 or blanked:find("AVAuthorizationStatus", 1, true) or uses ~= 3
       or not blanked:find("\"           \"", 1, true) then
        table.insert(found, "the code of the header was " .. blanked)
    end
    local statements = {
        {"qos_class_t\nqos_class_self", "__API_AVAILABLE,qos_class_self"},
        {"typedef qos_class_t", "dispatch_qos_class_t"},
        -- a parameter's name stands inside the parens, the function's before them
        {"       qos_class_t b", "f"},
    }
    for _, case in ipairs(statements) do
        local at = blanked:find(case[1], 1, true)
        local words = at and table.concat(lift.statement_words(blanked, at), ",")
        if words ~= case[2] then
            table.insert(found, string.format("the declaration at %s could declare %s, not %s", case[1], tostring(words), case[2]))
        end
    end
    -- The tokens a preprocessor keeps, by the line they came from, out of clang 23.1.1's -E of os/lock.h and
    -- libkern/OSSpinLockDeprecated.h (C, armv7-apple-ios6.1.3; the SDK's path shortened, attributes cut): os/lock.h:115
    -- takes os_unfair_lock_t, while OSSpinLockDeprecated.h:79 keeps os_unfair_lock only inside the message
    -- OSSPINLOCK_DEPRECATED_REPLACE_WITH makes of it - no use of the type.
    local output = table.concat({
        "# 112 \"<sdk>/usr/include/os/lock.h\" 3 4",
        "__attribute__((availability(ios,introduced=10.0)))",
        "extern __attribute__((__visibility__(\"default\"))) __attribute__((__nothrow__)) __attribute__((__nonnull__))",
        "__attribute__((__swift_attr__(\"@_unavailableFromAsync(message: \\\"\" \"Use OSAllocatedUnfairLock.performWhileLocked()\" \"\\\")\")))",
        "void os_unfair_lock_lock(os_unfair_lock_t lock);",
        "# 79 \"<sdk>/usr/include/libkern/OSSpinLockDeprecated.h\" 3 4",
        "typedef int32_t OSSpinLock __attribute__((availability(ios,deprecated=10.0,message=\"Use \" \"os_unfair_lock\" \"() from <os/lock.h> instead\")));",
        ""}, "\n")
    local kept, reached = {}, {}
    lift.tokens_kept(output, {os_unfair_lock = true, os_unfair_lock_t = true, OSSpinLock = true}, kept, reached)
    local lock, spin = "<sdk>/usr/include/os/lock.h", "<sdk>/usr/include/libkern/OSSpinLockDeprecated.h"
    if not (reached[lock] and reached[spin]) or not ((kept[lock] or {})[115] or {}).os_unfair_lock_t
       or ((kept[spin] or {})[79] or {}).os_unfair_lock or not ((kept[spin] or {})[79] or {}).OSSpinLock
       or #table.keys((kept[lock] or {})[114] or {}) > 0 then
        table.insert(found, "the preprocessor's tokens were read back as " .. string.serialize(kept, {strip = true, indent = false}))
    end
    -- What the lift leaves alone is compared with the set measured for the SDK: a line that is new, or gone, is named; comments are not lines.
    local registry = {_ceil = {}, _floor = {kind = "protocol"}, NSNoSuchClass = {kind = "class"}}
    local lines = lift.left_alone({"_ceil", "_floor", "NSNoSuchClass"}, {{api = "-[NSCoder setX:]", how = "declared nowhere"}, {api = "-[NSY z]", how = "owner not found"}}, registry)
    expect_equal(found, "what is left alone, with its kinds", table.concat(lines, "|"),
                 "class\tNSNoSuchClass\t|undeclared\t-[NSCoder setX:]\tdeclared nowhere|undeclared\t-[NSY z]\towner not found|" ..
                 "unmatched\t_ceil\tfunction or constant|unmatched\t_floor\tprotocol")
    local measured = "# measured on SDK x\n" .. table.concat(lines, "\n") .. "\n"
    local function named(list)
        return table.concat(list, "; ")
    end
    expect_equal(found, "a lift that finds what was measured", named(lift.differences(lines, measured)), "")
    expect_equal(found, "a name that is new", named(lift.differences(lines, measured:gsub("unmatched\t_ceil\tfunction or constant\n", ""))), "new: unmatched _ceil function or constant")
    expect_equal(found, "a name that is gone", named(lift.differences({lines[1], lines[2], lines[3], lines[4]}, measured)), "no longer found: unmatched _floor protocol")
    expect_equal(found, "a member found another way than measured", named(lift.differences(lift.left_alone({"_ceil", "_floor", "NSNoSuchClass"},
                 {{api = "-[NSCoder setX:]", how = "declared only by NSSecureCoding"}, {api = "-[NSY z]", how = "owner not found"}}, registry), measured)),
                 "new: undeclared -[NSCoder setX:] declared only by NSSecureCoding; no longer found: undeclared -[NSCoder setX:] declared nowhere")
    expect_equal(found, "no measured set at all", #lift.differences(lines, ""), 5)
    -- A kept accessor whose property is carried, joined by the attribute each is written from: the one join there is
    -- when the accessor is named by its getter rather than by the property it reads.
    -- an implicit accessor written from a property: its attribute is the property's, at the line the property is
    -- written at, so the line is the helper's to take - a case about a location two properties share has to write
    -- the accessor there, or it is not about that location at all
    local function accessor(qualified, selector, line)
        return {kind = "ObjCMethodDecl", name = selector, isImplicit = true, instance = true, _qualified = qualified,
                inner = {{kind = "AvailabilityAttr", platform = "ios", introduced = "9.0",
                          range = {begin = {expansionLoc = {file = "NSProcessInfo.h", line = line or 222, col = 5}}}}}}
    end
    local kept = {["-[NSProcessInfo isLowPowerModeEnabled]"] = true}
    local listed = {["-[NSProcessInfo isLowPowerModeEnabled]"] = {api = "-[NSProcessInfo isLowPowerModeEnabled]", status = "inert"},
                    ["NSProcessInfo.lowPowerModeEnabled"] = {api = "NSProcessInfo.lowPowerModeEnabled", status = "implemented"}}
    local where_of = {["NSProcessInfo.h:222:5"] = {"NSProcessInfo.lowPowerModeEnabled"}}
    local answers = {accessor("NSProcessInfo::isLowPowerModeEnabled", "isLowPowerModeEnabled")}
    expect_equal(found, "a kept accessor of a carried property", #lift.accessor_conflicts(kept, listed, answers, where_of), 1)
    expect_equal(found, "and it names both rows",
                 (lift.accessor_conflicts(kept, listed, answers, where_of)[1] or ""):match("isLowPowerModeEnabled%] is inert") ~= nil, true)
    -- the same accessor with nothing carried under its attribute: nothing to refuse
    expect_equal(found, "a kept accessor of nothing carried", #lift.accessor_conflicts(kept, listed, answers, {}), 0)
    -- an explicit accessor is its own declaration, whatever else shares the class
    local written = accessor("NSProcessInfo::isLowPowerModeEnabled", "isLowPowerModeEnabled")
    written.isImplicit = false
    expect_equal(found, "an accessor the header writes itself", #lift.accessor_conflicts(kept, listed, {written}, where_of), 0)
    -- the accessor carried as well as the property: one API, one answer, nothing to refuse
    kept["-[NSProcessInfo isLowPowerModeEnabled]"] = nil
    listed["-[NSProcessInfo isLowPowerModeEnabled]"] = {api = "-[NSProcessInfo isLowPowerModeEnabled]", status = "implemented"}
    -- The candidate an accessor suggests, and the acceptance test beside it. `isTextDragActive` is the getter
    -- @property (getter=isTextDragActive) BOOL textDragActive declares, on a protocol UIView adopts, so the
    -- candidate is `textDragActive`; and a property is only that property when the getter it declares IS the
    -- accessor, which `isolated` and any similarly named property cannot pass.
    expect_equal(found, "the property an accessor suggests", lift.getter_property("isTextDragActive"), "textDragActive")
    expect_equal(found, "a class property is its own candidate", lift.getter_property("readableTypeIdentifiers"), nil)
    expect_equal(found, "an accessor that is not a getter names nothing", lift.getter_property("viewIsAppearing"), nil)
    local declared = {getter = {name = "isTextDragActive"}}
    expect_equal(found, "a property whose getter is the accessor is the one", (declared.getter or declared).name, "isTextDragActive")
    local unrelated = {getter = {name = "textDragActive"}}
    expect_equal(found, "and one whose getter is not the accessor is not",
                 ((unrelated.getter or unrelated).name == "isTextDragActive") and "matched" or "refused", "refused")

    expect_equal(found, "both spellings carried", #lift.accessor_conflicts(kept, listed, answers, where_of), 0)

    -- A macro that expands to two declarations writes both their availability attributes at one place, so a
    -- location can carry two properties. Which one a getter was written from is then not something the location
    -- can say, and pairing it with either refuses two rows that have nothing to do with each other: a false
    -- refusal stops a lift, while a miss is a number. These are the reviewer's two cases.
    local shared = {["NSProcessInfo.h:300:5"] = {"NSProcessInfo.thermalState", "NSProcessInfo.lowPowerModeEnabled"}}
    local thermal = {api = "NSProcessInfo.thermalState", kind = "property", status = "implemented"}
    local kept_low = {["-[NSProcessInfo isLowPowerModeEnabled]"] = true}
    local listed_low = {["-[NSProcessInfo isLowPowerModeEnabled]"] = {api = "-[NSProcessInfo isLowPowerModeEnabled]", status = "inert"},
                        ["NSProcessInfo.thermalState"] = thermal, ["NSProcessInfo.lowPowerModeEnabled"] = listed["NSProcessInfo.lowPowerModeEnabled"]}
    local low = {accessor("NSProcessInfo::isLowPowerModeEnabled", "isLowPowerModeEnabled", 300)}
    expect_equal(found, "a macro's shared location, getter paired with the other property", #lift.accessor_conflicts(kept_low, listed_low, low, shared), 0)
    local kept_thermal = {["-[NSProcessInfo thermalState]"] = true}
    local listed_thermal = {["-[NSProcessInfo thermalState]"] = {api = "-[NSProcessInfo thermalState]", status = "absent"},
                            ["NSProcessInfo.thermalState"] = thermal, ["NSProcessInfo.lowPowerModeEnabled"] = listed["NSProcessInfo.lowPowerModeEnabled"]}
    local hot = {accessor("NSProcessInfo::thermalState", "thermalState", 300)}
    expect_equal(found, "the other getter, paired with the wrong property", #lift.accessor_conflicts(kept_thermal, listed_thermal, hot, shared), 0)
    -- The same two rows, each written at its own location, are still the pair the rule exists for: it is the
    -- location that carries two properties that pairs with neither, not the rows. So the accessor is written at
    -- the line the map here names, which is the contrast the two cases above are about.
    expect_equal(found, "the same two, one location each", #lift.accessor_conflicts(kept_low, listed_low,
                 {accessor("NSProcessInfo::isLowPowerModeEnabled", "isLowPowerModeEnabled", 222)},
                 {["NSProcessInfo.h:222:5"] = {"NSProcessInfo.lowPowerModeEnabled"}}), 1)
    expect_equal(found, "a location carrying no property", #lift.accessor_conflicts(kept_low, listed_low, low, {}), 0)

    -- The guards that decide whether the rule fires, one case each. A property that is not carried answers no
    -- question about the accessor's, and a property paired with itself is one row, not two.
    local listed_ignored = {["-[NSProcessInfo isLowPowerModeEnabled]"] = listed["-[NSProcessInfo isLowPowerModeEnabled]"],
                            ["NSProcessInfo.lowPowerModeEnabled"] = {api = "NSProcessInfo.lowPowerModeEnabled", status = "ignored"}}
    expect_equal(found, "a property that is ignored, not carried", #lift.accessor_conflicts(kept_low, listed_ignored, low, where_of), 0)
    -- A row the registry spells as the property is a member, and the accessor scan never reads it: the loop walks
    -- apis member_api() gives a *selector*, and a dotted name has a property instead. So a kept property row and
    -- the implicit accessor written from it are one API however the registry spells it, and the two spellings can
    -- never be one row - which is why the rule carries no guard for it.
    local own = {api = "NSProcessInfo.lowPowerModeEnabled", kind = "property", status = "implemented"}
    expect_equal(found, "a property row is a member", lift.absence_of(own.api, {[own.api] = own}), "member")
    expect_equal(found, "and the accessor scan does not read it", #lift.accessor_conflicts({[own.api] = true}, {[own.api] = own},
                                                                     {accessor("NSProcessInfo::lowPowerModeEnabled", "lowPowerModeEnabled")},
                                                                     {["NSProcessInfo.h:222:5"] = {own.api}}), 0)
    expect_equal(found, "while the getter of it is one the scan does read",
                 #lift.accessor_conflicts({["-[NSProcessInfo lowPowerModeEnabled]"] = true},
                                          {["-[NSProcessInfo lowPowerModeEnabled]"] = {api = "-[NSProcessInfo lowPowerModeEnabled]", status = "inert"},
                                           [own.api] = own},
                                          {accessor("NSProcessInfo::lowPowerModeEnabled", "lowPowerModeEnabled")},
                                          {["NSProcessInfo.h:222:5"] = {own.api}}), 1)

    -- What must never be silent: a member in unmatched is the lookup failing, and is refused by name. A protocol
    -- is measured, a class is measured, a function is measured; a member is not - and each of those three is a
    -- case, because a rule that fires on the wrong shape is what a case is for.
    expect_equal(found, "a member in unmatched is refused", #lift.silently_absent({"-[NSProcessInfo isLowPowerModeEnabled]"}, {}), 1)
    -- two of the five are member spellings - one a method, one a property - and the other three are not members
    -- at all, which is the whole of the rule: a protocol, a class and a function are measured, not refused
    expect_equal(found, "two of five names are members, and only those two are refused",
                 #lift.silently_absent({"-[NSNoSuchClass z]", "NSNoSuchClass.p", "INNoSuchProtocol", "_ceil", "NSNoSuchClass"},
                                    {INNoSuchProtocol = {kind = "protocol"}, NSNoSuchClass = {kind = "class"}}), 2)
    expect_equal(found, "a protocol is measured, not refused", #lift.silently_absent({"INEditMessageIntentHandling"}, {INEditMessageIntentHandling = {kind = "protocol"}}), 0)
    expect_equal(found, "a class is measured, not refused", #lift.silently_absent({"NSNoSuchClass"}, {NSNoSuchClass = {kind = "class"}}), 0)
    expect_equal(found, "and nothing at all is nothing to refuse", #lift.silently_absent({}), 0)
    -- The classifier, one shape each: a member is refused, and the three other shapes are measured. This is the
    -- one place both rules read, so a mutation of either of them - the protocol clause of 0002 put back, or the
    -- refusal narrowed - is a case here.
    expect_equal(found, "a method is a member", lift.absence_of("-[NSNoSuchClass z]", {}), "member")
    expect_equal(found, "a property is a member", lift.absence_of("NSNoSuchClass.p", {}), "member")
    expect_equal(found, "a class method is a member", lift.absence_of("+[NSNoSuchClass z]", {}), "member")
    expect_equal(found, "a protocol is not a member", lift.absence_of("INNoSuchProtocol", {INNoSuchProtocol = {kind = "protocol"}}), "protocol")
    expect_equal(found, "a class is not a member", lift.absence_of("NSNoSuchClass", {NSNoSuchClass = {kind = "class"}}), "class")
    expect_equal(found, "a function is not a member", lift.absence_of("_ceil", {}), "function or constant")
    expect_equal(found, "a function the registry gives a kind for is that kind", lift.absence_of("_ceil", {_ceil = {kind = "function"}}), "function")

    -- The set file's header counts are computed by the writer, so a re-measure moves them. A hand-written count is
    -- the one number in the file a reader cannot check against anything else, and a re-measure that does not move it
    -- is a re-measure nobody notices was wrong.
    local header = {"# What lift() leaves alone against iPhoneOS16.4.sdk: one full lift of the registry of this series",
                    "# (main deadbeef, which added a thing), none dropped: 3 lines.",
                    "# Each is a name the lift did not reach, and each was looked for in every header of the SDK",
                    "#  - class (1): a class no header declares",
                    "#  - undeclared (1): a registered member its class reaches no declaration of",
                    "#  - unmatched (1): __sincosf_stret is declared by math.h"}
    local three = {"class\tNSNoSuchClass\t", "undeclared\t-[NSNoSuchClass z]\tdeclared nowhere", "unmatched\t_ceil\tfunction or constant"}
    local written = lift.set_with_counts(header, three)
    local function says(what)
        return tostring(written:find(what, 1, true) ~= nil)
    end
    expect_equal(found, "the total is the lines' own", says("none dropped: 3 lines."), "true")
    expect_equal(found, "the header's class count is computed", says("#  - class (1):"), "true")
    expect_equal(found, "the header's undeclared count is computed", says("#  - undeclared (1):"), "true")
    expect_equal(found, "the header's unmatched count is computed", says("#  - unmatched (1):"), "true")
    expect_equal(found, "and the numbers in the header are not the ones it was given", says("none dropped: 99 lines."), "false")
    expect_equal(found, "the prose after each count is kept", says("a class no header declares"), "true")
    expect_equal(found, "the prose of the other lines is kept", says("looked for in every header of the SDK"), "true")
    expect_equal(found, "the series is kept when none is given", says("main deadbeef, which added a thing"), "true")
    expect_equal(found, "and replaced when one is", tostring(lift.set_with_counts(header, three, "main cafebabe"):find("main cafebabe", 1, true) ~= nil), "true")
    local four = lift.set_with_counts(header, {"class\tA\t", "class\tB\t", "class\tC\t", "unmatched\t_ceil\tfunction"})
    expect_equal(found, "a longer set moves the count that changed", tostring(four:find("#  - class (3):", 1, true) ~= nil), "true")
    expect_equal(found, "and leaves the one that did not", tostring(four:find("#  - undeclared (0):", 1, true) ~= nil), "true")
    -- the header first and the lines under it, in the order they were measured: the writer sorts nothing, so a
    -- set that is already sorted stays byte for byte what left_alone() wrote
    local under = 0
    for _, line in ipairs(header) do
        under = under + #line + 1
    end
    expect_equal(found, "the lines are under the header, in the order measured", written:sub(under + 1), table.concat(three, "\n") .. "\n")
    -- A registered protocol no header of the SDK declares is measured, as a class with no declaration is: a line in
    -- the set carrying its kind, so a name spelled wrong is a new line in the next re-measure's diff. A protocol the
    -- SDK declares is not in unmatched and so is not in the set at all.
    local protocols = {INEditMessageIntentHandling = {api = "INEditMessageIntentHandling", kind = "protocol", status = "implemented"},
                       INCarPlayDomainHandling = {api = "INCarPlayDomainHandling", kind = "protocol", status = "implemented"}}
    expect_equal(found, "a registered protocol the SDK declares nowhere", named(lift.left_alone({"INEditMessageIntentHandling"}, {}, protocols)),
                 "unmatched\tINEditMessageIntentHandling\tprotocol")
    expect_equal(found, "a protocol the SDK declares", named(lift.left_alone({}, {}, protocols)), "")
    local both = {INEditMessageIntentHandling = protocols.INEditMessageIntentHandling, NSNoSuchClass = {api = "NSNoSuchClass", kind = "class", status = "implemented"}}
    expect_equal(found, "a class beside it keeps its own kind", named(lift.left_alone({"INEditMessageIntentHandling", "NSNoSuchClass"}, {}, both)),
                 "class\tNSNoSuchClass\t; unmatched\tINEditMessageIntentHandling\tprotocol")

    -- an implemented class no header declares stays unmatched and is named apart as a class; the rest keep their kind
    local classes, rest, kinds = lift.split_unmatched({"CharonNoSuchClassAnywhere", "_ceil", "CharonProto"}, {CharonNoSuchClassAnywhere = {kind = "class"},
                                                      CharonProto = {kind = "protocol"}, _ceil = {}})
    expect_equal(found, "the classes among what stays unmatched", table.concat(classes, ","), "CharonNoSuchClassAnywhere")
    expect_equal(found, "the rest among what stays unmatched", table.concat(rest, ","), "_ceil,CharonProto")
    expect_equal(found, "the kinds of the rest", kinds._ceil .. "|" .. kinds.CharonProto .. "|" .. tostring(kinds.CharonNoSuchClassAnywhere), "function or constant|protocol|nil")
    -- and a lift that found only that fails against a measured set without it, by its name
    expect_equal(found, "a class no header declares, not measured", named(lift.differences(lift.left_alone({"CharonNoSuchClassAnywhere"}, {},
                 {CharonNoSuchClassAnywhere = {kind = "class"}}), "")), "new: class CharonNoSuchClassAnywhere ")

    -- names are asked for in groups of the sorted list that share six characters, at most forty to a group, the prefix all of them share
    local function grouped(names)
        local text = {}
        for _, group in ipairs(lift.name_groups(names)) do
            table.insert(text, group.prefix .. "=" .. table.concat(group.names, ","))
        end
        return table.concat(text, " ")
    end
    expect_equal(found, "names grouped by their shared prefix", grouped({"GCInputButtonB", "GCInputButtonA", "CGPath", "CGContextFillRect", "CGContext", "Ab"}),
                 "Ab=Ab CGContext=CGContext,CGContextFillRect CGPath=CGPath GCInputButton=GCInputButtonA,GCInputButtonB")
    expect_equal(found, "five shared characters are not enough", grouped({"UIViewA", "UIViewB", "UIVieX"}), "UIVieX=UIVieX UIView=UIViewA,UIViewB")
    local many = {}
    for index = 1, 41 do
        table.insert(many, string.format("NSAllocate%02d", index))
    end
    local sizes = {}
    for _, group in ipairs(lift.name_groups(many)) do
        table.insert(sizes, group.prefix .. "=" .. #group.names)
    end
    expect_equal(found, "at most forty names to a group", table.concat(sizes, " "), "NSAllocate=40 NSAllocate41=1")
    return found
end
