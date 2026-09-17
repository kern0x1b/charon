import("fixtures")

local function fake_target(folder, values, installdir)
    local package = {installdir = function () return installdir end}
    return {
        name = function () return "tweak" end,
        scriptdir = function () return folder end,
        values = function (_, key) return values[key] end,
        dep = function () return nil end,
        pkg = function (_, name) return name == "runtime" and package or nil end
    }
end

local function references(folder, binary)
    local listed = {}
    for line in fixtures.run(folder, "xcrun", {"otool", "-L", binary}):gmatch("\n%s+(%S+)") do
        table.insert(listed, line)
    end
    return table.concat(listed, " ")
end

function failures(opt)
    local platform = import("apple.platform", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local folder = fixtures.scratch()
    io.writefile(path.join(folder, "libSystem.tbd"), fixtures.system_stub())
    local runtime = path.join(folder, "runtime")
    os.mkdir(path.join(runtime, "lib"))
    io.writefile(path.join(folder, "abi.c"), "int abi(void) { return 1; }\n")
    io.writefile(path.join(folder, "cxx.c"), "extern int abi(void);\nint cxx(void) { return abi(); }\n")
    io.writefile(path.join(folder, "tweak.c"), "extern int abi(void);\nint tweak(void) { return abi(); }\n")
    fixtures.link(folder, opt.ld64, path.join(runtime, "lib", "libabi.1.dylib"), "armv7-apple-ios6.0", "abi.c",
                  {"-dynamiclib", "-install_name", "@rpath/libabi.1.dylib"})
    fixtures.link(folder, opt.ld64, path.join(runtime, "lib", "libcxx.1.dylib"), "armv7-apple-ios6.0", "cxx.c",
                  {"-dynamiclib", "-install_name", "@rpath/libcxx.1.dylib", "-L" .. path.join(runtime, "lib"), "-labi.1"})
    local built = fixtures.link(folder, opt.ld64, "tweak.dylib", "armv7-apple-ios6.0", "tweak.c",
                                {"-dynamiclib", "-install_name", "/Library/MobileSubstrate/DynamicLibraries/tweak.dylib",
                                 "-L" .. path.join(runtime, "lib"), "-labi.1"})
    io.writefile(path.join(folder, "control"), "Package: org.example.carried\nArchitecture: iphoneos-arm\n")

    local root = path.join(folder, "root")
    local binary = path.join(root, "Library", "MobileSubstrate", "DynamicLibraries", "tweak.dylib")
    os.mkdir(path.directory(binary))
    os.cp(built, binary)
    local target = fake_target(folder, {["charon.libraries"] = "runtime", ["charon.control"] = "control"}, runtime)
    local placed = platform.place_carried(target, root, binary)
    local carried = path.join(root, "usr", "lib", "charon", "org.example.carried")
    if #placed ~= 2 or not os.isfile(path.join(carried, "libabi.1.dylib")) then
        table.insert(found, "a tweak carries the library it loads into /usr/lib/charon/<Package>, got " .. table.concat(placed, " "))
    end
    if os.isfile(path.join(carried, "libcxx.1.dylib")) then
        table.insert(found, "a library of the package that no placed image loads must not be carried")
    end
    local listed = references(folder, binary)
    if not listed:find("/usr/lib/charon/org.example.carried/libabi.1.dylib", 1, true) or listed:find("@rpath", 1, true) then
        table.insert(found, "the tweak must load its runtime from its package's folder: " .. listed)
    end
    local identity = references(folder, path.join(carried, "libabi.1.dylib"))
    if not identity:startswith("/usr/lib/charon/org.example.carried/libabi.1.dylib") then
        table.insert(found, "the carried library must be identified by its installed path: " .. identity)
    end

    local unnamed = fake_target(folder, {["charon.libraries"] = "runtime"}, runtime)
    local errors = fixtures.refusal(function () platform.place_carried(unnamed, path.join(folder, "unnamed"), built) end) or ""
    if not errors:find("charon.control", 1, true) then
        table.insert(found, "a tweak that carries a library without naming its package must be refused: " .. errors)
    end

    io.writefile(path.join(folder, "nameless"), "Name: Carried\nArchitecture: iphoneos-arm\n")
    local nameless = fake_target(folder, {["charon.libraries"] = "runtime", ["charon.control"] = "nameless"}, runtime)
    errors = fixtures.refusal(function () platform.place_carried(nameless, path.join(folder, "nameless-root"), built) end) or ""
    if not errors:find("no Package field", 1, true) then
        table.insert(found, "a control file without Package cannot name the folder, and must be refused: " .. errors)
    end
    os.tryrm(folder)
    return found
end
