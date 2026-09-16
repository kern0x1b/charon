rule("apple-ios")
    on_load(function (target)
        import("core.project.project")
        local minimum = get_config("apple_minimum")
        if not minimum then
            raise("target(%s) builds for apple-ios and its project names no oldest release: set_config(\"apple_minimum\", \"6.0\")", target:name())
        end
        local versions = {}
        for _, name in ipairs({"iphoneos-sdk", "ld64"}) do
            local required = project.required_package(name)
            if not required then
                raise("target(%s) builds for apple-ios without includes(\"@addon/charon/apple-ios\") in its project", target:name())
            end
            versions[name] = required:get("version")
        end
        target:set("toolchains", string.format("@addon/charon/apple-ios[minimum=%s,sdk=%s,ld64=%s]", minimum, versions["iphoneos-sdk"], versions.ld64))
        target:set("policy", "build.ccache", false)
        local mapped = "-ffile-prefix-map=" .. os.projectdir() .. "=/port"
        target:add("cxflags", mapped)
        target:add("mxflags", mapped)
        target:add("asflags", mapped)
    end)
