package("monocypher")
    set_homepage("https://monocypher.org")
    set_description("Monocypher 4.0.2, the curves and the AEAD HAP pairs with: X25519, Ed25519 and ChaCha20-Poly1305 (the IETF construction, which is the one HAP's session keys use) and BLAKE2b for the key derivation, unmodified, as a static library whose every symbol is hidden, for the image that links it in")
    set_license("BSD-2-Clause OR CC0-1.0")
    set_policy("package.strict_compatibility", true)

    add_urls("https://monocypher.org/download/monocypher-$(version).tar.gz")
    add_versions("4.0.2", "38d07179738c0c90677dba3ceb7a7b8496bcfea758ba1a53e803fed30ae0879c")
    add_links("Monocypher")

    add_configs("recipe", {description = "The digest of this recipe, so a changed flag is a different library.", default = hash.strhash128(hash.sha256(path.join(os.scriptdir(), "xmake.lua"))), type = "string", readonly = true})

    -- Hidden, for the reason Box2D's recipe gives: libHomeKitBackports.dylib exports what HomeKit
    -- does, and nothing a second copy of Monocypher in the process could bind to. The sources are
    -- vendored rather than fetched, so the tree carries exactly the 4.0.2 release this recipe names
    -- -- Monocypher's own site is where the tarball is taken from when the package is built fresh, and
    -- the vendored copy is what the digest below pins.
    local FLAGS = {"-Os", "-fvisibility=hidden", "-fvisibility-inlines-hidden", "-DCONFIG_64_BITS"}

    on_install("iphoneos", function (package)
        local toolchain = assert(package:toolchains(), "monocypher is built with the apple-ios toolchain")[1]
        toolchain:load()
        local target = {"-target", package:arch() .. "-apple-ios", "-miphoneos-version-min=" .. toolchain:config("deployment"),
                        "-isysroot", toolchain:config("sdkdir"), "-I" .. os.curdir()}
        local objects = {}
        for _, source in ipairs({"monocypher.c", "monocypher-ed25519.c"}) do
            local object = path.absolute(path.join("objects", source:gsub("%.c$", ".o")))
            os.mkdir(path.directory(object))
            os.vrunv(toolchain:tool("cc"), table.join(target, FLAGS, {"-c", source, "-o", object}))
            table.insert(objects, object)
        end
        os.vrunv("xcrun", table.join({"libtool", "-static", "-o", path.join(package:installdir("lib"), "libMonocypher.a")}, objects))
        for _, header in ipairs({"monocypher.h", "monocypher-ed25519.h"}) do
            os.vcp(header, path.join(package:installdir("include"), "monocypher/") .. path.filename(header))
        end
        os.vcp("LICENCE.md", package:installdir("licenses"))
    end)

    on_test(function (package)
        assert(os.isfile(path.join(package:installdir("lib"), "libMonocypher.a")))
        assert(os.isfile(path.join(package:installdir("include"), "monocypher", "monocypher.h")))
    end)
