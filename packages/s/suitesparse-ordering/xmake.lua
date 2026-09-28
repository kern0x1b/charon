package("suitesparse-ordering")
    set_homepage("https://people.engr.tamu.edu/davis/suitesparse.html")
    set_description("AMD and COLAMD from SuiteSparse 7.12.2, the two sparse orderings, unmodified, as a static library whose every symbol is hidden, for the image that links it in")
    set_license("BSD-3-Clause")
    set_policy("package.strict_compatibility", true)

    -- The same tarball the machine's own xmake registry already pins, and the same hash: this is not a
    -- URL invented here, it is the one packages/s/suitesparse/xmake.lua in ~/.xmake/repositories
    -- carries for v7.12.2, so a store that has built suitesparse has already trusted these bytes.
    add_urls("https://github.com/DrTimothyAldenDavis/SuiteSparse/archive/refs/tags/$(version).tar.gz")
    add_versions("v7.12.2", "679412daa5f69af96d6976595c1ac64f252287a56e98cc4a8155d09cc7fd69e8")
    add_links("SuiteSparseOrdering")

    add_configs("recipe", {description = "The digest of this recipe, so a changed flag is a different library.", default = hash.strhash128(hash.sha256(path.join(os.scriptdir(), "xmake.lua"))), type = "string", readonly = true})

    -- Only the two orderings. CHOLMOD, UMFPACK, CXSparse, SuiteSparseQR, KLU, Mongoose, ParU, RBio, SPQR,
    -- SPEX, GraphBLAS, CAMD, CCOLAMD, CSparse and BTF are all in the same tarball and none of them is
    -- named in this list, because the first two are LGPL and GPL and the rest are not what this package
    -- is for. The list is spelled out rather than globbed so that a directory added to the tarball
    -- cannot join the build by accident.
    local AMD_SOURCES = {
        "amd_1.c", "amd_2.c", "amd_aat.c", "amd_control.c", "amd_defaults.c", "amd_dump.c", "amd_info.c",
        "amd_post_tree.c", "amd_postorder.c", "amd_preprocess.c", "amd_valid.c", "amd_version.c",
    }
    local COLAMD_SOURCES = {"colamd.c", "colamd_version.c"}
    local HEADERS = {
        ["AMD/Include/amd.h"] = "SuiteSparse/AMD",
        ["AMD/Include/amd_internal.h"] = "SuiteSparse/AMD",
        ["COLAMD/Include/colamd.h"] = "SuiteSparse/COLAMD",
        ["SuiteSparse_config/SuiteSparse_config.h"] = "SuiteSparse/SuiteSparse_config",
    }
    local LICENSES = {"AMD/Doc/License.txt", "COLAMD/Doc/License.txt", "AMD/README.txt", "COLAMD/README.txt"}

    -- Hidden, so the orderings are never API of the image they are linked into: libAccelerateBackports
    -- dylib exports what Accelerate exports, and nothing a second copy of AMD in the process could bind
    -- to. That is the whole reason this is a package and not a vendored copy of the sources in the tree:
    -- the sources stay in the store, the archive is built here, and `nm -gU` on the built dylib shows no
    -- amd_* or colamd_* name in it, so release-split has nothing of ours to place.
    local FLAGS = {"-Os", "-fvisibility=hidden"}

    on_install("iphoneos", function (package)
        local toolchain = assert(package:toolchains(), "suitesparse-ordering is built with the apple-ios toolchain")[1]
        toolchain:load()
        -- What the toolchain answers for the two compilers, before anything else is assumed: box2d asks
        -- for "cxx" and this package asks for "cc", and the install log says only "assertion failed!",
        -- so this is where the question gets answered rather than guessed at.
        print("suitesparse-ordering: toolchain %s, cc = %s, cxx = %s", tostring(toolchain), tostring(toolchain:tool("cc")),
              tostring(toolchain:tool("cxx")))
        local sdkdir = toolchain:config("sdkdir")
        -- -isysroot alone leaves a C compile with no C library: SuiteSparse_config.h includes <stdio.h>
        -- and the compiler answers "'stdio.h' file not found" (measured, and it was the bare
        -- "assertion failed!" above this, because xmake's own assert carries no message). The SDK's
        -- own headers go in with -isystem, which is where a sysroot's belong; the toolchain's clang is
        -- what compiles, so the C++ headers are not needed for this package, which is C.
        local target = {"-target", package:arch() .. "-apple-ios", "-miphoneos-version-min=" .. toolchain:config("deployment"),
                        "-isysroot", sdkdir, "-isystem", path.join(sdkdir, "usr", "include"),
                        "-I" .. path.join(os.curdir(), "SuiteSparse_config"),
                        "-I" .. path.join(os.curdir(), "AMD", "Include"), "-I" .. path.join(os.curdir(), "COLAMD", "Include")}
        -- and it says which it found, so a layout change is a message and not an assertion below.
        for _, directory in ipairs({"AMD/Source", "COLAMD/Source", "SuiteSparse_config", "AMD/Include", "COLAMD/Include"}) do
            assert(os.isdir(path.join(os.curdir(), directory)), "SuiteSparse " .. package:version()
                .. " did not unpack " .. directory .. " where the recipe expects it")
        end

        local objects = {}
        for _, directory in ipairs({"AMD", "COLAMD"}) do
            local sources = directory == "AMD" and AMD_SOURCES or COLAMD_SOURCES
            for _, name in ipairs(sources) do
                local source = path.join(directory, "Source", name)
                assert(os.isfile(source), "SuiteSparse " .. package:version() .. " has no " .. source)
                local object = path.absolute(path.join("objects", directory .. "_" .. name:gsub("%.c$", "") .. ".o"))
                os.mkdir(path.directory(object))
                os.vrunv(toolchain:tool("cc"), table.join(target, FLAGS, {"-c", source, "-o", object}))
                table.insert(objects, object)
            end
        end
        table.sort(objects)
        os.vrunv("xcrun", table.join({"libtool", "-static", "-o", path.join(package:installdir("lib"), "libSuiteSparseOrdering.a")}, objects))

        -- The destination ends in a separator, which is what makes os.vcp treat it as a directory to
        -- put the file in rather than as the name of a file to write - box2d's recipe writes it that way
        -- and this one did not, so every header copy went somewhere else and on_test then reported
        -- "installed no SuiteSparse/AMD/amd.h". The return value is checked too, so a copy that fails
        -- says which one instead of being ignored.
        -- os.vcp creates the last component of its destination and not the ones above it, so the two
        -- levels of include/SuiteSparse/AMD are made first: without this the copy of
        -- SuiteSparse_config/SuiteSparse_config.h is attempted into a directory whose parent does not
        -- exist and the recipe says so, by name, rather than not at all.
        os.mkdir(path.join(package:installdir("include"), "SuiteSparse"))
        os.mkdir(path.join(package:installdir("licenses")))
        for from, to in pairs(HEADERS) do
            assert(os.isfile(from), "SuiteSparse " .. package:version() .. " has no " .. from)
            -- every level of the destination made here rather than left to os.vcp, whose habit of
            -- creating the last component and not the ones above it cost two runs: first
            -- SuiteSparse_config/SuiteSparse_config.h, then COLAMD/Include/colamd.h.
            os.mkdir(path.join(package:installdir("include"), to))
            assert(os.vcp(from, path.join(package:installdir("include"), to) .. "/"),
                   "suitesparse-ordering could not install " .. from)
        end
        for _, name in ipairs(LICENSES) do
            if os.isfile(name) then
                assert(os.vcp(name, path.join(package:installdir("licenses"), name:gsub("[/\\]", "_"))),
                       "suitesparse-ordering could not install " .. name)
            end
        end
        assert(os.vcp("AMD/Doc/License.txt", path.join(package:installdir("licenses"), "AMD-LICENSE.txt")),
               "suitesparse-ordering could not install AMD's licence")
        assert(os.vcp("COLAMD/Doc/License.txt", path.join(package:installdir("licenses"), "COLAMD-LICENSE.txt")),
               "suitesparse-ordering could not install COLAMD's licence")
    end)

    on_test(function (package)
        for _, header in ipairs({"SuiteSparse/AMD/amd.h", "SuiteSparse/AMD/amd_internal.h", "SuiteSparse/COLAMD/colamd.h",
                                 "SuiteSparse/SuiteSparse_config/SuiteSparse_config.h"}) do
            assert(os.isfile(path.join(package:installdir("include"), header)),
                   "suitesparse-ordering installed no " .. header)
        end
        for _, licence in ipairs({"AMD-LICENSE.txt", "COLAMD-LICENSE.txt"}) do
            assert(os.isfile(path.join(package:installdir("licenses"), licence)),
                   "suitesparse-ordering installed no " .. licence)
        end
        -- last, so a missing archive is the last thing a failure can be about
        assert(os.isfile(path.join(package:installdir("lib"), "libSuiteSparseOrdering.a")),
               "suitesparse-ordering built no " .. path.join(package:installdir("lib"), "libSuiteSparseOrdering.a"))
    end)
