package("apple-backports")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("Objective-C classes, methods and constants later iOS releases added, for a minimum release that lacks them, as libFoundationBackports.dylib and libUIKitBackports.dylib in /usr/lib/charon/org.charon.apple-backports, which re-export whatever the release already has")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    add_deps("charon@firmware-tools", {alias = "firmware-tools"})
    add_deps("charon@ldid 2.1.5-procursus7+23.gaf86971", {alias = "ldid"})

    local modules = path.join(os.scriptdir(), "..", "..", "..", "modules")
    local inputs = table.join(os.files(path.join(os.scriptdir(), "*.c")), os.files(path.join(os.scriptdir(), "*.h")),
                              os.files(path.join(os.scriptdir(), "*", "*.m")), os.files(path.join(os.scriptdir(), "*", "*.h")),
                              os.files(path.join(os.scriptdir(), "registry", "*.json")), os.files(path.join(os.scriptdir(), "registry", "*", "*.json")))
    table.insert(inputs, path.join(modules, "apple", "backports.lua"))
    table.insert(inputs, path.join(os.scriptdir(), "..", "..", "..", "addons", "c", "charon", "xmake.lua"))
    table.sort(inputs)
    local digests = {}
    for _, file in ipairs(inputs) do
        table.insert(digests, path.filename(file) .. "=" .. hash.sha256(file))
    end
    local digest = hash.strhash128(table.concat(digests, ";"))
    add_configs("sources", {description = "The digest of the sources, their headers, the build module and the Charon releases, so a changed backport or a new release is a different package.", default = digest, type = "string", readonly = true})

    add_configs("uikit", {description = "Build libUIKitBackports.dylib beside libFoundationBackports.dylib, for an application; a daemon or a tool leaves UIKit out of its process.", default = false, type = "boolean"})
    add_configs("corelocation", {description = "Build libCoreLocationBackports.dylib, for a port that asks for location authorization; it loads CoreLocation into the process.", default = false, type = "boolean"})
    add_configs("avfoundation", {description = "Build libAVFoundationBackports.dylib, for a port that finds its cameras and microphones with a discovery session; it loads AVFoundation into the process.", default = false, type = "boolean"})
    add_configs("coredata", {description = "Build libCoreDataBackports.dylib, for a port that keeps its data with Core Data; it loads CoreData into the process.", default = false, type = "boolean"})
    add_configs("security", {description = "Build libSecurityBackports.dylib, for a port that evaluates a trust with SecTrustEvaluateWithError; it loads Security into the process.", default = false, type = "boolean"})

    add_configs("webkit", {description = "Build libWebKitBackports.dylib, for an application that shows web content in a WKWebView; it draws it with the UIWebView of the release.", default = false, type = "boolean"})
    add_configs("graphics", {description = "Build libGraphicsBackports.dylib, for a port that reads the name of a colour space, the code points of a video colour description or applies a block over a path or a PDF object; it loads CoreGraphics, CoreVideo and ImageIO into the process.", default = false, type = "boolean"})

    add_configs("localauthentication", {description = "Build libLocalAuthenticationBackports.dylib, for an application that asks for the owner's authentication; the device answers as one without a biometric sensor and without a way to ask for the passcode.", default = false, type = "boolean"})

    add_configs("opengles", {description = "Build libOpenGLESBackports.dylib, for an application that names the functions OpenGL ES 3.0 added; the release's driver is ES 2.0, so they answer through its extensions where it has one and with an error where it has none.", default = false, type = "boolean"})
    add_configs("safariservices", {description = "Build libSafariServicesBackports.dylib, for an application that shows a web page in an SFSafariViewController; the page is drawn by the UIWebView of the release, in bars of the application's own.", default = false, type = "boolean"})

    add_configs("authenticationservices", {description = "Build libAuthenticationServicesBackports.dylib, for an application that signs a user in through a web page with an ASWebAuthenticationSession; it brings libSafariServicesBackports.dylib, whose page it shows.", default = false, type = "boolean"})

    add_configs("backgroundtasks", {description = "Build libBackgroundTasksBackports.dylib, for an application that registers and submits background tasks with the BGTaskScheduler; iOS 6 launches no application in the background for one, so a submission answers that the scheduling is unavailable.", default = false, type = "boolean"})

    add_configs("photos", {description = "Build libPhotosBackports.dylib, for an application that asks for the authorization of the photo library through PHPhotoLibrary; it is answered from the ALAssetsLibrary of the release.", default = false, type = "boolean"})

    add_configs("gamecontroller", {description = "Build libGameControllerBackports.dylib, for an application that looks for game controllers, mice and keyboards through the GameController framework; iOS 6 has no such device support, so the lists are empty, no controller is ever announced and discovery ends at once.", default = false, type = "boolean"})

    add_configs("vision", {description = "Build libVisionBackports.dylib, for an application that names the Vision framework of iOS 11 and 12: its constants, geometry functions and classes are there, and a request the port cannot run comes back from a request handler as an error, not as a crash.", default = false, type = "boolean"})

    add_configs("metal", {description = "Build libMetalBackports.dylib, for an application that asks for the default Metal device before it draws; iOS 6 runs on graphics with no Metal, so the answer is nil and the application takes its OpenGL ES path.", default = false, type = "boolean"})

    add_configs("coretelephony", {description = "Build libCoreTelephonyBackports.dylib, for an application that reads the radio access technology of the phone and names the constants of it; iOS 6.0 has none of them and iOS 6.1 keeps the technology in a private class.", default = false, type = "boolean"})

    add_configs("accelerate", {description = "Build libAccelerateBackports.dylib, for an application that fills a vImage_Buffer from a CGImage or makes a CGImage from one: vImageBuffer_Init, vImageBuffer_InitWithCGImage and vImageCreateCGImageFromBuffer of iOS 7, over CoreGraphics, for the 8-bit RGB and gray formats.", default = false, type = "boolean"})

    add_configs("callkit", {description = "Build libCallKitBackports.dylib, for an application that places and takes VoIP calls through CallKit; iOS 6 runs no call services daemon, so the provider, the call controller and the call observer of the process meet in a broker of the port's own; it loads CoreTelephony, whose call centre gives the observer the cellular calls of the device, and AVFoundation, whose audio session a connected call activates.", default = false, type = "boolean"})

    on_load("iphoneos", function (package)
        package:add("links", table.join(package:config("uikit") and {"UIKitBackports"} or {}, package:config("corelocation") and {"CoreLocationBackports"} or {}, package:config("coredata") and {"CoreDataBackports"} or {}, package:config("security") and {"SecurityBackports"} or {}, package:config("avfoundation") and {"AVFoundationBackports"} or {}, package:config("webkit") and {"WebKitBackports"} or {}, package:config("graphics") and {"GraphicsBackports"} or {}, package:config("localauthentication") and {"LocalAuthenticationBackports"} or {}, (package:config("safariservices") or package:config("authenticationservices")) and {"SafariServicesBackports"} or {}, package:config("authenticationservices") and {"AuthenticationServicesBackports"} or {}, package:config("backgroundtasks") and {"BackgroundTasksBackports"} or {}, package:config("photos") and {"PhotosBackports"} or {}, package:config("gamecontroller") and {"GameControllerBackports"} or {}, package:config("vision") and {"VisionBackports"} or {}, package:config("metal") and {"MetalBackports"} or {}, package:config("coretelephony") and {"CoreTelephonyBackports"} or {}, package:config("accelerate") and {"AccelerateBackports"} or {}, package:config("callkit") and {"CallKitBackports"} or {}, package:config("opengles") and {"OpenGLESBackports"} or {}, {"FoundationBackports"}))
    end)

    on_install("iphoneos", function (package)
        local modules = path.join(package:scriptdir(), "..", "..", "..", "modules")
        local backports = import("apple.backports", {rootdir = modules, anonymous = true})
        local firmware = import("apple.firmware", {rootdir = modules, anonymous = true})
        local dyld = import("apple.dyld", {rootdir = modules, anonymous = true})
        local toolchain = assert(package:toolchains(), "apple-backports is built with the apple-ios toolchain")[1]
        toolchain:load()
        local linker
        for _, flag in ipairs(table.wrap(toolchain:get("shflags"))) do
            linker = flag:match("^%-fuse%-ld=(.+)$") or linker
        end
        local deployment = toolchain:config("deployment")
        local tool = path.join(package:dep("firmware-tools"):installdir(), "bin", "charon-firmware")
        local cache = firmware.ensure(package:arch(), deployment, {tool = tool})
        local libraries = table.join({"FoundationBackports"}, package:config("uikit") and {"UIKitBackports"} or {},
                                     package:config("corelocation") and {"CoreLocationBackports"} or {},
                                     package:config("coredata") and {"CoreDataBackports"} or {},
                                     package:config("security") and {"SecurityBackports"} or {},
                                     package:config("avfoundation") and {"AVFoundationBackports"} or {},
                                     package:config("webkit") and {"WebKitBackports"} or {},
                                     package:config("graphics") and {"GraphicsBackports"} or {},
                                     package:config("localauthentication") and {"LocalAuthenticationBackports"} or {},
                                     (package:config("safariservices") or package:config("authenticationservices")) and {"SafariServicesBackports"} or {},
                                     package:config("authenticationservices") and {"AuthenticationServicesBackports"} or {},
                                     package:config("backgroundtasks") and {"BackgroundTasksBackports"} or {},
                                     package:config("photos") and {"PhotosBackports"} or {},
                                     package:config("gamecontroller") and {"GameControllerBackports"} or {},
                                     package:config("vision") and {"VisionBackports"} or {},
                                     package:config("metal") and {"MetalBackports"} or {},
                                     package:config("opengles") and {"OpenGLESBackports"} or {},
                                     package:config("coretelephony") and {"CoreTelephonyBackports"} or {},
                                     package:config("accelerate") and {"AccelerateBackports"} or {},
                                     package:config("callkit") and {"CallKitBackports"} or {})
        local common = {root = package:scriptdir(), architecture = package:arch(), deployment = deployment, sdkdir = toolchain:config("sdkdir"),
                        cc = assert(toolchain:tool("cc"), "the apple-ios toolchain names no compiler for " .. package:arch()),
                        ld = assert(linker, "the apple-ios toolchain names no ld64 for " .. package:arch()), libraries = libraries}
        backports.build(table.join(common, {cache = cache, builddir = path.absolute("link"), outputdir = package:installdir("lib")}))
        local released
        for version in io.readfile(path.join(package:scriptdir(), "..", "..", "..", "addons", "c", "charon", "xmake.lua")):gmatch('add_versions%("v(%d[%d%.]*)"') do
            if not released or dyld.compare_versions(version, released) > 0 then
                released = version
            end
        end
        backports.write_deb(table.join(common, {tool = tool, builddir = path.absolute("bands"),
                                                ldid = path.join(package:dep("ldid"):installdir(), "bin", "ldid"),
                                                version = assert(released, "the addon recipe names no Charon release") .. "+" .. package:config("sources"):sub(1, 8),
                                                outputdir = package:installdir("share")}))
        os.vcp(path.join(package:scriptdir(), "registry"), package:installdir("share"))
        os.vcp(path.join(package:scriptdir(), "..", "..", "..", "LICENSE"), package:installdir("licenses"))
    end)

    on_test(function (package)
        for _, name in ipairs(package:get("links")) do
            assert(os.isfile(path.join(package:installdir("lib"), "lib" .. name .. ".dylib")), name)
        end
        assert(#os.files(path.join(package:installdir("share"), "org.charon.apple-backports_*.deb")) == 1)
    end)
