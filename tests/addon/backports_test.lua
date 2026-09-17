import("fixtures")

local function object(folder, name, source)
    io.writefile(path.join(folder, name .. ".c"), source)
    fixtures.run(folder, "xcrun", {"clang", "-target", "armv7-apple-ios6.0", "-Wno-incompatible-sysroot", "-fvisibility=hidden", "-c", name .. ".c", "-o", name .. ".o"})
    return path.join(folder, name .. ".o")
end

function failures(opt)
    local backports = import("apple.backports", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local folder = fixtures.scratch()
    local seven = object(folder, "seven", "__attribute__((visibility(\"default\"))) int arrived_seven = 7;\n__attribute__((visibility(\"default\"))) int also_seven(void) { return 7; }\nstatic int helper(void) { return 0; }\n")
    local eight = object(folder, "eight", "__attribute__((visibility(\"default\"))) int arrived_eight = 8;\n")
    local methods = object(folder, "methods", "static int added(void) { return 1; }\nint (*const hidden_table[])(void) = {added};\n")
    local mixed = object(folder, "mixed", "__attribute__((visibility(\"default\"))) int arrived_seven_too = 7;\n__attribute__((visibility(\"default\"))) int arrived_eight_too = 8;\n")
    local release_six = {}
    local release_seven = {_arrived_seven = true, _also_seven = true, _arrived_seven_too = true}
    local kept, reexported = backports.band(release_six, {seven, eight, methods})
    if #kept ~= 3 or #reexported ~= 0 then
        table.insert(found, string.format("a release that has none of the symbols must keep every object, not %d with %d re-exported", #kept, #reexported))
    end
    kept, reexported = backports.band(release_seven, {seven, eight, methods})
    table.sort(reexported)
    if table.concat(kept, ",") ~= table.concat({eight, methods}, ",") or table.concat(reexported, ",") ~= "_also_seven,_arrived_seven" then
        table.insert(found, "a release that exports every symbol of an object must drop the object and re-export its symbols, not keep " .. table.concat(kept, ",") .. " and re-export " .. table.concat(reexported, ","))
    end
    local errors = fixtures.refusal(function () backports.band(release_seven, {mixed}) end)
    if not errors or not errors:find("_arrived_seven_too", 1, true) or not errors:find("_arrived_eight_too", 1, true) then
        table.insert(found, "an object holding what a release exports beside what it does not must be refused naming both: " .. tostring(errors))
    end
    local uikit = "/System/Library/Frameworks/UIKit.framework/UIKit"
    local uifoundation = "/System/Library/PrivateFrameworks/UIFoundation.framework/UIFoundation"
    local release = {libraries = {[uikit] = {exports = {["_OBJC_CLASS_$_UIAlertController"] = true, ["_OBJC_METACLASS_$_UIAlertController"] = true, _UIApplicationDidFinishLaunchingNotification = true},
                                             reexports = {uifoundation}},
                                  [uifoundation] = {exports = {_NSFontAttributeName = true}, reexports = {}}}}
    local written = backports.stubs("armv7", {name = "UIKitBackports", frameworks = {"UIKit", "Foundation"}},
                                    {"_OBJC_CLASS_$_UIAlertController", "_NSFontAttributeName"}, {release, release}, folder)
    local stub = #written == 1 and io.readfile(written[1])
    if not stub or path.filename(written[1]) ~= "UIKit.tbd" then
        table.insert(found, "a symbol a framework re-exports must be taken from the framework the library links, not from the private library behind it: " .. table.concat(written, ","))
    elseif not stub:find("_NSFontAttributeName", 1, true) or not stub:find("UIAlertController", 1, true) or not stub:find("_UIApplicationDidFinishLaunchingNotification", 1, true) then
        table.insert(found, "a stub stands in for the whole library of its release, since it takes the place of the SDK's: " .. stub)
    end

    local listed = {"5.1.1", "6.0", "6.1.6", "7.0", "7.1.2", "8.0", "8.4.1", "9.0", "9.3.6", "10.0.1", "10.3.4"}
    local described = {}
    for _, range in ipairs(backports.band_ranges({"6.0", "7.0", "8.0", "9.0"}, listed)) do
        table.insert(described, range.first .. "-" .. range.last)
    end
    if table.concat(described, " ") ~= "6.0-6.1.6 7.0-7.1.2 8.0-8.4.1 9.0-10.3.4" then
        table.insert(found, "each release the backports' API arrived in opens a band running to the last catalog release before the next, and the last band to the catalog's end: " .. table.concat(described, " "))
    end
    described = {}
    for _, range in ipairs(backports.band_ranges({"6.0", "9.0", "11.0"}, listed)) do
        table.insert(described, range.first .. "-" .. range.last)
    end
    if table.concat(described, " ") ~= "6.0-8.4.1 9.0-10.3.4" then
        table.insert(found, "API of a release no firmware of the architecture reaches opens no band and stays in every one: " .. table.concat(described, " "))
    end
    local errors = fixtures.refusal(function () backports.band_ranges({"11.0"}, listed) end)
    if not errors or not errors:find("iOS 11.0 or later", 1, true) then
        table.insert(found, "a minimum release no catalog firmware reaches must be refused: " .. tostring(errors))
    end
    local dump = table.concat({
        "Dumping NSURLQueryItemReader:", "|-AvailabilityAttr 0x1 <col:1> ios 11.0 0 0 \"\" \"\" 0",
        "Dumping NSURLQueryItem:", "|-AvailabilityAttr 0x2 <col:1> macos 10.10 0 0 \"\" \"\" 0", "|-AvailabilityAttr 0x3 <col:1> ios 8.0 0 0 \"\" \"\" 0",
        "| `-ObjCMethodDecl 0x5 <col:1> - dataTaskWithURL:", "|   `-AvailabilityAttr 0x6 <col:1> ios 15.0 0 0 \"\" \"\" 0",
        "Dumping NSURLQueryItem:", "`-ObjCImplementation 0x4",
        "Dumping NSURLQueryItem:", "|-AvailabilityAttr 0x7 <col:1> ios 13.0 0 0 \"\" \"\" 0"}, "\n")
    if backports.introduced_version(dump, "NSURLQueryItem") ~= "8.0" or backports.introduced_version(dump, "NSURLComponents") then
        table.insert(found, "the release a declaration arrived in is the earliest iOS availability of its own declarations, not of their members or of another declaration the filter matched")
    end

    local dump = table.concat({
        "Dumping NSURLQueryItemReader:", "|-AvailabilityAttr 0x1 <col:1> ios 11.0 0 0 \"\" \"\" 0",
        "Dumping NSURLQueryItem:", "|-AvailabilityAttr 0x2 <col:1> macos 10.10 0 0 \"\" \"\" 0", "|-AvailabilityAttr 0x3 <col:1> ios 8.0 0 0 \"\" \"\" 0",
        "| `-ObjCMethodDecl 0x5 <col:1> - dataTaskWithURL:", "|   `-AvailabilityAttr 0x6 <col:1> ios 15.0 0 0 \"\" \"\" 0",
        "Dumping NSURLQueryItem:", "`-ObjCImplementation 0x4",
        "Dumping NSURLQueryItem:", "|-AvailabilityAttr 0x7 <col:1> ios 13.0 0 0 \"\" \"\" 0"}, "\n")
    if backports.introduced_version(dump, "NSURLQueryItem") ~= "8.0" or backports.introduced_version(dump, "NSURLComponents") then
        table.insert(found, "the release a declaration arrived in is the earliest iOS availability of its own declarations, not of their members or of another declaration the filter matched")
    end
    local named = backports.availability_names({"_OBJC_CLASS_$_NSDimension", "_OBJC_METACLASS_$_NSDimension",
                                                "_OBJC_IVAR_$_NSDimension._converter", "_NSCalendarIdentifierGregorian"})
    if not named["NSDimension"] or not named["NSCalendarIdentifierGregorian"] or named["OBJC_IVAR_$_NSDimension._converter"] then
        table.insert(found, "an ivar has no release of its own and is read as the class that holds it: " .. table.concat(table.orderkeys(named), " "))
    end

    local registry = path.join(folder, "registry")
    os.mkdir(registry)
    io.writefile(path.join(registry, "UIKit.json"), [[
        {"framework": "UIKit", "entries": [
            {"api": "UIStackView", "kind": "class", "introduced": "9.0", "status": "implemented", "facts": "facts/UIKit/UIStackView.md"},
            {"api": "-[UIView tintColorDidChange]", "kind": "method", "introduced": "7.0", "status": "implemented"},
            {"api": "UIFontTextStyleBody", "kind": "constant", "introduced": "7.0", "status": "implemented"},
            {"api": "UIBlurEffect", "kind": "class", "introduced": "8.0", "status": "absent", "reason": "the render server draws it", "effect": "the class is not there"}
        ]}
    ]])
    local carried = {classes = {UIStackView = true}, members = {["-[UIView tintColorDidChange]"] = true}, symbols = {UIFontTextStyleBody = true}}
    local undocumented = backports.check_registry(folder, carried)
    if undocumented ~= 2 then
        table.insert(found, "an entry that names no file of facts must be counted, not refused: " .. tostring(undocumented))
    end
    carried.members["-[UIView tintAdjustmentMode]"] = true
    errors = fixtures.refusal(function () backports.check_registry(folder, carried) end)
    if not errors or not errors:find("-[UIView tintAdjustmentMode]", 1, true) then
        table.insert(found, "a method the backports add without an entry in the registry must be refused naming it: " .. tostring(errors))
    end
    carried.members["-[UIView tintAdjustmentMode]"] = nil
    carried.classes.UIStackView = nil
    errors = fixtures.refusal(function () backports.check_registry(folder, carried) end)
    if not errors or not errors:find("UIStackView", 1, true) then
        table.insert(found, "an entry that says implemented while nothing of that name is built must be refused naming it: " .. tostring(errors))
    end
    carried.classes.UIStackView = true
    os.mkdir(path.join(registry, "Foundation"))
    io.writefile(path.join(registry, "Foundation", "ios11.json"), [[
        [
            {"api": "NSJSONWritingSortedKeys", "kind": "constant", "introduced": "11.0", "status": "ignored",
             "effect": "the release writes the keys in the order of the dictionary", "facts": "facts/Foundation/NSJSONSerialization.md"},
            {"api": "NSLocalizedFailureErrorKey", "kind": "constant", "introduced": "11.0", "status": "ignored",
             "effect": "the release leaves the failure out of -localizedDescription"}
        ]
    ]])
    errors = fixtures.refusal(function () backports.check_registry(folder, carried) end)
    if not errors or not errors:find("NSLocalizedFailureErrorKey is ignored without a file of facts", 1, true)
       or errors:find("NSJSONWritingSortedKeys", 1, true) then
        table.insert(found, "an API the release's own implementation answers differently is ignored, and must name the file of facts that says how: " .. tostring(errors))
    end
    io.writefile(path.join(registry, "Foundation", "ios11.json"), [[
        [
            {"api": "NSJSONWritingSortedKeys", "kind": "constant", "introduced": "11.0", "status": "ignored",
             "effect": "the release writes the keys in the order of the dictionary", "facts": "facts/Foundation/NSJSONSerialization.md"}
        ]
    ]])
    os.mkdir(path.join(registry, "UIKit"))
    io.writefile(path.join(registry, "UIKit", "ios10.json"), [[
        [{"api": "UIStackView", "kind": "class", "introduced": "9.0", "status": "implemented", "facts": "facts/UIKit/UIStackView.md"}]
    ]])
    errors = fixtures.refusal(function () backports.check_registry(folder, carried) end)
    if not errors or not errors:find("UIKit.json and UIKit/ios10.json", 1, true) then
        table.insert(found, "one API named by two files of the registry must be refused naming both: " .. tostring(errors))
    end
    os.rm(path.join(registry, "UIKit", "ios10.json"))
    io.writefile(path.join(registry, "UIKit", "floor.json"), [[
        [{"api": "NSLayoutConstraint", "kind": "class", "introduced": "6.0", "minimum": "6.0", "status": "absent",
          "reason": "auto layout arrived in 6.0", "effect": "below 6.0 the class is not there", "source": "the armv7 cache of iOS 5.1.1"}]
    ]])
    undocumented = backports.check_registry(folder, carried, nil, "6.0")
    if undocumented ~= 2 then
        table.insert(found, "a record of where an API begins needs no file of facts, only what the backports carry does: " .. tostring(undocumented))
    end
    os.rm(path.join(registry, "UIKit", "floor.json"))
    os.rm(path.join(registry, "Foundation", "ios11.json"))

    io.writefile(path.join(registry, "UIKit", "advice.json"), [[
        [
            {"api": "-[UIView setTintColor:]", "kind": "method", "introduced": "7.0", "status": "inert",
             "reason": "no control of the release reads it", "effect": "the colour is remembered and nothing is drawn with it"},
            {"api": "UIBlurEffect", "kind": "class", "introduced": "8.0", "status": "absent",
             "reason": "the render server draws it", "effect": "the class is not there"},
            {"api": "NSJSONWritingSortedKeys", "kind": "constant", "introduced": "11.0", "status": "ignored",
             "effect": "the keys come out in the dictionary's own order", "facts": "facts/Foundation/NSJSONSerialization.md"}
        ]
    ]])
    local advised = backports.advice(folder, {["setTintColor:"] = true, UIBlurEffect = true, NSJSONWritingSortedKeys = true, ["description"] = true})
    local order = {}
    for _, entry in ipairs(advised) do
        table.insert(order, entry.api .. "=" .. entry.status)
    end
    if table.concat(order, " ") ~= "NSJSONWritingSortedKeys=ignored UIBlurEffect=absent -[UIView setTintColor:]=inert" then
        table.insert(found, "what a port calls is reported quietest first, since a missing class crashes where a different answer never shows: " .. table.concat(order, " "))
    end
    os.rm(path.join(registry, "UIKit", "advice.json"))

    local scripts = path.join(folder, "scripts")
    backports.write_scripts(scripts)
    local function device(version)
        local root = path.join(folder, "device-" .. version)
        os.tryrm(root)
        local home = path.join(root, "usr", "lib", "charon", backports.package_name())
        for _, band in ipairs({"6.0", "9.3.5"}) do
            os.mkdir(path.join(home, "bands", band))
            io.writefile(path.join(home, "bands", band, "libFoundationBackports.dylib"), band)
        end
        io.writefile(path.join(home, "bands", "ranges"), "6.0 6.1.3\n9.3.5 10.3.3\n")
        os.mkdir(path.join(root, "System", "Library", "CoreServices"))
        if version ~= "" then
            io.writefile(path.join(root, "System", "Library", "CoreServices", "SystemVersion.plist"),
                         "<plist version=\"1.0\">\n<dict>\n\t<key>ProductBuildVersion</key>\n\t<string>X</string>\n\t<key>ProductVersion</key>\n\t<string>" .. version .. "</string>\n</dict>\n</plist>\n")
        end
        return root, home
    end
    local function run(script, root, argument)
        local output = path.join(folder, "script.out")
        local status = os.execv("sh", {"-c", string.format("DPKG_ROOT='%s' sh '%s' %s > '%s' 2>&1", root, path.join(scripts, script), argument, output)}, {try = true})
        return status, io.readfile(output)
    end
    for _, case in ipairs({{"6.0", "6.0"}, {"6.1.2", "6.0"}, {"10.2", "9.3.5"}, {"10.3.3", "9.3.5"}}) do
        local root, home = device(case[1])
        local status, text = run("postinst", root, "configure")
        local linked = os.islink(path.join(home, "libFoundationBackports.dylib")) and os.readlink(path.join(home, "libFoundationBackports.dylib"))
        if status ~= 0 or linked ~= "bands/" .. case[2] .. "/libFoundationBackports.dylib" then
            table.insert(found, string.format("iOS %s must get the libraries of the %s band: status %s, link %s, %s", case[1], case[2], tostring(status), tostring(linked), text))
        end
        if case[1] == "6.0" then
            run("prerm", root, "upgrade")
            if not os.islink(path.join(home, "libFoundationBackports.dylib")) then
                table.insert(found, "an upgrade must keep the links, which the new postinst sets again")
            end
            run("prerm", root, "remove")
            if os.islink(path.join(home, "libFoundationBackports.dylib")) or #os.filedirs(path.join(home, "*.dylib")) > 0 then
                table.insert(found, "removing the package must take the links it set before dpkg removes its files, so its folders empty")
            end
        end
    end
    for _, case in ipairs({{"6.1.4", "holds no libraries built and checked for iOS 6.1.4; it holds them for iOS 6.0 to 6.1.3, 9.3.5 to 10.3.3"},
                           {"8.4.1", "holds no libraries built and checked for iOS 8.4.1"},
                           {"", "cannot read ProductVersion"}}) do
        local root, home = device(case[1])
        local status, text = run("postinst", root, "configure")
        if status == 0 or not text:find(case[2], 1, true) or os.islink(path.join(home, "libFoundationBackports.dylib")) then
            table.insert(found, string.format("iOS %s has no band and must be refused naming it, not given the nearest: status %s, %s", case[1], tostring(status), text))
        end
    end
    os.tryrm(folder)
    return found
end
