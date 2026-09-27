package("apple-backports")
    set_homepage("https://github.com/kern0x1b/charon")
    set_description("Objective-C classes, methods and constants later iOS releases added, for a minimum release that lacks them, as libFoundationBackports.dylib and libUIKitBackports.dylib in /usr/lib/charon/org.charon.apple-backports, which re-export whatever the release already has")
    set_license("MIT")
    set_policy("package.strict_compatibility", true)

    add_deps("charon@firmware-tools", {alias = "firmware-tools"})
    add_deps("charon@ldid 2.1.5-procursus7+23.gaf86971", {alias = "ldid"})
    add_deps("charon@box2d 2.2.1", {alias = "box2d"})

    local modules = path.join(os.scriptdir(), "..", "..", "..", "modules")
    local inputs = table.join(os.files(path.join(os.scriptdir(), "*.c")), os.files(path.join(os.scriptdir(), "*.h")),
                              os.files(path.join(os.scriptdir(), "*", "*.m")), os.files(path.join(os.scriptdir(), "*", "*.mm")), os.files(path.join(os.scriptdir(), "*", "*.h")),
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
    add_configs("network", {description = "Build libNetworkBackports.dylib beside libFoundationBackports.dylib, for a port that asks Network for a connection or the path it is on; iOS 6 has no Network.framework, so the connection is a real BSD datagram socket and the path is the reachability the Foundation library already carries. It is what the Matter framework's device browser needs.", default = false, type = "boolean"})
    add_configs("corelocation", {description = "Build libCoreLocationBackports.dylib, for a port that asks for location authorization; it loads CoreLocation into the process.", default = false, type = "boolean"})
    add_configs("avfoundation", {description = "Build libAVFoundationBackports.dylib, for a port that finds its cameras and microphones with a discovery session or builds an H.264 format description from parameter sets and encodes with the H.264 profile levels of iOS 7; it loads AVFoundation, and libGraphicsBackports with CoreVideo, into the process.", default = false, type = "boolean"})
    add_configs("coredata", {description = "Build libCoreDataBackports.dylib, for a port that keeps its data with Core Data; it loads CoreData into the process.", default = false, type = "boolean"})
    add_configs("security", {description = "Build libSecurityBackports.dylib, for a port that evaluates a trust with SecTrustEvaluateWithError; it loads Security into the process.", default = false, type = "boolean"})

    add_configs("avfaudio", {description = "Build libAVFAudioBackports.dylib, for an application that looks for audio components, builds an AVAudioTime, an AVAudioChannelLayout, an AVParameterEvent or asks for the record permission through AVAudioApplication; the component discovery, the AudioComponent/AudioUnit C API and the clock it converts through are the release's own, so it builds on the carried AVAudioEngine, AVAudioFormat and AVAudioUnit and so brings libAVFoundationBackports.dylib with it, loading AVFAudio, AVFoundation, AudioToolbox and CoreAudio into the process.", default = false, type = "boolean"})

    add_configs("webkit", {description = "Build libWebKitBackports.dylib, for an application that shows web content in a WKWebView; it draws it with the UIWebView of the release.", default = false, type = "boolean"})
    add_configs("graphics", {description = "Build libGraphicsBackports.dylib, for a port that reads the name of a colour space, the code points of a video colour description or applies a block over a path or a PDF object; it loads CoreGraphics, CoreVideo and ImageIO into the process.", default = false, type = "boolean"})

    add_configs("localauthentication", {description = "Build libLocalAuthenticationBackports.dylib, for an application that asks for the owner's authentication; the device answers as one without a biometric sensor and without a way to ask for the passcode.", default = false, type = "boolean"})

    add_configs("opengles", {description = "Build libOpenGLESBackports.dylib, for an application that names the functions OpenGL ES 3.0 added; the release's driver is ES 2.0, so they answer through its extensions where it has one and with an error where it has none.", default = false, type = "boolean"})
    add_configs("mapkit", {description = "Build libMapKitBackports.dylib, for an application that draws overlays with MapKit's own renderers, frames a map with a camera, or takes a map snapshot. iOS 6 has the MKMapView and the whole of the MKOverlayView drawing path but none of the iOS 7 renderer tree, so the renderers here are the release's own overlay view with the iOS 7 API on it, the camera and the snapshotter are built on the release's own map view and projection, and the tile overlays fetch for real over NSURLConnection.", default = false, type = "boolean"})

    add_configs("passkit", {description = "Build libPassKitBackports.dylib, for an application that reads a pass with the iOS 7-and-later members of the SDK's PKPass and PKPassLibrary, which the release's own Passbook already carries, and that compares against the two PassKit notification names. Apple Pay is not carried: the device has no Secure Element, and +canMakePayments answers NO in Apple's own words.", default = false, type = "boolean"})

    add_configs("carplay", {description = "Build libCarPlayBackports.dylib, for an application that draws CarPlay's templates and the car home screen in-app. iOS 6 has no CarPlay at all and there is no car, so the list, grid and map templates, the interface controller, the window and the buttons are real view controllers over the release's own UIKit and MapKit, the home screen is the apps' own icons read at run time, the dock is the release's own clock, CoreTelephony radio technology and UIDevice battery, and the scene connection is the wall and is carried as such.", default = false, type = "boolean"})

    add_configs("safariservices", {description = "Build libSafariServicesBackports.dylib, for an application that shows a web page in an SFSafariViewController; the page is drawn by the UIWebView of the release, in bars of the application's own.", default = false, type = "boolean"})

    add_configs("authenticationservices", {description = "Build libAuthenticationServicesBackports.dylib, for an application that signs a user in through a web page with an ASWebAuthenticationSession; it brings libSafariServicesBackports.dylib, whose page it shows.", default = false, type = "boolean"})

    add_configs("backgroundtasks", {description = "Build libBackgroundTasksBackports.dylib, for an application that registers and submits background tasks with the BGTaskScheduler; iOS 6 launches no application in the background for one, so a submission answers that the scheduling is unavailable.", default = false, type = "boolean"})

    add_configs("photos", {description = "Build libPhotosBackports.dylib, for an application that asks for the authorization of the photo library through PHPhotoLibrary; it is answered from the ALAssetsLibrary of the release.", default = false, type = "boolean"})

    add_configs("gamecontroller", {description = "Build libGameControllerBackports.dylib, for an application that looks for game controllers, mice and keyboards through the GameController framework; iOS 6 has no such device support, so the lists are empty, no controller is ever announced and discovery ends at once.", default = false, type = "boolean"})

    add_configs("vision", {description = "Build libVisionBackports.dylib, for an application that names the Vision framework of iOS 11 and 12: its constants, geometry functions and classes are there, and a request the port cannot run comes back from a request handler as an error, not as a crash.", default = false, type = "boolean"})

    add_configs("metal", {description = "Build libMetalBackports.dylib, for an application that asks for the default Metal device before it draws; iOS 6 runs on graphics with no Metal driver, so MTLCreateSystemDefaultDevice gives a real device of the port's own that translates the calls it can onto OpenGL ES 2.0, and honestly refuses the ones it cannot, such as compiling Metal Shading Language source at runtime.", default = false, type = "boolean"})

    add_configs("metalkit", {description = "Build libMetalKitBackports.dylib beside libMetalBackports.dylib, for an application that draws with an MTKView or loads a mesh or a texture through MetalKit; it draws over the same OpenGL ES 2.0 bridge Metal itself uses.", default = false, type = "boolean"})

    add_configs("coretelephony", {description = "Build libCoreTelephonyBackports.dylib, for an application that reads the radio access technology of the phone and names the constants of it; iOS 6.0 has none of them and iOS 6.1 keeps the technology in a private class.", default = false, type = "boolean"})

    add_configs("contacts", {description = "Build libContactsBackports.dylib, for an application that reads or writes the address book through the Contacts framework of iOS 9; it answers out of the AddressBook the release already carries, whose store is the same one.", default = false, type = "boolean"})

    add_configs("accelerate", {description = "Build libAccelerateBackports.dylib, for an application that fills a vImage_Buffer from a CGImage or makes a CGImage from one: vImageBuffer_Init, vImageBuffer_InitWithCGImage and vImageCreateCGImageFromBuffer of iOS 7, over CoreGraphics, for the 8-bit RGB and gray formats.", default = false, type = "boolean"})

    add_configs("callkit", {description = "Build libCallKitBackports.dylib, for an application that places and takes VoIP calls through CallKit; iOS 6 runs no call services daemon, so the provider, the call controller and the call observer of the process meet in a broker of the port's own; it loads CoreTelephony, whose call centre gives the observer the cellular calls of the device, and AVFoundation, whose audio session a connected call activates.", default = false, type = "boolean"})

    add_configs("corespotlight", {description = "Build libCoreSpotlightBackports.dylib, for an application that indexes what it shows with CSSearchableIndex; writes, deletes and the batch client state journal to a real per-index store under Application Support, and a best-effort bridge registers the store's category with the release's own private SPSpotlightManager so the pull it already runs for Messages and Calendar can reach it too.", default = false, type = "boolean"})

    add_configs("pushkit", {description = "Build libPushKitBackports.dylib, for an application that places or takes VoIP calls through PKPushRegistry; the release's own apsd hands out a real device token, so a registry that shares a UIUserNotificationType already registered by the application receives one exactly as PushKit promises. apsd on this release ties every token to a user-facing Badge/Sound/Alert prompt, with no silent registration path, so a registry with no such prior registration never receives one - the one seam this port cannot reach, since only Apple's own service issues the token.", default = false, type = "boolean"})

    add_configs("intents", {description = "Build libIntentsBackports.dylib, for an application that donates an interaction, offers a vocabulary or resolves and handles an intent in process; iOS 6 runs no assistant daemon and no intent extension host, so a donation and the phrases an application offers are kept in the application's own store and read back, and every value a resolution result carries is read through the accessors of CharonIntentsResolution.h; it loads UIKit, whose asset catalogue is where an Intents image comes from", default = false, type = "boolean"})

    add_configs("javascriptcore", {description = "Build libJavaScriptCoreBackports.dylib, for an application that runs JavaScript through JSContext, JSValue, JSVirtualMachine, JSManagedValue or a class conforming to JSExport; the release already carries JavaScriptCore.framework's C API (JSGlobalContextRef, JSValueRef, JSObjectRef and their functions), confirmed by the release's own export table rather than a running process's memory, and this is a wrapper over exactly that.", default = false, type = "boolean"})

    add_configs("scenekit", {description = "Build libSceneKitBackports.dylib, for an application that plays a compiled .scn scene archive through SCNScene/SCNView; SceneKit.framework carries no code at all on this release, so this is the archiver's own object graph -- SCNScene, SCNNode, SCNGeometry and its sources and elements, SCNMaterial and SCNMaterialProperty, SCNParticleSystem and its property controller, SCNLight, SCNCamera, SCNPlane, SCNPhysicsWorld and SCNPhysicsRadialGravityField -- decoded from the real keyed-archive keys of the release's own SCNKeyedArchiver format -- and SCNView, which draws the scene's meshes with SceneKit's lighting models, as measured against macOS SceneKit, over the OpenGL ES 2.0 this device already has; animations are evaluated as SceneKit's are; particles, subdivision, the clear coat and normal and ambient occlusion maps are not drawn yet (facts/SceneKit/SCNView.md).", default = false, type = "boolean"})

    add_configs("mediaplayer", {description = "Build libMediaPlayerBackports.dylib, for an application that answers lock-screen and headset remote-control commands through MPRemoteCommandCenter; the release has no MediaPlayer.framework command surface, but it has the older mechanism the new one is documented to sit above - UIEventTypeRemoteControl, delivered to the responder chain with a UIEventSubtypeRemoteControl* subtype since iOS 4.0 - so play/pause/stop/toggle/next/previous/seek map to their old-style subtypes for real. changePlaybackPositionCommand and the feedback/rating/language-option commands have no old-style event to answer to, so they are real, addressable command objects that never fire, honestly, not fabricated ones.", default = false, type = "boolean"})

    add_configs("avkit", {description = "Build libAVKitBackports.dylib, for an application that plays video in an AVPlayerViewController, an AVPlayerLayer with controls of the port's own that writes the now playing information through MediaPlayer, or floats a video mini-player through AVPictureInPictureController; AVKit.framework does not exist at all on this release, and neither does any cross-app window-compositing surface a third-party dylib could draw into, so this is an in-app floating window only - the real AVPlayerLayer is reparented into a draggable window above the host app's own view hierarchy, keeps playing for real, and is reparented back on -stopPictureInPicture. It does not persist once the host app leaves the foreground, the one dimension a real SpringBoard-side companion (the kind CallKitBackports' CharonCallScreen already models for its own call screen) would be needed for and this port does not build. It builds libUIKitBackports.dylib as well, whose transition coordinator the full screen presentation hands to the delegate.", default = false, type = "boolean"})

    add_configs("messageui", {description = "Build libMessageUIBackports.dylib, for an application that composes a message or a mail through MessageUI; what the release's own compose controller can carry is read off its metadata, so +canSendSubject and +canSendAttachments answer for this release rather than for a constant, and the two collaboration factories answer NO because the release's composers have no row to insert one into.", default = false, type = "boolean"})
    add_configs("securityui", {description = "Build libSecurityUIBackports.dylib, for an application that shows the certificate of a SecTrustRef in a sheet with SFCertificatePresentation; the sheet is the port's own, its lines read out of the trust with the Security calls this release already carries.", default = false, type = "boolean"})
    add_configs("usernotificationsui", {description = "Build libUserNotificationsUIBackports.dylib, for an extension that reports its notification content and its media state through NSExtensionContext; iOS 6 runs no extension host at all, so what the extension states is kept and the messages to the host say once that there is none.", default = false, type = "boolean"})
    add_configs("notificationcenter", {description = "Build libNotificationCenterBackports.dylib, for an application that records what its Today widgets have to show through NCWidgetController and draws them with the widget vibrancy effects; iOS 6 has no Notification Center, so the record is real and read back and nothing ever asks a widget to refresh.", default = false, type = "boolean"})
    add_configs("messages", {description = "Build libMessagesBackports.dylib, for an application that names the message classes of iOS 10 - MSMessage, MSMessageLayout and its template subclass, MSSession - and for one that gives MFMessageComposeViewController a message to compose; every member of them is a value the sender set and the receiver reads, kept and answered back, and a message answers isPending YES throughout because this release has no iMessage service, no conversation and no Messages extension host to send one through.", default = false, type = "boolean"})
    add_configs("metrickit", {description = "Build libMetricKitBackports.dylib, for an application that reads the metrics and diagnostics the system vends: every value class of the framework with its dictionary and JSON representations and its archiving, the manager with a real subscriber list and a real payload store under Application Support, and the two extended-launch measurements the port can really take. Nothing on this release samples an application, so every metric the port hands over is one the application itself wrote into the store or the port measured.", default = false, type = "boolean"})

    on_load("iphoneos", function (package)
        package:add("links", table.join((package:config("uikit") or package:config("avkit") or package:config("usernotificationsui") or package:config("notificationcenter")) and {"UIKitBackports"} or {}, package:config("corelocation") and {"CoreLocationBackports"} or {}, package:config("coredata") and {"CoreDataBackports"} or {}, package:config("security") and {"SecurityBackports"} or {}, package:config("avfoundation") and {"AVFoundationBackports"} or {}, package:config("avfaudio") and {"AVFAudioBackports"} or {}, package:config("webkit") and {"WebKitBackports"} or {}, (package:config("graphics") or package:config("avfoundation")) and {"GraphicsBackports"} or {}, package:config("localauthentication") and {"LocalAuthenticationBackports"} or {}, (package:config("safariservices") or package:config("authenticationservices")) and {"SafariServicesBackports"} or {}, package:config("authenticationservices") and {"AuthenticationServicesBackports"} or {}, package:config("backgroundtasks") and {"BackgroundTasksBackports"} or {}, package:config("photos") and {"PhotosBackports"} or {}, package:config("gamecontroller") and {"GameControllerBackports"} or {}, package:config("vision") and {"VisionBackports"} or {}, package:config("metal") and {"MetalBackports"} or {}, package:config("metalkit") and {"MetalKitBackports"} or {}, package:config("coretelephony") and {"CoreTelephonyBackports"} or {}, (package:config("accelerate") or package:config("avfoundation")) and {"AccelerateBackports"} or {}, package:config("callkit") and {"CallKitBackports"} or {}, package:config("contacts") and {"ContactsBackports"} or {}, package:config("corespotlight") and {"CoreSpotlightBackports"} or {}, package:config("pushkit") and {"PushKitBackports"} or {}, package:config("opengles") and {"OpenGLESBackports"} or {}, package:config("javascriptcore") and {"JavaScriptCoreBackports"} or {}, package:config("scenekit") and {"SceneKitBackports"} or {}, package:config("mediaplayer") and {"MediaPlayerBackports"} or {}, package:config("messageui") and {"MessageUIBackports"} or {}, package:config("securityui") and {"SecurityUIBackports"} or {}, package:config("usernotificationsui") and {"UserNotificationsUIBackports"} or {}, package:config("notificationcenter") and {"NotificationCenterBackports"} or {}, package:config("messages") and {"MessagesBackports"} or {}, package:config("metrickit") and {"MetricKitBackports"} or {}, package:config("avkit") and {"AVKitBackports"} or {}, package:config("mapkit") and {"MapKitBackports"} or {}, package:config("passkit") and {"PassKitBackports"} or {}, package:config("carplay") and {"CarPlayBackports"} or {}, package:config("network") and {"NetworkBackports"} or {}, {"FoundationBackports"}, package:config("intents") and {"IntentsBackports"} or {}))
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
        local libraries = table.join(package:config("network") and {"NetworkBackports"} or {}, {"FoundationBackports"}, (package:config("uikit") or package:config("avkit") or package:config("usernotificationsui") or package:config("notificationcenter")) and {"UIKitBackports"} or {},
                                     package:config("corelocation") and {"CoreLocationBackports"} or {},
                                     package:config("coredata") and {"CoreDataBackports"} or {},
                                     package:config("security") and {"SecurityBackports"} or {},
                                     (package:config("avfoundation") or package:config("avfaudio")) and {"AVFoundationBackports"} or {},
                                     package:config("avfaudio") and {"AVFAudioBackports"} or {},
                                     package:config("webkit") and {"WebKitBackports"} or {},
                                     (package:config("graphics") or package:config("avfoundation") or package:config("avfaudio")) and {"GraphicsBackports"} or {},
                                     package:config("localauthentication") and {"LocalAuthenticationBackports"} or {},
                                     (package:config("safariservices") or package:config("authenticationservices")) and {"SafariServicesBackports"} or {},
                                     package:config("authenticationservices") and {"AuthenticationServicesBackports"} or {},
                                     package:config("backgroundtasks") and {"BackgroundTasksBackports"} or {},
                                     package:config("photos") and {"PhotosBackports"} or {},
                                     package:config("gamecontroller") and {"GameControllerBackports"} or {},
                                     package:config("vision") and {"VisionBackports"} or {},
                                     package:config("metal") and {"MetalBackports"} or {},
                                     package:config("metalkit") and {"MetalKitBackports"} or {},
                                     package:config("opengles") and {"OpenGLESBackports"} or {},
                                     package:config("coretelephony") and {"CoreTelephonyBackports"} or {},
                                     (package:config("accelerate") or package:config("avfoundation") or package:config("avfaudio")) and {"AccelerateBackports"} or {},
                                     package:config("callkit") and {"CallKitBackports"} or {},
                                     package:config("contacts") and {"ContactsBackports"} or {},
                                     package:config("corespotlight") and {"CoreSpotlightBackports"} or {},
                                     package:config("pushkit") and {"PushKitBackports"} or {},
                                     package:config("javascriptcore") and {"JavaScriptCoreBackports"} or {},
                                     package:config("scenekit") and {"SceneKitBackports"} or {},
                                     package:config("mediaplayer") and {"MediaPlayerBackports"} or {},
                                     package:config("messageui") and {"MessageUIBackports"} or {},
                                     package:config("messages") and {"MessagesBackports"} or {},
                                     package:config("metrickit") and {"MetricKitBackports"} or {},
                                     package:config("securityui") and {"SecurityUIBackports"} or {},
                                     package:config("usernotificationsui") and {"UserNotificationsUIBackports"} or {},
                                     package:config("notificationcenter") and {"NotificationCenterBackports"} or {},
                                     package:config("avkit") and {"AVKitBackports"} or {},
                                     package:config("intents") and {"IntentsBackports"} or {},
                                     package:config("mapkit") and {"MapKitBackports"} or {},
                                     package:config("passkit") and {"PassKitBackports"} or {},
                                     package:config("carplay") and {"CarPlayBackports"} or {})
        local common = {root = package:scriptdir(), architecture = package:arch(), deployment = deployment, sdkdir = toolchain:config("sdkdir"),
                        cc = assert(toolchain:tool("cc"), "the apple-ios toolchain names no compiler for " .. package:arch()),
                        ld = assert(linker, "the apple-ios toolchain names no ld64 for " .. package:arch()), libraries = libraries,
                        archives = {box2d = {linkdir = package:dep("box2d"):installdir("lib"), link = "Box2D", includedir = package:dep("box2d"):installdir("include")}}}
        -- no width here on purpose: on_install runs inside a job of xmake's own, and
        -- backports.lua's width() sees that and compiles one unit at a time, for this call and for
        -- write_deb() below, without either of them having to remember
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
