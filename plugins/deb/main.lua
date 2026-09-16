import("core.base.option")
import("@self.charon.packaging")

function main()
    packaging.write({target = option.get("target"), outputdir = option.get("outputdir")})
end
