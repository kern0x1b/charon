-- healthkit as a device binary: the three questions a 6.1.3 device can answer, asked of this port on
-- the emulator and held to what Apple's own headers document, with the release's own HealthKit as the
-- control - which on 6.1.3 is absent, and the absence is what the test reports for the release side.
set_project("healthkit-device")
set_version("0.0.1")
add_repositories("charon https://github.com/kern0x1b/charon.git charon-repo-0.8.12")
add_addons("charon v0.8.12")
set_config("apple_minimum", "6.1.3")
includes("@addon/charon/apple-ios")
includes("@addon/charon/emulate")
set_allowedplats("iphoneos")
set_allowedarchs("iphoneos|armv7")
set_defaultplat("iphoneos")
set_defaultarchs("iphoneos|armv7")

local root = os.getenv("HEALTHKIT_ROOT") or path.join(os.scriptdir(), "../../../..")
local sources = {
    "CharonHKStore.m", "CharonHKTypes.m", "HKObject.m", "HKObjectType.m", "HKSample.m", "HKSamples.m",
    "HKSource.m", "HKQuantity.m", "HKQuantityType.m", "HKQuantityTypes.m", "HKUnit.m", "HKWorkout.m",
    "HKWorkoutEvent.m", "HKCharacteristicObjects.m", "HKFitzpatrickSkinTypeObject9.m", "HKStatistics.m",
    "HKQuery.m", "HKQueries.m", "HKQueryAnchor9.m", "HKDevice9.m", "HKActivitySummary93.m",
    "HKActivitySummaryQuery93.m", "HKHealthStore.m", "HKHealthStore9.m", "HKHealthStore10.m",
    "HKDocument10.m", "HKDocumentQuery10.m", "HKConstants8.m", "HKConstants82.m", "HKConstants90.m",
    "HKConstants93.m", "HKConstants100.m",
}

target("healthkit")
    add_rules("@addon/charon/daemon")
    for _, name in ipairs(sources) do
        add_files(path.join(root, "packages/a/apple-backports/HealthKit", name))
    end
    add_files(path.join(root, "tests/backports/device/healthkit.m"), path.join(root, "tests/backports/device/check.m"))
    add_includedirs(path.join(root, "tests/backports/device"), path.join(root, "packages/a/apple-backports/HealthKit"))
    add_mflags("-fobjc-arc", "-Wno-deprecated-declarations", "-Wno-unguarded-availability")
    add_ldflags("-fobjc-arc", "-lsqlite3")
    add_frameworks("Foundation", "UIKit", "CoreGraphics", "QuartzCore", "CoreLocation", "AudioToolbox", "ImageIO")
    add_syslinks("sqlite3")
    add_values("charon.version", "1.0")
