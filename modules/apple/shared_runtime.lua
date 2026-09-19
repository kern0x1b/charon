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

-- Gives the libraries of one or more packages their absolute names and writes the packages.
--   opt.packages: each {name, version, title, description, depends, libraries, extra}: the package, the packages it needs as
--     Debian writes them, the libraries it holds, and {source, leaf} for the ones that come from elsewhere (libc++)
--   opt.root: where the packages' trees are built, and stay, since a program links against the libraries in them
--   opt.workdir: a scratch folder; opt.outputdir: where the packages are written
--   opt.ldid, opt.strip: the signer and the strip arguments
-- Answers the packages' debs by name.
function write(opt)
    local debian = import("debian", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
    os.tryrm(opt.root)
    os.tryrm(opt.workdir)
    os.mkdir(opt.workdir)
    local held = {}
    for _, described in ipairs(opt.packages) do
        local folder = folder_of(described.name)
        local destination = path.join(opt.root, folder)
        os.mkdir(destination)
        local entry = {described = described, folder = folder, destination = destination, identities = {}, binaries = {}, leaves = {}}
        local function place(source, leaf)
            local target = path.join(destination, leaf)
            os.vcp(source, target)
            entry.identities[target] = folder .. "/" .. leaf
            entry.leaves[leaf] = folder .. "/" .. leaf
            table.insert(entry.binaries, target)
        end
        for _, library in ipairs(described.libraries) do
            place(library, path.filename(library))
        end
        for _, library in ipairs(described.extra or {}) do
            place(library.source, library.leaf)
        end
        table.insert(held, entry)
    end
    -- Every reference the libraries make to one another is by absolute name afterwards, into their own package or into
    -- another of these, and retarget refuses a library that still says @rpath.
    for _, entry in ipairs(held) do
        local others = {}
        for _, other in ipairs(held) do
            if other ~= entry then
                for leaf, identity in pairs(other.leaves) do
                    others[leaf] = identity
                end
            end
        end
        bundle.retarget(entry.binaries, entry.identities, {home = entry.folder .. "/", provided = others})
        for _, library in ipairs(entry.binaries) do
            os.vrunv("xcrun", table.join({"strip"}, opt.strip, {library}))
        end
        for _, library in ipairs(entry.binaries) do
            signing.sign(opt.ldid, library)
        end
    end
    local debs = {}
    for _, entry in ipairs(held) do
        local described = entry.described
        local control = path.join(opt.workdir, described.name .. ".control")
        io.writefile(control, table.concat({
            "Package: " .. described.name,
            "Name: " .. described.title,
            "Architecture: iphoneos-arm",
            "Section: System",
            "Description: " .. described.description .. " in " .. entry.folder .. "; a runtime built without library evolution cannot be replaced by another build"
        }, "\n") .. "\n")
        -- The package holds its own folder and nothing of the others'.
        local tree = path.join(opt.workdir, described.name .. "-tree")
        os.mkdir(path.directory(path.join(tree, entry.folder)))
        os.vcp(entry.destination, path.directory(path.join(tree, entry.folder)) .. "/")
        debs[described.name] = debian.write({control = control, version = described.version, root = tree, depends = described.depends, outputdir = opt.outputdir})
    end
    return debs
end
