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
    local listed = {"5.1.1", "6.0", "6.1.6", "7.0", "7.1.2", "8.0", "8.4.1", "9.0", "9.3.6", "10.0.1", "10.3.4"}
    local described = {}
    for _, range in ipairs(backports.band_ranges({"6.0", "7.0", "8.0", "9.0"}, listed)) do
        table.insert(described, range.first .. "-" .. range.last)
    end
    if table.concat(described, " ") ~= "6.0-6.1.6 7.0-7.1.2 8.0-8.4.1 9.0-10.3.4" then
        table.insert(found, "each release the backports' API arrived in opens a band running to the last catalog release before the next, and the last band to the catalog's end: " .. table.concat(described, " "))
    end
    local errors = fixtures.refusal(function () backports.band_ranges({"6.0", "11.0"}, listed) end)
    if not errors or not errors:find("iOS 11.0 or later", 1, true) then
        table.insert(found, "API arriving in a release no catalog firmware reaches must be refused: " .. tostring(errors))
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
            run("postrm", root, "upgrade")
            if not os.islink(path.join(home, "libFoundationBackports.dylib")) then
                table.insert(found, "an upgrade must keep the links, which the new postinst sets again")
            end
            run("postrm", root, "remove")
            if os.islink(path.join(home, "libFoundationBackports.dylib")) then
                table.insert(found, "removing the package must take the links it set")
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
