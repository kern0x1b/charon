rule("tweak")
    add_deps("@self/apple-ios")

    on_load(function (target)
        target:set("kind", "shared")
        target:set("prefixname", "")
        target:set("extension", ".dylib")
        target:add("packages", "ldid")
        local installed = target:values("charon.install") or "/Library/MobileSubstrate/DynamicLibraries"
        target:data_set("charon.install", installed)
        target:add("shflags", "-install_name", installed .. "/" .. target:filename(), {force = true})
    end)

    after_link(function (target)
        import("@self.apple.platform")
        platform.verify_inputs(target)
        platform.verify(target, target:targetfile())
    end)

    on_install(function (target)
        import("@self.apple.platform")
        local folder = path.join(target:installdir(), target:data("charon.install"))
        os.mkdir(folder)
        local installed = path.join(folder, target:filename())
        os.vcp(target:targetfile(), installed)
        platform.finish(target, installed)
        local filter = target:values("tweak.filter")
        if filter then
            os.vcp(path.join(target:scriptdir(), filter), path.join(folder, target:basename() .. ".plist"))
        end
        platform.install_files(target)
    end)
