import("core.base.json")
import("core.project.project")
import("macho")

function read_plist(file)
    return json.decode(os.iorunv("plutil", {"-convert", "json", "-o", "-", file}))
end

function write_plist(file, content)
    local staged = os.tmpfile() .. ".json"
    json.savefile(staged, content)
    os.vrunv("plutil", {"-convert", "xml1", "-o", file, staged})
    os.rm(staged)
end

local function overrides(target)
    local found = {}
    for _, entry in ipairs(table.wrap(target:values("app.plist"))) do
        local key, value = entry:match("^([^=]+)=(.*)$")
        if not key then
            raise("target(%s): app.plist takes KEY=VALUE, not %s", target:name(), entry)
        end
        found[key] = value
    end
    return found
end

function info(target, deployment)
    local declared = target:values("app.plist-file")
    local content = {}
    if declared then
        local file = path.join(target:scriptdir(), declared)
        if not os.isfile(file) then
            raise("target(%s) names app.plist-file %s, and there is no such file", target:name(), declared)
        end
        content = read_plist(file)
    end
    for key, value in pairs(overrides(target)) do
        content[key] = value
    end
    local name = target:basename()
    if content.CFBundleExecutable ~= nil and content.CFBundleExecutable ~= name then
        raise("%s gives CFBundleExecutable %s, and the application built is %s; the bundle would not start", declared or "app.plist", content.CFBundleExecutable, name)
    end
    local version = project.version()
    local derived = {
        CFBundleName = name,
        CFBundleDisplayName = name,
        CFBundleExecutable = name,
        CFBundleVersion = version,
        CFBundleShortVersionString = version,
        MinimumOSVersion = deployment
    }
    for key, value in pairs(derived) do
        if content[key] == nil then
            content[key] = value
        end
    end
    local scheme = target:values("app.url-scheme")
    if scheme then
        content.CFBundleURLTypes = {{CFBundleURLName = content.CFBundleIdentifier or name, CFBundleURLSchemes = {scheme}}}
    end
    return content
end

local function package_libraries(target, package, name)
    local libraries = {}
    for _, file in ipairs(os.files(path.join(package:installdir(), "lib", "*.dylib"))) do
        if not os.islink(file) then
            table.insert(libraries, file)
        end
    end
    if #libraries == 0 then
        raise("target(%s) bundles the libraries of %s, and it installs no shared library", target:name(), name)
    end
    table.sort(libraries)
    local carried = {}
    for _, file in ipairs(libraries) do
        local image = macho.images(macho.read(file))[1]
        table.insert(carried, {source = file, name = path.filename(image.identity or file)})
    end
    return carried
end

function carried_libraries(target)
    local carried = {}
    for _, name in ipairs(table.wrap(target:values("app.frameworks"))) do
        local built = target:dep(name)
        if built then
            if not built:is_shared() then
                raise("target(%s) bundles target(%s), which is not a shared library", target:name(), name)
            end
            table.insert(carried, {source = built:targetfile(), name = built:filename()})
        else
            local package = target:pkg(name)
            if not package then
                raise("target(%s) bundles %s, which is neither a target it add_deps() nor a package it add_packages()", target:name(), name)
            end
            table.join2(carried, package_libraries(target, package, name))
        end
    end
    return carried
end

local function stem(reference)
    return path.filename(reference):match("^[^.]+")
end

function retarget(binaries, identities)
    local names = {}
    for binary, identity in pairs(identities) do
        local image = macho.images(macho.read(binary))[1]
        if image.identity then
            names[path.filename(image.identity)] = identity
        end
        names[path.filename(identity)] = identity
    end
    for binary, identity in pairs(identities) do
        os.vrunv("xcrun", {"install_name_tool", "-id", identity, binary})
    end
    for _, binary in ipairs(binaries) do
        for _, reference in ipairs(macho.images(macho.read(binary))[1].libraries) do
            local wanted = names[path.filename(reference)]
            if wanted and wanted ~= reference then
                os.vrunv("xcrun", {"install_name_tool", "-change", reference, wanted, binary})
            end
        end
    end
    local carried = {}
    for name in pairs(names) do
        carried[stem(name)] = true
    end
    local problems = {}
    for _, binary in ipairs(binaries) do
        for _, image in ipairs(macho.images(macho.read(binary))) do
            for _, reference in ipairs(image.libraries) do
                if reference:startswith("@rpath/") then
                    table.insert(problems, string.format("%s still depends on %s", path.filename(binary), reference))
                elseif carried[stem(reference)] and not reference:startswith("@executable_path/") then
                    table.insert(problems, string.format("%s loads %s from outside its own bundle while the bundle carries that library; it would run against whatever the system has there, and two copies of one runtime in a process do not agree", path.filename(binary), reference))
                end
            end
        end
    end
    if #problems > 0 then
        raise(table.concat(table.unique(problems), "; "))
    end
end

function copy_resources(target, bundle)
    for _, entry in ipairs(table.wrap(target:values("app.resources"))) do
        local source = path.join(target:scriptdir(), entry)
        if os.isdir(source) then
            for _, child in ipairs(os.filedirs(path.join(source, "*"))) do
                os.vcp(child, bundle .. "/")
            end
        elseif os.isfile(source) then
            os.vcp(source, bundle .. "/")
        else
            raise("target(%s) names resource %s, and there is no such file or folder", target:name(), entry)
        end
    end
end
