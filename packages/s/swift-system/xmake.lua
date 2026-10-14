package("swift-system")
    set_homepage("https://github.com/apple/swift-system")
    set_description("swift-system 1.8.1, Apple's System module (FilePath, Errno, FileDescriptor and the calls under them): the release sources pinned by sha256, patched for the port, with the armv7 iOS 6.1.3 build script and the host differential against Apple's System. Apache-2.0 upstream")
    set_license("Apache-2.0")
    set_policy("package.strict_compatibility", true)

    -- The release tarball of the tag 1.8.1 (the tag names commit 869129b7bf), pinned by its sha256 as the other recipes pin theirs.
    add_urls("https://github.com/apple/swift-system/archive/refs/tags/$(version).tar.gz")
    add_versions("1.8.1", "5610bea8f1f390895137247e7e6aa6bf89a6cd108d75d3368aba5da3f06f0d7a")

    -- The identity of this recipe: a changed recipe, patch or build script is a different package, so nothing has to be
    -- removed from the shared store.
    local digests = {}
    local inputs = {os.scriptdir() .. "/xmake.lua", os.scriptdir() .. "/build-armv7.sh"}
    for _, patch in ipairs(os.files(os.scriptdir() .. "/patches/*.patch")) do
        table.insert(inputs, patch)
    end
    table.sort(inputs)
    for _, file in ipairs(inputs) do
        table.insert(digests, path.filename(file) .. "=" .. hash.sha256(file))
    end
    add_configs("sources", {description = "The digest of this recipe, its patches and its build script, so a changed step is a different package.",
                            default = hash.strhash128(table.concat(digests, ";")), type = "string", readonly = true})

    -- Installs upstream's tree with this recipe's patches applied, the armv7 build script that compiles the module from it,
    -- and the host differential against Apple's System. Nothing is compiled here: build-armv7.sh takes its toolchain paths
    -- from the environment (see its header), and the differential runs on a Mac with the Xcode command line tools.
    on_install(function (package)
        local tree = package:installdir("src")
        os.cp(os.curdir(), tree)
        for _, patch in ipairs(os.files(path.join(os.scriptdir(), "patches", "*.patch"))) do
            os.vrunv("patch", {"-d", tree, "-p1", "-s", "-i", patch})
        end
        os.cp(path.join(os.scriptdir(), "build-armv7.sh"), package:installdir("bin"))
        os.cp(path.join(os.scriptdir(), "tests", "differential"), package:installdir("share"))
        print("%s: %s installed; the source is patched in %s", package:name(), package:version_str(), tree)
    end)
