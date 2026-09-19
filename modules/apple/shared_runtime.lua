import("bundle")
import("signing")
import("dyld")

local ADDON = path.join(os.scriptdir(), "..", "..", "addons", "c", "charon", "xmake.lua")

-- A runtime that programs share instead of carrying: its libraries live in /usr/lib/charon/<package> under absolute
-- install names, and a package of its own holds them. The libraries are built without library evolution, so the package
-- and its folder are named after the build (see charon@swift-runtime), and a program depends on exactly that one.

-- The packages of the shared runtime: the C++ runtime, the Swift libraries, and the ones that pull UIKit in. Each is named
-- after the build it holds, and each names the ones it needs by exact version.
function package_name(kind, buildhash)
    return "org.charon." .. kind .. "-" .. buildhash:sub(1, 8)
end

-- The version of such a package: the Charon release the recipe belongs to, and the build.
function package_version(buildhash)
    local released
    for version in io.readfile(ADDON):gmatch('add_versions%("v(%d[%d%.]*)"') do
        if not released or dyld.compare_versions(version, released) > 0 then
            released = version
        end
    end
    return assert(released, "the addon recipe names no Charon release") .. "+" .. buildhash:sub(1, 8)
end

function folder_of(name)
    return "/usr/lib/charon/" .. name
end

-- Gives the libraries their absolute names and writes the package.
--   opt.name, opt.version, opt.title, opt.description: the package; opt.depends: the packages it needs, as Debian writes them
--   opt.libraries: the libraries the package holds; opt.extra: {source, leaf} of the ones that come from elsewhere (libc++)
--   opt.root: where the package's tree is built, and stays, since a program links against the libraries in it
--   opt.workdir: a scratch folder; opt.outputdir: where the package is written
--   opt.ldid, opt.strip: the signer and the strip arguments
function write(opt)
    local debian = import("debian", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
    local folder = folder_of(opt.name)
    local root = opt.root
    os.tryrm(root)
    os.tryrm(opt.workdir)
    os.mkdir(opt.workdir)
    local destination = path.join(root, folder)
    os.mkdir(destination)
    local identities, binaries = {}, {}
    local function place(source, leaf)
        local target = path.join(destination, leaf)
        os.vcp(source, target)
        identities[target] = folder .. "/" .. leaf
        table.insert(binaries, target)
    end
    for _, library in ipairs(opt.libraries) do
        place(library, path.filename(library))
    end
    for _, library in ipairs(opt.extra or {}) do
        place(library.source, library.leaf)
    end
    -- Every reference the libraries make to one another is by absolute name afterwards, and retarget refuses a library
    -- that still says @rpath or loads one of these from anywhere else.
    bundle.retarget(binaries, identities, {home = folder .. "/"})
    for _, library in ipairs(binaries) do
        os.vrunv("xcrun", table.join({"strip"}, opt.strip, {library}))
    end
    for _, library in ipairs(binaries) do
        signing.sign(opt.ldid, library)
    end
    local control = path.join(opt.workdir, "control")
    io.writefile(control, table.concat({
        "Package: " .. opt.name,
        "Name: " .. opt.title,
        "Architecture: iphoneos-arm",
        "Section: System",
        "Description: " .. opt.description .. " in " .. folder .. "; a runtime built without library evolution cannot be replaced by another build"
    }, "\n") .. "\n")
    local deb = debian.write({control = control, version = opt.version, root = root, depends = opt.depends, outputdir = opt.outputdir})
    return deb, destination
end
