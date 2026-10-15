-- The SDK the generator runs on, read from the SDK alone (coordination/wave-2026-10-03/design-sdk-generator.md, contract 2): the name
-- and the version from its SDKSettings.json (CanonicalName, Version), and the target triple of the parse from its deployment target.
-- Every step that needs "the release" takes it from here; no step names a release, a framework or a machine path.
-- The module lists come from the steps that read them: decls --list (the declaration frameworks) and swift_shard.modules (the Swift
-- modules).

local files = import("files", {anonymous = true})
local json = import("core.base.json")

-- The SDK's settings: {path, name, version, triple}, where name is the canonical name (iphoneos26.2), version the release (26.2) and
-- triple the arm64e triple of the SDK's deployment target. Raises, naming the file, when SDKSettings.json is absent or lacks a field.
function discover(sdk)
    local file = path.join(sdk, "SDKSettings.json")
    local text = files.read_text(file)
    assert(text, "no SDKSettings.json in " .. sdk .. ": not an SDK folder")
    local settings = json.decode(text)
    assert(type(settings) == "table", "SDKSettings.json is not a JSON object: " .. file)
    assert(settings.CanonicalName and settings.CanonicalName ~= "", "no CanonicalName in " .. file)
    assert(settings.Version and settings.Version ~= "", "no Version in " .. file)
    assert(settings.DefaultDeploymentTarget, "no DefaultDeploymentTarget in " .. file)
    return {
        path = sdk,
        name = settings.CanonicalName,
        version = settings.Version,
        triple = "arm64e-apple-ios" .. settings.DefaultDeploymentTarget,
    }
end
