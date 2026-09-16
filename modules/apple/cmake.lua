import("lib.detect.find_tool")

local processors = {armv7 = "arm", armv7s = "arm", arm64 = "aarch64"}

local function quoted(values)
    return table.concat(values, " "):gsub("\\", "\\\\"):gsub("\"", "\\\"")
end

function toolchain(package)
    local found = assert(package:toolchains(), package:name() .. " is built for apple-ios without the apple-ios toolchain")[1]
    found:load()
    return found
end

function toolchain_file(package, opt)
    opt = opt or {}
    local chosen = toolchain(package)
    local sdk = chosen:config("sdkdir")
    local linked_minimum = chosen:config("deployment")
    local compiled_minimum = opt.compile_deployment or linked_minimum
    local compiled = table.join({"-target", package:arch() .. "-apple-ios", "-miphoneos-version-min=" .. compiled_minimum, "-isysroot", sdk}, opt.cflags or {})
    local common = {"-target", package:arch() .. "-apple-ios", "-miphoneos-version-min=" .. linked_minimum, "-isysroot", sdk}
    local linker = {}
    for _, flag in ipairs(table.wrap(chosen:get("shflags"))) do
        if flag:startswith("-fuse-ld=") then
            table.insert(linker, flag)
        end
    end
    local linked = table.join(common, linker, opt.ldflags or {})
    local roots = {sdk}
    for _, dep in ipairs(package:orderdeps()) do
        if not dep:is_binary() and not dep:is_toolchain() then
            table.insert(roots, dep:installdir())
        end
    end
    local lines = {
        "set(CMAKE_SYSTEM_NAME " .. (opt.system or "iOS") .. ")",
        "set(CMAKE_SYSTEM_PROCESSOR " .. assert(processors[package:arch()], "apple-ios builds armv7, armv7s and arm64") .. ")",
        "set(CMAKE_OSX_SYSROOT \"" .. sdk .. "\" CACHE PATH \"\" FORCE)",
        "set(CMAKE_OSX_ARCHITECTURES " .. package:arch() .. " CACHE STRING \"\" FORCE)",
        "set(CMAKE_C_COMPILER \"" .. os.iorunv("xcrun", {"-f", "clang"}):trim() .. "\")",
        "set(CMAKE_CXX_COMPILER \"" .. os.iorunv("xcrun", {"-f", "clang++"}):trim() .. "\")"
    }
    if (opt.system or "iOS") == "iOS" then
        table.insert(lines, "set(CMAKE_OSX_DEPLOYMENT_TARGET " .. compiled_minimum .. " CACHE STRING \"\" FORCE)")
    else
        table.insert(lines, "set(CMAKE_OSX_DEPLOYMENT_TARGET \"\" CACHE STRING \"\" FORCE)")
    end
    for _, language in ipairs({"C", "CXX", "OBJC", "OBJCXX", "ASM"}) do
        local flags = table.join(compiled, language:find("CXX") and opt.cxxflags or {})
        table.insert(lines, string.format("set(CMAKE_%s_FLAGS_INIT \"%s\")", language, quoted(flags)))
    end
    for _, kind in ipairs({"EXE", "SHARED", "MODULE"}) do
        table.insert(lines, string.format("set(CMAKE_%s_LINKER_FLAGS_INIT \"%s\")", kind, quoted(table.join(linked, kind ~= "EXE" and opt.shflags or {}))))
    end
    table.join2(lines, {
        "set(CMAKE_FIND_ROOT_PATH \"" .. table.concat(roots, "\" \"") .. "\")",
        "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)",
        "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)",
        "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)",
        "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)"
    })
    local file = path.absolute(path.join(opt.builddir or "build_charon", "apple-ios.toolchain.cmake"))
    io.writefile(file, table.concat(lines, "\n") .. "\n")
    return file
end

function install(package, configs, opt)
    opt = opt or {}
    local cmake = assert(find_tool("cmake"), "cmake is needed to build " .. package:name())
    local ninja = assert(find_tool("ninja"), "ninja is needed to build " .. package:name())
    local builddir = path.absolute(opt.builddir or "build_charon")
    os.mkdir(builddir)
    local argv = {"-G", "Ninja", "-S", path.absolute(opt.sourcedir or "."), "-B", builddir,
                  "-DCMAKE_MAKE_PROGRAM=" .. ninja.program,
                  "-DCMAKE_TOOLCHAIN_FILE=" .. toolchain_file(package, table.join(opt, {builddir = builddir})),
                  "-DCMAKE_BUILD_TYPE=" .. (package:is_debug() and "Debug" or "Release"),
                  "-DCMAKE_INSTALL_PREFIX=" .. package:installdir(),
                  "-DCMAKE_INSTALL_LIBDIR=lib",
                  "-DBUILD_SHARED_LIBS=" .. (package:config("shared") and "ON" or "OFF"),
                  "-DCMAKE_MACOSX_BUNDLE=OFF"}
    table.join2(argv, configs or {})
    local envs = {SOURCE_DATE_EPOCH = opt.source_date_epoch or "0", IPHONEOS_DEPLOYMENT_TARGET = toolchain(package):config("deployment")}
    os.vrunv(cmake.program, argv, {envs = envs})
    os.vrunv(cmake.program, table.join({"--build", builddir, "--parallel", tostring(os.cpuinfo("ncpu"))}, opt.targets and table.join({"--target"}, opt.targets) or {}), {envs = envs})
    if opt.install ~= false then
        os.vrunv(cmake.program, {"--install", builddir}, {envs = envs})
    end
    return builddir
end
