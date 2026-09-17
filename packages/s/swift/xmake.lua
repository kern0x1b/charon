package("swift")
    set_kind("toolchain")
    set_homepage("https://www.swift.org")
    set_description("The swift.org compiler, only what compiles a module (driver, frontend, its host libraries, the clang headers and shims), with the standard library sources of the same release")
    set_license("Apache-2.0 WITH Swift-exception")

    add_urls("https://download.swift.org/swift-$(version)-release/xcode/swift-$(version)-RELEASE/swift-$(version)-RELEASE-osx.pkg")
    add_versions("6.4.0", "8fd03185b98fe27f54a54631c2449decf75d5b466ce8e34abbd414141063c6aa")

    local sources = {["6.4.0"] = "b8189d766d86ad7fc8106787d6ce9e402f38dd72"}

    local kept = {
        "usr/bin/swift-frontend", "usr/bin/swift-driver", "usr/lib/swift/host", "usr/lib/swift/shims", "usr/lib/swift/apinotes",
        "usr/lib/swift/module.modulemap", "usr/lib/clang",
        "usr/lib/swift/macosx/libSwiftDriver.dylib", "usr/lib/swift/macosx/libSwiftDriverExecution.dylib",
        "usr/lib/swift/macosx/libSwiftOptions.dylib", "usr/lib/swift/macosx/libTSCBasic.dylib", "usr/lib/swift/macosx/libTSCUtility.dylib",
        "usr/lib/swift/macosx/libllbuildSwift.dylib", "usr/lib/swift/macosx/libArgumentParser.dylib"
    }

    on_download(function (package, opt)
        import("net.http")
        local swift = import("apple.swift", {rootdir = path.join(package:scriptdir(), "..", "..", "..", "modules"), anonymous = true})
        local staging = opt.sourcedir .. ".tmp"
        os.tryrm(staging)
        os.mkdir(staging)

        local archive = path.join(staging, "toolchain.pkg")
        http.download(opt.url, archive)
        local digest = hash.sha256(archive)
        if digest ~= package:sourcehash(opt.url_alias) then
            raise("%s has sha256 %s, not the %s this package was written against", opt.url, digest, tostring(package:sourcehash(opt.url_alias)))
        end
        local expanded = path.join(staging, "expanded")
        os.vrunv("pkgutil", {"--expand-full", archive, expanded})
        local payload = os.dirs(path.join(expanded, "*.pkg", "Payload"))[1]
        if not payload then
            raise("%s holds no package payload", opt.url)
        end
        local toolchain = path.join(staging, "toolchain")
        for _, item in ipairs(kept) do
            local from = path.join(payload, item)
            if not os.exists(from) then
                raise("the swift.org %s toolchain has no %s", package:version_str(), item)
            end
            os.mkdir(path.directory(path.join(toolchain, item)))
            os.vcp(from, path.join(toolchain, item), {symlink = true})
        end
        os.ln("swift-driver", path.join(toolchain, "usr", "bin", "swiftc"))
        local clang = path.filename(assert(os.dirs(path.join(toolchain, "usr", "lib", "clang", "*"))[1], "the toolchain has no clang resource folder"))
        os.ln(path.join("..", "clang", clang), path.join(toolchain, "usr", "lib", "swift", "clang"))
        os.tryrm(archive)
        os.tryrm(expanded)

        local tag = "swift-" .. package:version_str() .. "-RELEASE"
        local checkout = path.join(staging, "source")
        os.vrunv("git", {"clone", "--depth", "1", "--branch", tag, "--filter=blob:none", "--no-checkout", "https://github.com/swiftlang/swift.git", checkout})
        local head = os.iorunv("git", {"-C", checkout, "rev-parse", "HEAD"}):trim()
        if head ~= sources[package:version_str()] then
            raise("%s is %s now, not the %s this package was written against; a tag that moved is not the release it names", tag, head, tostring(sources[package:version_str()]))
        end
        os.vrunv("git", table.join({"-C", checkout, "sparse-checkout", "set", "--no-cone"}, swift.source_paths()))
        os.vrunv("git", {"-C", checkout, "checkout", tag})

        os.tryrm(opt.sourcedir)
        os.mv(staging, opt.sourcedir)
    end)

    on_install("@macosx", function (package)
        os.vcp(path.join("toolchain", "usr", "*"), package:installdir() .. "/", {symlink = true})
        local source = path.join(package:installdir("share"), "swift-source")
        os.vcp("source", source, {symlink = true})
        os.tryrm(path.join(source, ".git"))
        os.vcp(path.join("source", "LICENSE.txt"), package:installdir("licenses") .. "/")
    end)

    on_test(function (package)
        local version = os.iorunv(path.join(package:installdir("bin"), "swiftc"), {"--version"})
        local release = "swift-" .. package:version():major() .. "." .. package:version():minor() .. "-RELEASE"
        assert(version:find(release, 1, true), "swiftc of the swift package reports " .. version)
        assert(os.isfile(path.join(package:installdir("share", "swift-source", "stdlib", "public", "core"), "CMakeLists.txt")))
    end)
