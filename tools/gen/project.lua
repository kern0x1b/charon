-- The project's own fixed facts: the compile SDK of the package, the one the protocol bodies are transcribed from. They are options with
-- the project's defaults, not literals inside a step: a step takes sdk16(args), and --sdk16 or CHARON_SDK16 override the default. The
-- release of that SDK is read from it by sdk.discover, so no step names it. This file is the only place a machine path is written.

local DEFAULT_SDK16 = path.join(os.getenv("HOME") or "", ".xmake", "packages", "i", "iphoneos-sdk", "16.4",
                                "cccc080d0cbe42c2a85b1369aba6e290", "Developer.app", "Contents", "Developer", "Platforms",
                                "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS16.4.sdk")

-- The folder of the compile SDK: args.sdk16, else CHARON_SDK16, else the project's default.
function sdk16(args)
    return args.sdk16 or os.getenv("CHARON_SDK16") or DEFAULT_SDK16
end
