rule("check")
    on_load(function (target)
        target:set("kind", "phony")
        target:set("default", false)
        if not target:values("check.command") then
            raise("target(%s) is a check without set_values(\"check.command\", PROGRAM, ARGUMENTS...)", target:name())
        end
    end)
