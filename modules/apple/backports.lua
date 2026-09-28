import("macho")
import("dyld")
import("firmware")
import("signing")
import("objc")
import("core.base.json")
import("core.base.scheduler")
import("cache")

-- A library stands after every library it names in `libraries`: link() finds those in the output folder, so they are built first.
LIBRARIES = {
    -- libicucore carries the four udtitvfmt_* entry points NSDateIntervalFormatter is built on, exported by the
    -- release from iOS 5.0 on and by none before it, so the class floor is 5.0; the imports are weak, so a
    -- release whose libicucore lacks them binds NULL and the class answers nil rather than faulting.
    {name = "FoundationBackports", folder = "Foundation", frameworks = {"Foundation", "CoreFoundation", "SystemConfiguration"}, libraries = {"icucore"}},
    {name = "GraphicsBackports", folder = "Graphics", frameworks = {"CoreGraphics", "CoreImage", "CoreVideo", "ImageIO", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "UIKitBackports", folder = "UIKit", frameworks = {"UIKit", "Foundation", "CoreGraphics", "QuartzCore", "MobileCoreServices", "ImageIO"}, libraries = {"FoundationBackports", "GraphicsBackports"}, archives = {"box2d"}},
    {name = "CoreLocationBackports", folder = "CoreLocation", frameworks = {"CoreLocation", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "CoreDataBackports", folder = "CoreData", frameworks = {"CoreData", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "SecurityBackports", folder = "Security", frameworks = {"Security", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "AccelerateBackports", folder = "Accelerate", frameworks = {"Accelerate", "CoreGraphics", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "AVFoundationBackports", folder = "AVFoundation", frameworks = {"AVFoundation", "CoreMedia", "CoreVideo", "AudioToolbox", "CoreImage", "ImageIO", "CoreGraphics", "QuartzCore", "Accelerate", "UIKit", "Foundation"}, libraries = {"FoundationBackports", "GraphicsBackports", "AccelerateBackports"}},
    {name = "AVFAudioBackports", folder = "AVFAudio", frameworks = {"AudioToolbox", "CoreAudio", "AVFoundation", "UIKit", "Foundation", "Accelerate", "QuartzCore"}, libraries = {"FoundationBackports", "GraphicsBackports", "AccelerateBackports", "AVFoundationBackports"}},
    {name = "WebKitBackports", folder = "WebKit", frameworks = {"UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "LocalAuthenticationBackports", folder = "LocalAuthentication", frameworks = {"Foundation"}, libraries = {"FoundationBackports"}},
    {name = "OpenGLESBackports", folder = "OpenGLES", frameworks = {"OpenGLES", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "SafariServicesBackports", folder = "SafariServices", frameworks = {"UIKit", "Foundation", "CoreGraphics", "QuartzCore", "MobileCoreServices"}, libraries = {"FoundationBackports"}},
    {name = "AuthenticationServicesBackports", folder = "AuthenticationServices", frameworks = {"UIKit", "Foundation"}, libraries = {"FoundationBackports", "SafariServicesBackports"}},
    {name = "BackgroundTasksBackports", folder = "BackgroundTasks", frameworks = {"UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "PhotosBackports", folder = "Photos", frameworks = {"AssetsLibrary", "AVFoundation", "CoreLocation", "CoreGraphics", "ImageIO", "MobileCoreServices", "UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "GameControllerBackports", folder = "GameController", frameworks = {"UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "VisionBackports", folder = "Vision", frameworks = {"CoreGraphics", "CoreImage", "CoreVideo", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "MetalBackports", folder = "Metal", frameworks = {"QuartzCore", "CoreGraphics", "OpenGLES", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "MetalKitBackports", folder = "MetalKit", frameworks = {"UIKit", "QuartzCore", "CoreGraphics", "OpenGLES", "Foundation"}, libraries = {"FoundationBackports", "MetalBackports"}},
    {name = "CoreTelephonyBackports", folder = "CoreTelephony", frameworks = {"CoreTelephony", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "CallKitBackports", folder = "CallKit", frameworks = {"CoreTelephony", "AVFoundation", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "ContactsBackports", folder = "Contacts", frameworks = {"AddressBook", "CoreFoundation", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "HomeKitBackports", folder = "HomeKit", frameworks = {"CoreLocation", "Foundation"}, libraries = {"FoundationBackports"}, archives = {"monocypher"}, c_archives = {"monocypher"}},
    {name = "CoreSpotlightBackports", folder = "CoreSpotlight", frameworks = {"Foundation"}, libraries = {"FoundationBackports"}},
    {name = "PushKitBackports", folder = "PushKit", frameworks = {"UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "JavaScriptCoreBackports", folder = "JavaScriptCore", frameworks = {"JavaScriptCore", "CoreGraphics", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "SceneKitBackports", folder = "SceneKit", frameworks = {"UIKit", "QuartzCore", "OpenGLES", "CoreGraphics", "Foundation"}, libraries = {"FoundationBackports", "OpenGLESBackports"}},
    {name = "MediaPlayerBackports", folder = "MediaPlayer", frameworks = {"MediaPlayer", "UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "MessageUIBackports", folder = "MessageUI", frameworks = {"MessageUI", "MobileCoreServices", "UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "MessagesBackports", folder = "Messages", frameworks = {"MessageUI", "Messages", "UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "MetricKitBackports", folder = "MetricKit", frameworks = {"MetricKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "SensorKitBackports", folder = "SensorKit", frameworks = {"SensorKit", "CoreMedia", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "SecurityUIBackports", folder = "SecurityUI", frameworks = {"SecurityUI", "Security", "UIKit", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "UserNotificationsUIBackports", folder = "UserNotificationsUI", frameworks = {"UserNotificationsUI", "UserNotifications", "UIKit", "Foundation"}, libraries = {"FoundationBackports", "UIKitBackports"}},
    {name = "NotificationCenterBackports", folder = "NotificationCenter", frameworks = {"NotificationCenter", "UIKit", "Foundation"}, libraries = {"FoundationBackports", "UIKitBackports"}},
    {name = "AVKitBackports", folder = "AVKit", frameworks = {"UIKit", "AVFoundation", "CoreMedia", "CoreVideo", "CoreImage", "MediaPlayer", "QuartzCore", "CoreGraphics", "Foundation"}, libraries = {"FoundationBackports", "UIKitBackports"}},
    {name = "MapKitBackports", folder = "MapKit", frameworks = {"MapKit", "UIKit", "CoreGraphics", "CoreLocation", "QuartzCore", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "PassKitBackports", folder = "PassKit", frameworks = {"PassKit", "UIKit", "CoreGraphics", "Foundation"}, libraries = {"FoundationBackports"}},
    {name = "CarPlayBackports", folder = "CarPlay", frameworks = {"CarPlay", "MapKit", "UIKit", "CoreGraphics", "CoreTelephony", "Foundation"}, libraries = {"FoundationBackports"}},
    -- Network.framework does not exist on the releases this port covers, so this library is the only place its
    -- connection surface can be, and it reports the path through the Foundation library's path monitor.
    {name = "NetworkBackports", folder = "Network", frameworks = {"Network", "Foundation", "Security"}, libraries = {"FoundationBackports"}},
    -- Intents arrives with iOS 8 and the armv7 ladder ends at 10.3.4, so no release this package
    -- covers carries it: every band builds this library whole. It links UIKit because an Intents
    -- image is the application's own image and UIKit is where the asset catalogue is on every
    -- release below, and CoreLocation because INPlacemarkResolutionResult resolves a CLPlacemark.
    {name = "IntentsBackports", folder = "Intents", frameworks = {"Intents", "UIKit", "CoreLocation", "Foundation"}, libraries = {"FoundationBackports"}, archives = {"charon-coding"}, c_archives = {"charon-coding"}},
    -- IntentsUI is the button and the two controllers an application shows to add or edit a
    -- shortcut, so it is a library of its own: a port that only donates interactions never draws
    -- one, and a daemon has no UIKit in its process to begin with. It needs the Intents classes
    -- the controllers hold, and it draws with UIKit.
    -- Accessibility arrived with iOS 3, so the release already has libAccessibility.dylib and its
    -- C API; what it does not have is the Objective-C classes the SDK of 26.2 declares on top of
    -- it, and this library is those. The release carries none of the 30 (measured against the
    -- 6.1.3 armv7 cache, with a control), so every band builds it whole and nothing in it is a
    -- class of its own that the release would answer.
    {name = "AccessibilityBackports", folder = "Accessibility", frameworks = {"Accessibility", "Foundation", "CoreGraphics"}, libraries = {"FoundationBackports"}, archives = {"charon-coding"}, c_archives = {"charon-coding"}},
    {name = "IntentsUIBackports", folder = "IntentsUI", frameworks = {"IntentsUI", "Intents", "UIKit", "Foundation", "CoreGraphics"}, libraries = {"FoundationBackports", "IntentsBackports"}},
    {name = "ARKitBackports", folder = "ARKit", frameworks = {"ARKit", "AVFoundation", "CoreMotion", "CoreLocation", "CoreMedia", "CoreVideo", "CoreGraphics", "ImageIO", "QuartzCore", "OpenGLES", "UIKit", "Foundation"}, libraries = {"FoundationBackports", "AVFoundationBackports", "SceneKitBackports"}},
    {name = "HealthKitBackports", folder = "HealthKit", frameworks = {"UIKit", "Foundation"}, libraries = {"FoundationBackports"}, system = {"sqlite3"}}
}
PACKAGE = "org.charon.apple-backports"
INSTALL_FOLDER = "/usr/lib/charon/" .. PACKAGE
COMPATIBLE = {armv7 = {"armv7", "armv7s"}, armv7s = {"armv7s"}, arm64 = {"arm64"}}

function libraries()
    return LIBRARIES
end

function package_name()
    return PACKAGE
end

function compatible(architecture)
    return COMPATIBLE[architecture] or {architecture}
end

function held_cache(architecture, release)
    for _, candidate in ipairs(compatible(architecture)) do
        local held = dyld.held_source(path.join(dyld.root(), release), candidate)
        if held then
            return held
        end
    end
end

-- A backport holds more than the API it carries: Charon's own helpers, the
-- classes it invents for itself and the ivars of the classes it implements.
-- None of that is API - a release that already has a class exports its own
-- ivars, not these - so it is neither weighed against a release nor exported.
-- The store key of each object this process placed or compiled (object_key), and the symbols read
-- out of those objects, by key.
local KEYS, SYMBOLS = {}, {}

local function internal_symbol(name)
    if name:startswith("_OBJC_IVAR_$_") or name:find("$shim", 1, true) then
        return true
    end
    local bare = name:match("^_OBJC_%u*CLASS_%$_(.+)$") or name:match("^_(.+)$") or name
    return bare:startswith("charon_") or bare:startswith("Charon")
end

local function symbols_where(file, wanted, kind)
    -- an object of the store never changes under its key, and a gate reads each one's symbols three
    -- times over (minimums, the release check, the link)
    local memo = kind and KEYS[file] and (KEYS[file] .. kind)
    if memo and SYMBOLS[memo] then
        return SYMBOLS[memo]
    end
    local found = symbols_of(file, wanted)
    if memo then
        SYMBOLS[memo] = found
    end
    return found
end

function symbols_of(file, wanted)
    local data = macho.read(file)
    local found = {}
    for _, image in ipairs(macho.images(data)) do
        if image.symtab then
            local symoff, nsyms, stroff = image.symtab[1], image.symtab[2], image.symtab[3]
            local entry = image.wide and 16 or 12
            for index = 0, nsyms - 1 do
                local strx, kind, _, _, value = string.unpack(image.wide and "<I4BBI2I8" or "<I4BBI2I4", data, image.base + symoff + index * entry + 1)
                if wanted(kind, value) then
                    local finish = data:find("\0", image.base + stroff + strx + 1, true)
                    found[data:sub(image.base + stroff + strx + 1, finish - 1)] = true
                end
            end
        end
    end
    return table.orderkeys(found)
end

local function defined_symbols(file, hidden)
    return symbols_where(file, function (kind)
        return kind & 0xE0 == 0 and kind & 0x0E == 0x0E and (hidden or (kind & 0x10 == 0 and kind & 0x01 ~= 0))
    end, hidden and "hidden" or "defined")
end

-- What an object needs another file to define (nm -u): external, undefined, and not a common symbol,
-- which an object defines itself.
local function undefined_symbols(file)
    return symbols_where(file, function (kind, value)
        return kind & 0xE0 == 0 and kind & 0x0E == 0 and kind & 0x01 ~= 0 and value == 0
    end, "undefined")
end

local function exported_symbols(file)
    local found = {}
    for _, symbol in ipairs(defined_symbols(file)) do
        if not internal_symbol(symbol) then
            table.insert(found, symbol)
        end
    end
    return found
end

-- The clang driver a build runs: the one it was given, or the host's.
-- The archive a name in a library's list refers to.
--
-- The name in a library's list is the **alias** it was written with ("charon-coding"), and the
-- table the build is handed is keyed by the **package** the resolve turned that alias into
-- ("charon@charon-coding 1.0.0"), because that is what the caller that resolves packages can
-- know. So the lookup tries the alias first and the package form second - which is what the
-- `charon@` branch was there for, and it had no caller until compile() started needing the
-- include directory of an archive whose API is C (measured: with the alias-only lookup the header
-- is not found and the Accessibility library does not compile). The recipe's own `common` table
-- keys by the alias, so both spellings occur, and this is where they are joined.
function archive_of(archives, name)
    if not archives then
        return nil
    end
    if archives[name] then
        return archives[name]
    end
    for key, archive in pairs(archives) do
        if (key:match("^(%S+)") or key) == "charon@" .. name then
            return archive
        end
    end
    return nil
end

local function driver(opt, arguments)
    if opt.cc then
        return opt.cc, arguments
    end
    return "xcrun", table.join({"clang"}, arguments)
end

-- What a compile runs through is apple.cache, which the lift reads the SDK with as well: the
-- backports build and the lift are the two things here that run a compiler thousands of times,
-- and a second copy of "find ccache on the path" is a second thing to keep right. What the cache
-- is and what it was measured to do is written there.
local function clang(opt, arguments, objective_c)
    local given = {"-target", opt.triple, "-isysroot", opt.sdkdir}
    if objective_c then
        table.insert(given, "-fobjc-arc")
        if dyld.compare_versions(opt.deployment, "5.0") < 0 then
            table.join2(given, {"-Xclang", "-fobjc-runtime-has-weak"})
        end
    end
    table.join2(given, arguments)
    return driver(opt, given)
end

-- The object store (opt.store): an object kept under a key of everything its compile reads that can
-- change, so that a build hands back an object it already has without starting a process. A ccache
-- hit is not that: it is a process, which hashes the preprocessor's inputs, stats every SDK header
-- it read and copies the object out - measured 30-60 ms a unit under the fleet's load, 2331 units a
-- gate at four cores, which was the whole of the 21-29 s every gate spent "compiling" a tree nothing
-- in had changed. The key is the compiler, its arguments with the checkout's own path taken out (as
-- ccache's base_dir takes it out, so every worktree shares one entry), the source, and every header
-- of the checkout the source reaches through #include/#import, by content. Headers outside the
-- checkout - the SDK, the compiler's own, an archive's include folder - sit under installdirs whose
-- names are the hash of what they hold, and are in the key through the paths in the arguments.
-- A directive the scan cannot read (a macro in place of a name) leaves the unit out of the store,
-- compiled every time as before. Reading a directive in a block the preprocessor skips only adds a
-- header to the key, which costs a rebuild and never a stale object.
local SCANNED, CONTENT = {}, {}

local function directives(file)
    local found = SCANNED[file]
    if found == nil then
        found = {}
        for line in io.readfile(file):gmatch("[^\n]+") do
            local rest = line:match("^%s*#%s*include_next(.*)$") or line:match("^%s*#%s*include(.*)$") or line:match("^%s*#%s*import(.*)$")
            if rest then
                local open, name = rest:match('^%s*(["<])([^">]+)[">]')
                if not open then
                    found = false
                    break
                end
                table.insert(found, {quoted = open == '"', name = name})
            end
        end
        SCANNED[file] = found
    end
    return found
end

local function content(file)
    CONTENT[file] = CONTENT[file] or hash.strhash128(io.readfile(file))
    return CONTENT[file]
end

-- Every header of the checkout the source reaches, in the order first reached, or nil when a
-- directive on the way cannot be read. A quoted name is looked for beside the file that names it and
-- then in the -I folders, an angled one in the -I folders, as clang looks; every folder that holds
-- the name counts, not only the first, so a header shadowed by another is still in the key.
local function reached(source, folders)
    local seen, order = {}, {}
    local function visit(file)
        local found = directives(file)
        if not found then
            return false
        end
        for _, include in ipairs(found) do
            local candidates = include.quoted and {path.directory(file)} or {}
            table.join2(candidates, folders)
            for _, folder in ipairs(candidates) do
                local header = path.normalize(path.join(folder, include.name))
                if not seen[header] and os.isfile(header) then
                    seen[header] = true
                    table.insert(order, header)
                    if visit(header) == false then
                        return false
                    end
                end
            end
        end
        return true
    end
    if visit(source) == false then
        return nil
    end
    return order
end

local OWN_TEXT

-- This file's text, by content: what a measurement or a link kept in the store was computed by.
local function own_text()
    OWN_TEXT = OWN_TEXT or hash.strhash128(io.readfile(path.join(os.scriptdir(), "backports.lua")))
    return OWN_TEXT
end

-- What the compiler and the linker read from the environment besides their arguments: the include
-- paths clang takes from the environment and the SDK and deployment the driver falls back on. A key
-- without them hands back what a different environment built (measured: a header found only on
-- CPATH, changed between two runs, and the second run took the first run's object).
local ENVIRONMENT = {"CPATH", "C_INCLUDE_PATH", "OBJC_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJCPLUS_INCLUDE_PATH",
                     "SDKROOT", "DEVELOPER_DIR", "IPHONEOS_DEPLOYMENT_TARGET", "MACOSX_DEPLOYMENT_TARGET",
                     "CCC_OVERRIDE_OPTIONS", "LIBRARY_PATH", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH"}
local function environment()
    local parts = {}
    for _, name in ipairs(ENVIRONMENT) do
        local value = os.getenv(name)
        if value then
            table.insert(parts, name .. "=" .. value)
        end
    end
    return table.concat(parts, "\n")
end

function object_key(opt, program, arguments, source, object)
    if not opt.store or not opt.root then
        return nil
    end
    local checkout = path.normalize(path.join(path.absolute(opt.root), "..", "..", ".."))
    local function portable(text)
        local at = text:find(checkout, 1, true)
        return at and text:sub(1, at - 1) .. "@checkout" .. portable(text:sub(at + #checkout)) or text
    end
    local folders = {}
    for index, argument in ipairs(arguments) do
        local folder = argument:match("^%-I(.+)$") or (argument == "-I" and arguments[index + 1])
        if folder then
            folder = path.normalize(path.absolute(folder))
            if folder:startswith(checkout) then
                table.insert(folders, folder)
            end
        end
    end
    local headers = reached(source, folders)
    if not headers then
        return nil
    end
    -- The arguments are the whole of what this file asks of the compiler, so its own text is not here:
    -- an edit that changes a compile changes its arguments.
    local parts = {"charon-object-2", program, environment()}
    for _, argument in ipairs(arguments) do
        table.insert(parts, argument == object and "@object" or portable(argument))
    end
    table.insert(parts, content(source))
    for _, header in ipairs(headers) do
        table.insert(parts, portable(header) .. "=" .. content(header))
    end
    return hash.strhash128(table.concat(parts, "\n"))
end

-- Only C is compiled hidden. The classes of a backport are the API it carries,
-- and the headers of the release declare a Foundation class without the
-- visibility UIKit gives its own, so -fvisibility=hidden makes clang hide every
-- Foundation class it implements: the library exports nothing, a port links its
-- classes as the weak imports that are NULL on the release, and the device says
-- only that the program failed. What the library must not export it hides at
-- the link, where a hidden symbol can still be named.
--
-- Objective-C++ is how a backport reaches a C++ library it links in (LIBRARIES' archives). The
-- archives are built without RTTI, so a class derived here from one of theirs has none either, and
-- the inline functions of their headers stay hidden, as the archives' own symbols are. Every .mm
-- backport is compiled so: one that needs RTTI for another reason (typeid, dynamic_cast) cannot
-- have it here.
-- The flags one source is compiled with. A job may add include roots of its own: a source this build
-- generated sits in the build directory, and its quoted import reaches a header of the tree only when the
-- tree is on the path.
local function unit(opt, source, object)
    -- The source, absolute, and relative to this package rather than to wherever xmake happens to
    -- be: path.absolute() on its own resolves a relative source against the working directory,
    -- which inside package:on_install is xmake's own and not the checkout, so a caller that passed
    -- "UIKit/Foo.mm" would be looked for under xmake's directory. Every caller here already passes
    -- path.join(opt.root, ...), so this is the identity for all of them; it is here for the next one.
    if not source:startswith("/") then
        source = path.join(opt.root, source)
    end
    -- This does NOT close the one-object residue, and nothing a caller passes can. ccache rewrites
    -- the compiler's own -c argument when base_dir is set - heavy.sh sets it in the cache's
    -- ccache.conf - and hands the object back as that run wrote it, so a cached build records the
    -- relative spelling whatever the caller passed and an uncached one the absolute. Measured the
    -- same file three ways straight through ccache, so nothing else was in the way: no cache and
    -- ccache with base_dir unset are byte for byte the same and both record the absolute path;
    -- only base_dir set gives the relative one. That rewrite is the price of the cross-worktree
    -- sharing hash_dir = false buys, and -ffile-prefix-map, which rules/apple-ios already applies
    -- to this repository's own targets, is the follow-up that would collapse both spellings -
    -- measured, and it does not: the map rewrites an absolute spelling and ccache hands the
    -- compiler a relative one, so the gap falls from 84 bytes to 8 and stops
    -- (band-api-prefixmap, d2e15520). What the two lines above close is the other half: a caller
    -- that spelled the source two ways would be two objects under one key, and that is no longer
    -- possible.
    local objective_c = not source:endswith(".c")
    local arguments = {"-Os", "-g0", "-Wall", "-Wno-unguarded-availability-new", "-Wno-unguarded-availability"}
    if objective_c then
        table.insert(arguments, "-Werror=objc-missing-property-synthesis")
    else
        table.insert(arguments, "-fvisibility=hidden")
    end
    if source:endswith(".mm") then
        table.join2(arguments, {"-fno-rtti", "-fvisibility-inlines-hidden"})
    end
    -- Every archive's headers, for every file. A C archive is used by C files, so its headers
    -- cannot wait for a .mm; and a C++ archive's headers are reached from a plain .m too, because
    -- a header of ours can include one of them - measured at UIKit's CharonDynamics.h:15, which
    -- includes <Box2D/Box2D.h> and is included from a .m, so the narrowing to .mm that a review
    -- asked for breaks the 4.3 gate with "Box2D/Box2D.h file not found".
    --
    -- The width that costs is real and is the reason it is written this way: every library's
    -- sources compile with every archive's include directory on the path. That is a few -I flags a
    -- search walks over, and the alternative measured is a build that does not compile.
    for _, name in ipairs(table.orderkeys(opt.archives or {})) do
        table.insert(arguments, "-I" .. opt.archives[name].includedir)
    end
    -- __FILE__ spelled from the checkout, not with it: an object that names its own source (UIDynamicAnimator.mm's
    -- assertion handler) otherwise carries the path of the worktree that built it, which the store's key leaves out on
    -- purpose so every worktree shares one entry - measured, two worktrees, one key, two objects differing in that path.
    if opt.root then
        local checkout = path.normalize(path.join(path.absolute(opt.root), "..", "..", ".."))
        table.insert(arguments, "-fmacro-prefix-map=" .. checkout .. "/=")
    end
    local program, arguments = clang(opt, table.join(arguments, {"-c", source, "-o", object}), objective_c)
    local key = object_key(opt, program, arguments, source, object)
    KEYS[object] = key
    return program, arguments, key and path.join(opt.store, key:sub(1, 2), key .. ".o")
end

local function store_folder(folder)
    try { function () os.mkdir(folder) end }
    assert(os.isdir(folder), "cannot create the store folder " .. folder)
end

local function place(object, stored)
    -- Removed first either way: the object may be a link into the store from an earlier run, and a
    -- compile must not write through it.
    os.tryrm(object)
    if stored and os.isfile(stored) then
        os.ln(stored, object)
        -- the store is swept by age (sweep_store), and an entry a build still takes is not old
        os.touch(stored)
        return true
    end
    return false
end

function compile_arguments(opt, source)
    local objective_c = not source:endswith(".c")
    local arguments = {"-Os", "-g0", "-Wall", "-Wno-unguarded-availability-new", "-Wno-unguarded-availability"}
    for _, folder in ipairs(opt.includes or {}) do
        table.insert(arguments, "-I" .. folder)
    end
    if objective_c then
        table.insert(arguments, "-Werror=objc-missing-property-synthesis")
    else
        table.insert(arguments, "-fvisibility=hidden")
    end
    if source:endswith(".mm") then
        table.join2(arguments, {"-fno-rtti", "-fvisibility-inlines-hidden"})
    end
    -- Every archive's headers, for every file. A C archive is used by C files, so its headers
    -- cannot wait for a .mm; and a C++ archive's headers are reached from a plain .m too, because
    -- a header of ours can include one of them - measured at UIKit's CharonDynamics.h:15, which
    -- includes <Box2D/Box2D.h> and is included from a .m, so the narrowing to .mm that a review
    -- asked for breaks the 4.3 gate with "Box2D/Box2D.h file not found".
    --
    -- The width that costs is real and is the reason it is written this way: every library's
    -- sources compile with every archive's include directory on the path. That is a few -I flags a
    -- search walks over, and the alternative measured is a build that does not compile.
    for _, name in ipairs(table.orderkeys(opt.archives or {})) do
        table.insert(arguments, "-I" .. opt.archives[name].includedir)
    end
    -- __FILE__ spelled from the checkout, not with it: an object that names its own source (UIDynamicAnimator.mm's
    -- assertion handler) otherwise carries the path of the worktree that built it, which the store's key leaves out on
    -- purpose so every worktree shares one entry - measured, two worktrees, one key, two objects differing in that path.
    if opt.root then
        local checkout = path.normalize(path.join(path.absolute(opt.root), "..", "..", ".."))
        table.insert(arguments, "-fmacro-prefix-map=" .. checkout .. "/=")
    end
    return arguments, objective_c
end

function compile(opt, source, object)
    local flags, objective_c = compile_arguments(opt, source)
    local program, arguments = clang(opt, table.join(flags, {"-c", source, "-o", object}), objective_c)
    -- Through the cache, which is apple.cache: it puts the compiler in as the wrapper's first
    -- argument, because os.execv runs a name it cannot execute itself by splitting that name on
    -- spaces, and a checkout under a path with a space in it has to survive that. The link below
    -- goes through driver() and no cache: a cache holds compilations, not links.
    -- From the checkout: ccache (base_dir) hands the compiler every path under the tree relative to where it runs, and
    -- __FILE__ is then spelled from there - from the shared checkout it named the worktree (".agent-work/worktrees/<name>/
    -- packages/..."), which the store's key leaves out; from the checkout itself it is "packages/..." in every worktree.
    local program, argv = cache.wrapped(program, arguments)
    os.vrunv(program, argv, opt.root and {curdir = path.normalize(path.join(path.absolute(opt.root), "..", "..", ".."))} or nil)
    if stored then
        store_folder(path.directory(stored))
        local temporary = stored .. "." .. hash.strhash32(object .. os.mclock()) .. ".tmp"
        os.cp(object, temporary)
        os.mv(temporary, stored)
    end
    return true
end

-- The entries of the store no build has taken for older than seconds, removed: an entry is touched
-- each time a build takes it, so what goes is what no tree still builds. At most once an hour, since
-- a gate is every few minutes and a walk of the store is not free.
function sweep_store(store, seconds)
    -- The store comes from the environment (CHARON_OBJECT_STORE), and a stale value can name any
    -- folder: only what this file writes is removed, an object, a link, a measurement or an
    -- inventory named by its key (or the temporary of one a killed build left), in the four places
    -- it writes them, and nothing else under store is ever looked at.
    local KEY = string.rep("%x", 32)
    local kinds = {
        {"*", "*.o", "^" .. KEY .. "%.o"},
        {"links/*", "*.dylib", "^" .. KEY .. "%.dylib"},
        {"releases/*", "*.lua", "^" .. KEY .. "%.lua"},
        {"inventories", "*.lua", "^" .. KEY .. "%.lua"}}
    local mark = path.join(store, "swept")
    if not os.isdir(store) or (os.isfile(mark) and os.time() - os.mtime(mark) < 3600) then
        return
    end
    io.writefile(mark, "")
    local now, removed = os.time(), 0
    for _, kind in ipairs(kinds) do
        for _, file in ipairs(os.files(path.join(store, kind[1], kind[2] .. "*"))) do
            local name = path.filename(file)
            if name:match(kind[3] .. "$") or name:match(kind[3] .. "%.%x+%.tmp$") then
                if now - os.mtime(file) > seconds then
                    os.tryrm(file)
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

-- How many units this build may compile at once. The caller may lower it, and heavy.sh raises it
-- for the builds that are not already inside a job: a gate, release-split, the canon build, all of
-- which run from `xmake lua` as the only coroutine of their own.
--
-- One at a time it is, whatever the caller asked for, as soon as xmake is already running a job of
-- its own in this process - a package's on_install, and write_deb() called from it. A job runner
-- started from inside one never returns: measured, every object is written and the run then hangs
-- there for good, on a shared scheduler and on an isolated one alike. The test for that is here and
-- not on a call site, because there are two entries into compiled() from a package install and the
-- next caller would not remember: scheduler.co_count() is 1 for a script's own top level and 2
-- inside a job, so anything above 1 means a job is already driving this process.
local function width(opt)
    if scheduler.co_count() > 1 then
        return 1
    end
    if opt.width then
        return opt.width
    end
    return math.max(1, tonumber(os.getenv("FLEET_HEAVY_CPUS") or "") or 1)
end

-- The units the compiler has actually been run on since the counter was last read. A placed object
-- is not one of these: a unit the cache hands back is an object the build holds and a compile it
-- did not do, and the line build() prints has to say which of the two it is reporting.
local COMPILED

-- The units of a build, compiled. A backport unit is independent of every other one: what it
-- compiles is decided before any of them run, and the objects are only read afterwards, by the
-- link and by the checks that read symbols out of them. So they are handed to the same job runner
-- xmake builds its own targets with, which is what makes the count above a bound rather than a
-- hope - and which re-raises what a unit printed, so a unit that does not compile still fails the
-- build exactly as it did one at a time. Only the compiles run in parallel: the order the objects
-- are numbered in, which the link reads them in, is built before this and never touched here.
local function compile_all(opt, jobs)
    local count = width(opt)
    -- What the store already holds is placed here, in this coroutine, with no process started: only
    -- the rest is handed to the job runner.
    local missing = {}
    for _, job in ipairs(jobs) do
        local _, _, stored = unit(job.opt, job.source, job.object)
        if not place(job.object, stored) then
            table.insert(missing, job)
        end
    end
    COMPILED = COMPILED or 0
    if count <= 1 or #missing < 2 then
        for _, job in ipairs(missing) do
            if compile(job.opt, job.source, job.object, job.library) then
                COMPILED = COMPILED + 1
            end
        end
        return
    end
    import("async.runjobs")("backports", function (index)
        local job = missing[index]
        if compile(job.opt, job.source, job.object, job.library) then
            COMPILED = COMPILED + 1
        end
    end, {comax = count, total = #missing})
end

local function sections_of(file)
    local names = {}
    for _, image in ipairs(macho.images(macho.read(file))) do
        for _, section in ipairs(image.sections) do
            names[section.segment .. "," .. section.name] = true
        end
    end
    return names
end

function sources(root, library)
    local found = table.join(os.files(path.join(root, library.folder, "*.m")), os.files(path.join(root, library.folder, "*.mm")),
                             os.files(path.join(root, library.folder, "*.c")))
    table.sort(found)
    return found
end

-- The protocol metadata a framework carries, which the port does not: on Apple a framework's protocols are
-- in the framework, so NSProtocolFromString and -conformsToProtocol: work on a class an application never saw,
-- and the port emits a protocol's metadata only where a class adopts it. An implemented protocol row nothing
-- adopts is a row no build answers for, and check_registry holds it red (measured 2026-09-28: 73 such rows,
-- coordination/registry-gap-2026-09-28.tsv). So the build writes one object source per library per release
-- band - <Library>Protocols<release>.m - that names every protocol the band carries, which is what makes clang
-- emit __OBJC_PROTOCOL_$_<name> into the object. One file per band, so every symbol in it first appears in one
-- release and release-split has nothing to flag; one io.writefile per file, so no redirection can truncate it.
function protocol_sources(root, library, folder, umbrella)
    -- Only this library's own rows: a framework's rows live under registry/<folder>/, so the library whose
    -- folder is that framework is the one that carries them, and a framework no library builds (PhotosUI, whose
    -- protocols ride in PhotosBackports) is not read into any library at all. Reading the whole registry put all
    -- 73 rows into every library.
    local bands, floors_of = {}, {}
    for _, file in ipairs(table.join(os.files(path.join(root, "registry", library.folder, "*.json")),
                                 os.files(path.join(root, "registry", library.folder .. ".json")))) do
        local held = json.loadfile(file)
        if type(held) == "table" and held.entries == nil and #held == 0 then
            held = {entries = {}}
        end
        for _, entry in ipairs((held.entries or held)) do
            if entry.kind == "protocol" and entry.status == "implemented" then
                local introduced = entry.introduced or "0"
                bands[introduced] = bands[introduced] or {}
                table.insert(bands[introduced], entry.api)
                -- the file's floor is the highest minimum of its rows, as a source the registry places has
                if entry.minimum and (not floors_of[introduced] or dyld.compare_versions(entry.minimum, floors_of[introduced]) > 0) then
                    floors_of[introduced] = entry.minimum
                end
            end
        end
    end
    local written, floor = {}, {}
    for introduced, names in pairs(bands) do
        table.sort(names)
        local file = path.join(folder, library.name .. "Protocols" .. introduced .. ".m")
        local text = string.format([[// %sProtocols%s.m — written by modules/apple/backports.lua, not by hand.
// Every @protocol() below is named so clang emits __OBJC_PROTOCOL_$_<name> into this object, which is the
// metadata the release carries for that protocol in %s.framework itself. One file per release the rows
// arrived in, so every symbol here first appears in one release and release-split is clean.
#import "Charon%sProtocols.h"

static void charon_%s_protocols(void) __attribute__((used));
static void charon_%s_protocols(void)
{
]], library.name, introduced, library.name, library.folder, library.name, library.name)
        for _, name in ipairs(names) do
            text = text .. string.format("    (void)@protocol(%s);\n", name)
        end
        text = text .. "}\n"
        io.writefile(file, text)
        table.insert(written, file)
        floor[file] = floors_of[introduced]
    end
    table.sort(written)
    return written, floor
end

local function names_a_class(symbols)
    for _, symbol in ipairs(symbols) do
        if symbol:startswith("_OBJC_CLASS_$_") or symbol:startswith("_OBJC_METACLASS_$_") or symbol:startswith("_OBJC_IVAR_$_") then
            return true
        end
    end
    return false
end

-- A band neither keeps nor re-exports an object below its registry minimum (range.minimums, from
-- minimums() below, for the band's release range.release); those it names as left out, the third answer.
function band(release_exports, objects, arrived, range)
    local kept, reexported, left = {}, {}, {}
    for _, object in ipairs(objects) do
        local minimum = range and range.minimums[object]
        local symbols = exported_symbols(object)
        local present = {}
        for _, symbol in ipairs(symbols) do
            if release_exports[symbol] then
                table.insert(present, symbol)
            end
        end
        if minimum and dyld.compare_versions(range.release, minimum) < 0 then
            table.insert(left, object)
        elseif #present == 0 or (arrived and not names_a_class(present) and arrived(object)) then
            table.insert(kept, object)
        elseif #present == #symbols then
            table.join2(reexported, symbols)
        else
            local absent = {}
            for _, symbol in ipairs(symbols) do
                if not release_exports[symbol] then
                    table.insert(absent, symbol)
                end
            end
            raise("%s defines %s, which the release already exports, together with %s, which it does not; an object carries API that arrived in one release, so split it",
                  path.filename(object), table.concat(present, " "), table.concat(absent, " "))
        end
    end
    return kept, reexported, left
end

local function compiled(opt)
    local attach = path.join(opt.builddir, "objects", "attach.o")
    os.mkdir(path.directory(attach))
    -- the SDK these objects are compiled against, for tools/release-split.lua: which release first exports a symbol depends on
    -- which SDK's stubs say what library it belongs to, and guessing the SDK from what is installed answers for another build
    io.writefile(path.join(opt.builddir, "objects", "sdkdir"), opt.sdkdir)
    compile(opt, path.join(opt.root, "attach.c"), attach)
    local placed = floors(opt)
    local objects, origins, minimums = {}, {}, {}
    local pending = {}
    for _, library in ipairs(LIBRARIES) do
        objects[library.name] = {}
        -- the protocol metadata the framework carries and the port does not: one generated source per band
        local generated = path.join(opt.builddir, "protocols", library.folder)
        os.mkdir(generated)
        local written, floor = protocol_sources(opt.root, library, generated, library.frameworks[1])
        for _, source in ipairs(written) do
            local object = path.join(opt.builddir, "objects", library.folder, "protocols", path.filename(source) .. ".o")
            os.mkdir(path.directory(object))
            local job = table.join(opt, {includes = {path.join(opt.root, library.folder)}})
            -- compiled at its rows' registry minimum, as floors() compiles a placed source, and left out of every
            -- band below it: a framework's headers need not compile for a release its rows are not carried to
            -- (ARKit's ARSession.h declares a strong dispatch_queue_t, which is no object before iOS 6)
            local minimum = floor[source]
            if minimum and dyld.compare_versions(minimum, opt.deployment) > 0 then
                job = table.join(job, {deployment = minimum, triple = opt.architecture .. "-apple-ios" .. minimum})
                minimums[object] = minimum
            end
            pending[#pending + 1] = {opt = job, source = source, object = object}
            table.insert(objects[library.name], object)
            origins[object] = source
        end
        for _, source in ipairs(sources(opt.root, library)) do
            local object
            if placed[source] then
                object = placed[source].object
                minimums[object] = placed[source].minimum
            else
                object = path.join(opt.builddir, "objects", library.folder, path.basename(source) .. ".o")
                os.mkdir(path.directory(object))
                table.insert(pending, {opt = opt, source = source, object = object,
                                       library = library})
            end
            table.insert(objects[library.name], object)
            origins[object] = source
        end
    end
    compile_all(opt, pending)
    return attach, objects, origins, minimums
end

local function exported_through(release, install, seen)
    local found = release.libraries[install]
    if not found or seen[install] then
        return {}
    end
    seen[install] = true
    local names = table.keys(found.exports)
    for _, other in ipairs(found.reexports or {}) do
        table.join2(names, exported_through(release, other, seen))
    end
    return names
end

local function provides(release, install, symbol, seen)
    local found = release.libraries[install]
    if not found or seen[install] then
        return false
    end
    seen[install] = true
    if found.exports[symbol] then
        return true
    end
    for _, other in ipairs(found.reexports or {}) do
        if provides(release, other, symbol, seen) then
            return true
        end
    end
    return false
end

-- A .tbd that says a library at `install` exports these symbols and classes: what a link needs to name a
-- library the SDK does not have, or has elsewhere, and what the release's own cache says it holds.
local function write_stub(architecture, folder, install, symbols, classes)
    local target = architecture .. "-ios"
    local file = path.join(folder, path.basename(install) .. ".tbd")
    io.writefile(file, table.concat({"--- !tapi-tbd", "tbd-version: 4", "targets: [ " .. target .. " ]", "install-name: '" .. install .. "'", "exports:",
                                     "  - targets: [ " .. target .. " ]", "    symbols: [ " .. table.concat(symbols, ", ") .. " ]",
                                     "    objc-classes: [ " .. table.concat(classes, ", ") .. " ]", "..."}, "\n") .. "\n")
    return file
end

function stubs(architecture, library, reexported, releases, folder)
    local preferred = {}
    for index, framework in ipairs(library.frameworks) do
        preferred[framework] = index
    end
    local chosen = {}
    for _, symbol in ipairs(reexported) do
        local candidates = {}
        for install in pairs(releases[1].libraries) do
            local everywhere = true
            for _, release in ipairs(releases) do
                everywhere = everywhere and provides(release, install, symbol, {})
            end
            if everywhere then
                table.insert(candidates, install)
            end
        end
        if #candidates == 0 then
            raise("no library exports %s in every release a band of %s is checked against", symbol, library.name)
        end
        table.sort(candidates, function (a, b)
            local left, right = preferred[path.basename(a)] or math.huge, preferred[path.basename(b)] or math.huge
            if left ~= right then
                return left < right
            end
            return a < b
        end)
        chosen[candidates[1]] = chosen[candidates[1]] or {}
        table.insert(chosen[candidates[1]], symbol)
    end
    local files = {}
    for _, install in ipairs(table.orderkeys(chosen)) do
        local symbols, classes = {}, {}
        for _, symbol in ipairs(exported_through(releases[1], install, {})) do
            local class = symbol:match("^_OBJC_CLASS_%$_(.+)$")
            if class then
                table.insert(classes, class)
            elseif not symbol:startswith("_OBJC_METACLASS_$_") then
                table.insert(symbols, symbol)
            end
        end
        table.sort(symbols)
        table.sort(classes)
        table.insert(files, write_stub(architecture, folder, install, symbols, classes))
    end
    return files
end

-- `-framework X` resolves through the SDK's own install-name for X, which is wherever Apple's
-- *current* release keeps it - not necessarily where the band being linked keeps it. JavaScriptCore
-- moved from /System/Library/PrivateFrameworks to /System/Library/Frameworks exactly at iOS 7.0
-- (measured against both ends of the covered range, the only one of this package's 21 frameworks
-- that did): a band before that point links fine because the SDK's path happens to still match iOS
-- 6's, and a band from 7.0 on embeds a load command for a path that release never carried, which
-- only shows up as a bare "which neither the device nor this build provides" at the import check,
-- far from the framework name that would explain it.
--
-- The fix cannot be stubs()'s: a .tbd built from only this band's own exports drops every symbol
-- a later release added that this band's code reaches through a weak, API_AVAILABLE-guarded
-- reference (UTType.m's calls to _UTTypeIsDeclared/_UTTypeIsDynamic, absent on every release this
-- package covers before 11.0, are exactly that shape) - the linker needs a *declaration* to bind
-- those weakly, and a band-scoped stub does not carry one for the same reason the band does not
-- carry the real definition. Answered instead by keeping the ordinary, full-declaration
-- `-framework X` link exactly as before (nothing loses a weak-import declaration it depends on),
-- and rewriting the one load command afterward with install_name_tool -change, from whatever the
-- SDK embedded to the path this band's own cache says the framework actually lives at - the same
-- fact stubs() already reads from the cache, applied to the framework itself instead of only the
-- symbols a band reexports from it. Not a JavaScriptCore special case: framework_install_path is
-- asked for every framework a library links, so the next one Apple relocates is caught here
-- instead of costing another afternoon finding it by hand.
function framework_install_path(library, releases)
    local found = {}
    for _, framework in ipairs(library.frameworks) do
        local suffix = "/" .. framework .. ".framework/" .. framework
        local install
        for candidate in pairs(releases[1].libraries) do
            if candidate:endswith(suffix) then
                install = install or candidate
            end
        end
        if install then
            local everywhere = true
            for _, release in ipairs(releases) do
                everywhere = everywhere and release.libraries[install] ~= nil
            end
            if not everywhere then
                raise("%s is at %s in one release this band covers and not in another: a band spanning both needs the same install path in every release it covers, or it should be split at the release where the framework moved",
                      framework, install)
            end
            found[framework] = install
        end
    end
    return found
end

-- dyld learned to re-export a symbol of another library in iOS 4.2, and ld64
-- refuses -reexported_symbols_list for anything older ("targeted OS version
-- does not support -reexported_symbols_list"). A band for such a release still
-- drops what the release carries - that is the point of the band - it just
-- promises nothing in its place, and the port binds the release's own symbol,
-- which is there. libcxx does the same where it cannot re-export libcxxabi.
function reexports(deployment)
    return dyld.compare_versions(deployment, "4.2") >= 0
end

local INVENTORIES = {}

-- The Objective-C inventory of a release's cache is a function of the cache file and of the code that
-- reads it, and reading it is most of what a gate spends linking (measured: 3.9 s of a quiet machine's
-- time, loaded back in 0.4 s). So a build with a store keeps it there, under the cache's path, size
-- and time and the text of the modules that read it.
local INVENTORY_STORE

local function release_inventory(cache)
    if not INVENTORIES[cache] and INVENTORY_STORE and os.isfile(cache) then
        local parts = {"charon-inventory-1", cache, tostring(os.filesize(cache)), tostring(os.mtime(cache))}
        for _, name in ipairs({"objc.lua", "dyld.lua", "macho.lua"}) do
            table.insert(parts, hash.strhash128(io.readfile(path.join(os.scriptdir(), name))))
        end
        local key = hash.strhash128(table.concat(parts, "\n"))
        local file = path.join(INVENTORY_STORE, "inventories", key .. ".lua")
        local saved = os.isfile(file) and io.load(file)
        if saved then
            os.touch(file)
        else
            saved = objc.inventory(cache)
            store_folder(path.directory(file))
            local temporary = file .. "." .. hash.strhash32(cache .. os.mclock()) .. ".tmp"
            io.save(temporary, saved)
            os.mv(temporary, file)
        end
        INVENTORIES[cache] = saved
    end
    INVENTORIES[cache] = INVENTORIES[cache] or objc.inventory(cache)
    return INVENTORIES[cache]
end

local function carried_classes(cache)
    return release_inventory(cache).classes
end

-- The C++ runtime a band's objects link: libc++ where every release of the band has it, from iOS 5.0. Below
-- that the Itanium C++ ABI they need (operator new and delete, the personality routine, terminate) is
-- libstdc++.6's, which every release of the band must carry (checked for each) and the SDK does not, so the stub is
-- written from what the first release's cache says it exports.
function cxx_runtime(opt, library, releases, folder)
    local libcxx, libstdcxx = "/usr/lib/libc++.1.dylib", "/usr/lib/libstdc++.6.dylib"
    local without = false
    for _, release in ipairs(releases) do
        without = without or not release.libraries[libcxx]
    end
    if not without then
        return {"-lc++"}
    end
    for _, release in ipairs(releases) do
        if not release.libraries[libstdcxx] then
            raise("%s keeps C++ objects, and a release of its band has neither %s nor %s", library.name, libcxx, libstdcxx)
        end
    end
    local symbols = exported_through(releases[1], libstdcxx, {})
    table.sort(symbols)
    os.mkdir(folder)
    return {write_stub(opt.architecture, folder, libstdcxx, symbols, {})}
end

-- The key of one link for the store: the linker's arguments with the run's own folders taken out,
-- every file they name by content (an object by its store key, which is its content's cause), and the
-- install paths the link rewrites afterwards. What the link then checks is checked on the copy too.
function linked_key(opt, program, arguments, real_paths, outputdir, output)
    if not opt.store then
        return nil
    end
    -- This file's text too: what it does to a library after the linker (the install paths it rewrites)
    -- is its code and not an argument.
    local parts = {"charon-link-2", program, environment(), own_text()}
    local folders = {{outputdir, "@outputdir"}, {opt.builddir, "@builddir"}}
    for _, argument in ipairs(arguments) do
        local text = argument
        for _, folder in ipairs(folders) do
            if folder[1] then
                local at = text:find(folder[1], 1, true)
                while at do
                    text = text:sub(1, at - 1) .. folder[2] .. text:sub(at + #folder[1])
                    at = text:find(folder[1], at + #folder[2], true)
                end
            end
        end
        table.insert(parts, text)
        local file = argument:match("^%-Wl,%-[%w_]+,(.+)$") or argument
        if file ~= output and os.isfile(file) then
            table.insert(parts, KEYS[file] or hash.strhash128(io.readfile(file)))
        end
        local other = argument:match("^%-l(.+)$")
        if other then
            local dylib = path.join(outputdir, "lib" .. other .. ".dylib")
            table.insert(parts, os.isfile(dylib) and hash.strhash128(io.readfile(dylib)) or "none")
        end
    end
    for _, framework in ipairs(table.orderkeys(real_paths)) do
        table.insert(parts, framework .. "=" .. real_paths[framework])
    end
    return hash.strhash128(table.concat(parts, "\n"))
end

local function link(opt, library, attach, objects, releases, outputdir, checked)
    local release = checked and checked.release or opt.deployment
    local kept, reexported, left = band(releases[1].exports, objects, checked and later_than(opt, checked.release), {release = release, minimums = opt.minimums or {}})
    if #left > 0 then
        local named = {}
        for _, object in ipairs(left) do
            table.insert(named, string.format("%s (%s)", path.filename(opt.origins[object]), opt.minimums[object]))
        end
        cprint("${color.warning}note:${clear} the band for iOS %s leaves %d objects of %s out below their registry minimum: %s",
               release, #named, library.name, table.concat(named, " "))
    end
    if not reexports(opt.deployment) then
        reexported = {}
    end
    if checked then
        local told = duplicated(kept, carried_classes(checked.cache))
        if #told > 0 then
            raise("the band for iOS %s keeps %s, which the release has and does not export: the band cannot leave a class out that nothing says is there, and a process would hold two classes of that name, one of which the runtime picks. Ask the release for the class where it has one, or carry it under a name of Charon's own.",
                  checked.release, table.concat(told, " "))
        end
    end
    local output = path.join(outputdir, "lib" .. library.name .. ".dylib")
    os.mkdir(outputdir)
    local arguments = {"-target", opt.triple, "-isysroot", opt.sdkdir, "-fuse-ld=" .. opt.ld, "-fobjc-arc", "-dynamiclib",
                       "-install_name", path.join(INSTALL_FOLDER, path.filename(output)),
                       "-Wl,-rename_section,__DATA,__objc_catlist,__DATA,__charon_catlist", "-o", output, attach}
    table.join2(arguments, kept)
    if #reexported > 0 then
        local folder = path.join(opt.builddir, "stubs", path.filename(outputdir), library.name)
        os.tryrm(folder)
        os.mkdir(folder)
        table.join2(arguments, stubs(opt.architecture, library, reexported, releases, folder))
    end
    for _, other in ipairs(library.libraries or {}) do
        table.join2(arguments, {"-L" .. outputdir, "-l" .. other})
    end
    -- C++ reaches a library only through its Objective-C++ objects: the archives' API is C++, and so
    -- is the runtime they need. A band that keeps none of those objects, because its release carries
    -- the classes they define, links neither, since ld64 keeps a load command for every dylib it is
    -- given, used or not, and libc++ is exported only from iOS 5.0 on.
    local cxx = false
    for _, object in ipairs(kept) do
        cxx = cxx or opt.origins[object]:endswith(".mm")
    end
    -- **This is a change to the machinery, not to one framework.** Every archive in `archives` was
    -- taken to be C++, because every archive these packages held was C++, and the C++ ones are
    -- the only ones a band without a .mm object may skip: they need the C++ runtime, which is
    -- exported only from iOS 5.0 on, and ld64 keeps a load command for a dylib it is given
    -- whether the band used it or not. An archive whose API is **C** is the case that rule gets
    -- wrong, and there is one: charon-coding holds the secure coding, the copying and the archive
    -- allow-list that the Intents, IntentsUI and Accessibility classes share, and no two of those
    -- libraries can borrow it from another, because internal_symbol() hides a helper out of every
    -- dylib. A library that keeps no C++ object in any band therefore had no way to have a C
    -- helper at all, which is what the link said on `_charon_intents_decode` referenced from
    -- [AXBrailleTable initWithCoder:], which is where the link said it.
    --
    -- The language is a second list of the same names, `c_archives`, and not a table inside
    -- `archives`, because coordination/build-gate.lua reads `library.archives` for the names and
    -- a band does not change a script the coordinator owns.
    --
    -- tests/addon/archive_language_test.lua is the check: it fails on any library whose archives a
    -- band that keeps no C++ object could not link, which is the state without this.
    -- One list of the archives this band keeps, and the order they go on the link line in: the
    -- C ones always, the C++ ones only for a band that kept a .mm object, and each name once.
    local wanted_archives = {}
    for _, name in ipairs(library.archives or {}) do
        wanted_archives[name] = cxx
    end
    for _, name in ipairs(library and library.c_archives or {}) do
        wanted_archives[name] = true
    end
    for _, language in ipairs(table.orderkeys(wanted_archives)) do
        if wanted_archives[language] then
            local archive = archive_of(opt.archives, language)
            if not archive then
                raise("%s links the static library of the package %s, and the build was given none: pass archives = {%s = {linkdir = ..., link = ..., includedir = ...}}, from the package's installdir",
                      library.name, language, language)
            end
            table.insert(arguments, path.join(archive.linkdir, "lib" .. archive.link .. ".a"))
        end
    end
    if cxx then
        table.join2(arguments, cxx_runtime(opt, library, releases, path.join(opt.builddir, "stubs", path.filename(outputdir), library.name)))
    end
    -- A system library the band's own sources call into, a SQLite the HealthKit store is: it is linked
    -- as -l and the SDK carries its .tbd, and every release a band that keeps those sources runs on
    -- has it, which the import check below reads off the cache and would otherwise name as unresolved.
    for _, name in ipairs(library.system or {}) do
        table.insert(arguments, "-l" .. name)
    end
    -- A framework the band's release does not have is not linked: it could not load there. What the
    -- band keeps then needs none of it, or the link names the symbols that do.
    local real_paths = framework_install_path(library, releases)
    local absent = {}
    for _, framework in ipairs(library.frameworks) do
        if real_paths[framework] then
            table.join2(arguments, {"-framework", framework})
        else
            table.insert(absent, framework)
        end
    end
    if #absent > 0 then
        cprint("${color.warning}note:${clear} the band for iOS %s links %s without %s, which the release does not have", release, library.name, table.concat(absent, " "))
    end
    if #reexported > 0 then
        local list = path.join(opt.builddir, library.name .. ".reexported")
        io.writefile(list, table.concat(reexported, "\n") .. "\n")
        table.insert(arguments, "-Wl,-reexported_symbols_list," .. list)
    end
    local internal = {}
    for _, object in ipairs(kept) do
        for _, symbol in ipairs(defined_symbols(object)) do
            if internal_symbol(symbol) then
                table.insert(internal, symbol)
            end
        end
    end
    if #internal > 0 then
        local list = path.join(opt.builddir, library.name .. ".internal")
        io.writefile(list, table.concat(table.unique(internal), "\n") .. "\n")
        table.insert(arguments, "-Wl,-unexported_symbols_list," .. list)
    end
    local program, argv = driver(opt, arguments)
    local stored = linked_key(opt, program, argv, real_paths, outputdir, output)
    stored = stored and path.join(opt.store, "links", stored:sub(1, 2), stored .. ".dylib")
    if stored and os.isfile(stored) then
        os.cp(stored, output)
        os.touch(stored)
    else
        os.vrunv(program, argv)
        local embedded
        for _, framework in ipairs(library.frameworks) do
            local real = real_paths[framework]
            if real then
                embedded = embedded or macho.images(macho.read(output))[1].libraries
                local suffix = "/" .. framework .. ".framework/" .. framework
                for _, current in ipairs(embedded) do
                    if current:endswith(suffix) and current ~= real then
                        os.vrunv("xcrun", {"install_name_tool", "-change", current, real, output})
                    end
                end
            end
        end
        if stored then
            store_folder(path.directory(stored))
            local temporary = stored .. "." .. hash.strhash32(output .. os.mclock()) .. ".tmp"
            os.cp(output, temporary)
            os.mv(temporary, stored)
        end
    end
    if sections_of(output)["__DATA,__objc_catlist"] then
        raise("%s kept __objc_catlist: the linker did not rename it, so the runtime would attach every backported method over the system's own", output)
    end
    local held = {}
    for _, symbol in ipairs(defined_symbols(output)) do
        held[symbol] = true
    end
    local missing = {}
    for _, object in ipairs(kept) do
        for _, symbol in ipairs(exported_symbols(object)) do
            if not held[symbol] then
                table.insert(missing, symbol)
            end
        end
    end
    if #missing > 0 then
        table.sort(missing)
        raise("%s holds %d API it does not export, and a port that links against it takes the weak import of the release instead, which is NULL there: %s",
              output, #missing, table.concat(table.slice(missing, 1, math.min(8, #missing)), " ") .. (#missing > 8 and (" and %d more"):format(#missing - 8) or ""))
    end
    return output
end

local function loaded(cache, architecture)
    local release = dyld.load(cache)
    if not table.contains(compatible(architecture), release.architecture) then
        raise("%s holds %s libraries, which an %s build does not run on", cache, release.architecture, architecture)
    end
    return release
end

-- A category's class reference is NULL on a release that has the class without exporting
-- it, and is a class of Charon's own where charon_alias.h exports the release's name; in
-- both cases attach.c attaches the category to the release's class of that name, which it
-- finds only where the class is in an image the library loads. A category whose class is
-- neither exported nor there is dropped on the very release it is for, while its methods
-- still count as built. An alias of charon_alias.h is held to the same: its class must be
-- the release's, in an image the library loads.
local function loaded_images(release, binaries, binary, architecture)
    local own = {}
    for _, other in ipairs(binaries) do
        own[path.join(INSTALL_FOLDER, path.filename(other))] = other
    end
    local seen, pending = {}, {path.join(INSTALL_FOLDER, path.filename(binary))}
    while #pending > 0 do
        local install = table.remove(pending)
        if not seen[install] then
            seen[install] = true
            local dependents = release.libraries[install] and release.libraries[install].dependents
            if own[install] then
                for _, image in ipairs(macho.images(macho.read(own[install]))) do
                    if image.architecture == architecture then
                        dependents = image.libraries
                    end
                end
            end
            table.join2(pending, dependents or {})
        end
    end
    return seen
end

function unattached_categories(release, inventory, binaries, architecture)
    local defined, aliases = {}, {}
    for _, binary in ipairs(binaries) do
        for _, symbol in ipairs(defined_symbols(binary)) do
            defined[symbol] = true
        end
    end
    local found = {}
    for _, binary in ipairs(binaries) do
        local images
        for proxy, name in pairs(objc.binary_aliases(binary, architecture) or {}) do
            aliases[proxy] = name
            local carried = inventory.classes[name]
            images = images or loaded_images(release, binaries, binary, architecture)
            if not (carried and carried.image and images[carried.image]) then
                table.insert(found, string.format("%s, which %s aliases in %s", name, proxy, path.filename(binary)))
            end
        end
    end
    -- A category's class reference is filled when the class is this binary's own, an alias, or
    -- exported by the release or by a library of the package; otherwise dyld leaves it NULL
    -- and the loader has no class to attach it to, even where the release carries the class.
    -- ld64 merges a library's categories on one class into one, named after one of them, so a
    -- category is named with the members it adds: they, not its name, find every file behind it.
    for _, binary in ipairs(binaries) do
        for _, category in ipairs(objc.binary_categories(binary, architecture) or {}) do
            local bound = category.bound and category.bound:match("^_OBJC_CLASS_%$_(.+)$")
            local class = category.class and (aliases[category.class] or category.class) or bound
            local attached = category.class ~= nil or (category.bound ~= nil and (release.exports[category.bound] or defined[category.bound]))
            if not attached then
                local members = {}
                for kind, sign in pairs({instance = "-", class_methods = "+"}) do
                    for selector in pairs(category[kind]) do
                        table.insert(members, sign .. selector:sub(2))
                    end
                end
                table.sort(members)
                local named = string.format("%s(%s: %s) in %s", class or "a class this check cannot name", category.name or "?",
                                            table.concat(members, " "), path.filename(binary))
                local carried = class and inventory.classes[class]
                if carried and carried.image then
                    table.insert(found, string.format("%s (the release carries %s in %s without exporting it: alias it through charon_alias.h)",
                                                      named, class, carried.image))
                else
                    table.insert(found, named)
                end
            end
        end
    end
    table.sort(found)
    return found
end

function check_categories(release, inventory, binaries, architecture, version)
    local found = unattached_categories(release, inventory, binaries, architecture)
    if #found > 0 then
        raise("categories whose class neither iOS %s nor the package exports, and aliases whose class it does not carry in an image the library loads, so the library's loader has no class to give what they add and nothing of it is there: %s",
              version, table.concat(found, " "))
    end
end

-- The members a binary's categories add to classes it does not define itself: the API a category
-- carries, as the registry spells it.
local function class_image(inventory, name)
    local class = inventory and inventory.classes and inventory.classes[name]
    return class and class.image or false
end

local function members_of(inventory, classes)
    local found = {}
    for name, class in pairs(inventory and inventory.classes or {}) do
        if classes(name) then
            for kind, sign in pairs({instance = "-", class = "+"}) do
                for selector in pairs(class[kind]) do
                    local plain = selector:sub(2)
                    if not plain:startswith(".cxx_") and plain ~= "load" and not internal_symbol(plain) then
                        table.insert(found, string.format("%s[%s %s]", sign, name, plain))
                    end
                end
            end
        end
    end
    return found
end

-- What the band machinery places an object by: the members a category adds to a class the object does not
-- define. A member the port adds in a category is not defined by the object that carries it - a member of
-- a class the release already carries belongs to that class - and counting it here moved the carrying object
-- out of the band its own minimum says: measured 2026-09-28 by bisecting the 4.3 gate over 2fde39f4, which
-- widened this for check_registry, and put 16 objects above iOS 4.3.
function added_members(inventory, ours)
    return members_of(inventory, function (name)
        return not class_image(inventory, name) and not ours[name]
    end)
end

-- The API the port carries in its categories, which is a wider question than what any one object defines: a
-- member the port adds to a class the release already carries is API the port carries, and check_registry asks
-- whether a row says so. The port's own classes are its machinery and it names them. This is the set 2fde39f4
-- widened, kept for that reader alone.
function carried_api(inventory)
    return members_of(inventory, function (name)
        return not name:startswith("Charon")
    end)
end


function surface(binaries, architecture)
    local found = {classes = {}, members = {}, symbols = {}, defined = {}, registered = {}, answered = {}}
    for _, binary in ipairs(binaries) do
        local ours = {}
        if macho.imported_symbols(binary, architecture)["objc_allocateClassPair"] then
            for literal in pairs(macho.text_literals(binary, architecture)) do
                found.registered[literal] = true
            end
        end
        for _, symbol in ipairs(exported_symbols(binary)) do
            local class = symbol:match("^_OBJC_CLASS_%$_(.+)$")
            if class then
                ours[class] = true
                found.classes[class] = true
            elseif not symbol:startswith("_OBJC_METACLASS_$_") and not symbol:startswith("_OBJC_IVAR_$_") then
                found.symbols[symbol:sub(2)] = true
                found.defined["_" .. symbol:sub(2)] = true
            end
        end
        local inventory = objc.binary_inventory(binary, architecture)
        for name, class in pairs(inventory and inventory.classes or {}) do
            if class.image and not name:startswith("Charon") then
                found.classes[name] = true
            end
            if not name:startswith("Charon") then
                for kind, sign in pairs({instance = "-", class = "+"}) do
                    for selector in pairs(class[kind]) do
                        found.answered[string.format("%s[%s %s]", sign, name, selector:sub(2))] = true
                    end
                end
            end
        end
        for _, member in ipairs(carried_api(inventory)) do
            found.members[member] = true
        end
    end
    return found
end

local STATUSES = {implemented = true, inert = true, absent = true, ignored = true}

-- The accessor that reads or writes a property by the property's own name, as the other spelling of that one
-- API: -[Class name] or +[Class name] for Class.name, and Class.name for either. The setter is deliberately not
-- one of them: a property can be carried while its setter is left out or left inert, which is what a row of its
-- own is for, and spelling() would pair them and refuse an answer that is right.
local function accessor_of(api)
    local sign, owner, name = api:match("^([-+])%[([%w_]+) ([%w_]+)%]$")
    if sign then
        return owner .. "." .. name
    end
    return api:match("^([%u][%w_]*)%.([%w_]+)$") and api
end

function registry(root)
    local listed, told, incomplete, frameworks = {}, {}, {}, {}
    local files = table.join(os.files(path.join(root, "registry", "*.json")), os.files(path.join(root, "registry", "*", "*.json")))
    table.sort(files)
    for _, file in ipairs(files) do
        -- registry/<Framework>.json or registry/<Framework>/<part>.json, named from the package root so that a
        -- name named twice names two paths a reader can open
        local folder = path.filename(path.directory(file))
        local named = folder == "registry" and path.filename(file) or folder .. "/" .. path.filename(file)
        named = "registry/" .. named
        frameworks[folder == "registry" and path.basename(file) or folder] = true
        local held = json.decode(io.readfile(file))
        for _, entry in ipairs(held.entries or held) do
            if told[entry.api] then
                table.insert(incomplete, entry.api .. " is named by both " .. told[entry.api] .. " and " .. named)
            end
            told[entry.api] = named
            listed[entry.api] = entry
            -- a method or a property is told by -[Class selector:], +[Class selector:] or Class.name: lift() and the check of releases read
            -- no other spelling, and a member spelled Class.selector: is asked for as a bare name, found nowhere and left as it was
            local plain = entry.api:gsub("%(%)$", "")
            if (entry.kind == "method" or entry.kind == "property") and not (plain:match("^[-+]%[[%w_]+ .+%]$") or plain:match("^[%w_]+%.[%w_]+$")) then
                table.insert(incomplete, entry.api .. " is a " .. entry.kind .. " not spelled -[Class selector:], +[Class selector:] or Class.name")
            elseif (entry.kind == "class" or entry.kind == "protocol") and not plain:match("^[%u_][%w_]*$") then
                -- the other way round: a class or a protocol is matched against an ObjCInterfaceDecl or an
                -- ObjCProtocolDecl of that name, so a member spelling is a name no dump can ever answer
                table.insert(incomplete, entry.api .. " is a " .. entry.kind .. " spelled " .. entry.api ..
                                          ", and a " .. entry.kind .. " is named by its interface or its protocol, not by a member")
            end
            if not STATUSES[entry.status] then
                table.insert(incomplete, entry.api .. " says " .. tostring(entry.status) .. ", which is not one of the four answers")
            elseif entry.status ~= "implemented" then
                if not entry.effect then
                    table.insert(incomplete, entry.api .. " is " .. entry.status .. " without an effect")
                elseif entry.status ~= "ignored" and not entry.reason then
                    table.insert(incomplete, entry.api .. " is " .. entry.status .. " without a reason")
                elseif entry.status == "ignored" and not entry.facts then
                    table.insert(incomplete, entry.api .. " is ignored without a file of facts")
                end
            end
        end
    end
    -- Two rows that name one API in two spellings are one API and must answer alike: the lift carries the
    -- implemented one and lowers its availability, and an implicit accessor carries its property's attribute,
    -- so a status that disagreed between a property and the accessor that reads it has one of them say the
    -- call is not there and the other lower it anyway. The lift refuses its own headers over that, after the
    -- whole surface has been dumped; said here, the registry is refused in the second it is read.
    local told_pair = {}
    for api, entry in pairs(listed) do
        local other = accessor_of(api)
        local twin = other and other ~= api and listed[other] or nil
        if twin and twin.status ~= entry.status then
            local pair = api < other and (api .. " " .. other) or (other .. " " .. api)
            if not told_pair[pair] then
                told_pair[pair] = true
                table.insert(incomplete, string.format("%s is %s and %s is %s, and they are one API in two spellings (%s and %s), which the lift would carry and lower together",
                                                      api, entry.status, other, twin.status, told[api], told[other]))
            end
        end
    end
    return listed, incomplete, table.orderkeys(frameworks)
end

local function property_of(selector)
    local named = selector:match("^set(%u[%w_]*):$")
    if named then
        return named:sub(1, 1):lower() .. named:sub(2)
    end
    return selector:match("^([%w_]+)$")
end

spellings = function(api)
    local plain = api:gsub("%(%)$", "")
    local found = {[plain] = true, [plain .. "()"] = true}
    local class, member = plain:match("^([%u][%w_]*)%.(.+)$")
    if class then
        for _, selector in ipairs({member, "set" .. member:sub(1, 1):upper() .. member:sub(2) .. ":"}) do
            found[string.format("-[%s %s]", class, selector)] = true
            found[string.format("+[%s %s]", class, selector)] = true
        end
    end
    local sign, owner, selector = plain:match("^([-+])%[([%w_]+) (.+)%]$")
    if sign then
        found[owner .. "." .. selector] = true
        local property = property_of(selector)
        if property then
            found[owner .. "." .. property] = true
        end
    end
    return found
end

local ORDER = {ignored = 1, absent = 2, inert = 3}

function advice(root, used)
    local listed = registry(root)
    local found = {}
    for api, entry in pairs(listed) do
        if ORDER[entry.status] then
            for spelling in pairs(spellings(api)) do
                local selector = spelling:match("^[-+]%[[%w_]+ (.+)%]$")
                if used[spelling] or (selector and used[selector]) then
                    found[api] = entry
                end
            end
        end
    end
    local named = table.orderkeys(found)
    table.sort(named, function (a, b)
        if ORDER[found[a].status] ~= ORDER[found[b].status] then
            return ORDER[found[a].status] < ORDER[found[b].status]
        end
        return a < b
    end)
    local advised = {}
    for _, api in ipairs(named) do
        table.insert(advised, {api = api, status = found[api].status, effect = found[api].effect, introduced = found[api].introduced})
    end
    return advised
end

local function carried_by_release(entry, inventory)
    local function has(class, selector, sign)
        local carried = inventory.classes[class]
        return carried ~= nil and carried[sign == "-" and "instance" or "class"]["-" .. selector] ~= nil
    end
    if entry.kind == "class" then
        return inventory.classes[entry.api] ~= nil
    elseif entry.kind == "protocol" then
        return nil
    elseif entry.kind == "method" then
        local sign, class, selector = entry.api:match("^([-+])%[([%w_]+) (.+)%]$")
        if sign ~= nil and inventory.classes[class] == nil and (inventory.protocols or {})[class] ~= nil then
            return nil
        end
        return sign ~= nil and has(class, selector, sign)
    elseif entry.kind == "property" then
        local class, property = entry.api:match("^([%w_]+)%.([%w_]+)$")
        return class ~= nil and (has(class, property, "-") or has(class, "set" .. property:sub(1, 1):upper() .. property:sub(2) .. ":", "-"))
    end
    return nil
end

local function in_range(entry, deployment)
    if not deployment then
        return false
    end
    return not (entry.minimum and dyld.compare_versions(deployment, entry.minimum) < 0)
        and not (entry.maximum and dyld.compare_versions(deployment, entry.maximum) >= 0)
end

-- The registry entry a built name answers to: its own spelling, else the entry of the class that owns it.
-- Exported, not local: modules/apple/backports.lua's own registry_test reads backports.entry_of, and a
-- forward declaration main added reads it too. The inventory is optional and defaults to what the
-- caller has: a name whose class the release itself carries needs a row of its own.
function entry_of(listed, name, inventory)
    for spelling in pairs(spellings(name)) do
        if listed[spelling] then
            return listed[spelling]
        end
    end
    local owner = name:match("^[-+]%[([%w_]+) ") or name:match("^([%u][%w_]*)%.")
    if not owner then
        return nil
    end
    -- A class row answers for the members of a class the port defines wholly. It does not answer for a class
    -- the release itself carries: -[UIView foo] that the port adds in a category is API the port carries, and
    -- UIView's row says nothing about foo, so the member needs its own row (measured 2026-09-28: with the
    -- class row answering, 1,452 members of classes the port carries had no row of their own and passed).
    local carried = inventory and inventory.classes and inventory.classes[owner]
    if carried and carried.image then
        return nil
    end
    return listed[owner]
end

-- Every name the headers the build reads declare: the tree's own - a Charon header, generated or written - and
-- the SDK the package compiled against. A type, an enumeration or a struct has no symbol by nature, so an entry
-- of kind "type" or "case" is implemented when a header declares it, and the declaration is read, never taken on
-- trust: a name no header here or there declares is the same as a class nothing exports. The SDK holds tens of
-- thousands of headers, so its pass is kept beside the caches and read again for nothing.
local function declared_names(root, sdkdir)
    local names, ours = {}, {}
    for _, file in ipairs(os.files(path.join(root, "*.h"))) do
        for word in io.readfile(file):gmatch("[%w_]+") do
            ours[word] = true
        end
    end
    for _, folder in ipairs({root, path.join(root, "*")}) do
        for _, file in ipairs(os.files(path.join(folder, "*.h"))) do
            for word in io.readfile(file):gmatch("[%w_]+") do
                ours[word] = true
            end
        end
    end
    if sdkdir and os.isdir(sdkdir) then
        -- named by a key over everything its content depends on, the reader included: a tag for how the
        -- words are gathered, so a change here is a different file and nothing is ever invalidated by hand
        -- (the rule dyld.lua's own kept files are written to). Without the tag a fixed SDK path keeps serving
        -- the words an earlier reader gathered - and an earlier reader that gathered none.
        -- named by a key over everything its content depends on: the SDK's own path spelled as text,
        -- and a tag for how the words are gathered. hash.sha256 of a table is the empty-string hash -
        -- opt.sdkdir is a table where the build resolves it - so every SDK's words landed on one 51 MB
        -- file and answered for a header they do not declare. Measured: e3b0c44298fc1c14 is sha256 of
        -- the empty string, and that file was 51,197,631 bytes of a different SDK.
        local spelling = type(sdkdir) == "table" and table.concat(sdkdir, " ") or tostring(sdkdir)
        -- hash.sha256 takes bytes, and a Lua string hashed as one reads as no bytes at all: measured
        -- 2026-09-28, sha256(spelling) is e3b0c44298fc1c14, the empty string, for every SDK - and the
        -- one file that key names was 51,197,631 bytes of some other SDK's words.
        local kept = path.join(dyld.root(), "cache", "sdk-header-names-v1-"
                              .. hash.strhash128(spelling):sub(1, 16) .. ".txt")
        local text = os.isfile(kept) and io.readfile(kept) or nil
        if not text then
            -- os.execv's stdout is a file to write, not a buffer: grep's words go to a temporary file, and
            -- the words themselves are kept in the cache by io.writefile, which is what this tree has
            local found = os.tmpfile()
            for _, folder in ipairs({path.join(sdkdir, "usr/include"), path.join(sdkdir, "System/Library/Frameworks")}) do
                if os.isdir(folder) then
                    os.execv("grep", {"-rhoE", "[A-Za-z_][A-Za-z0-9_]*", folder}, {stdout = found})
                end
            end
            text = io.readfile(found) or ""
            os.tryrm(found)
            io.writefile(kept, text)
        end
        for word in text:gmatch("[%w_]+") do
            names[word] = true
        end
    end
    for word in pairs(ours) do
        names[word] = true
    end
    return names
end

-- Whether the protocol a member's owner names is declared - with a body, not a forward declaration - by a
-- header this package installs or by the SDK the backport is compiled against. The owner's being a protocol
-- is not the answer: a protocol nothing declares answers nothing, and the member of one is then implemented
-- nowhere. The release's own inventory answers for a protocol the release itself carries.
local SDK_DECLARATIONS = {}

-- The SDK's own protocol declarations, once per SDK: 51 MB of words over tens of thousands of headers, and
-- the SDK at a given path does not change under us. Keyed by that path and nothing else.
function sdk_protocol_declarations(sdkdir)
    if not sdkdir or not os.isdir(sdkdir) then
        return {}
    end
    local seen = SDK_DECLARATIONS[sdkdir]
    if not seen then
        seen = {}
        local function scan(folder)
            for _, file in ipairs(os.files(path.join(folder, "*.h"))) do
                for line in io.lines(file) do
                    for protocol in line:gmatch("@protocol%s+([%w_]+)") do
                        if not line:find("@protocol%s+" .. protocol .. "%s*;") then
                            seen[protocol] = true
                        end
                    end
                end
            end
        end
        scan(path.join(sdkdir, "usr/include"))
        -- every framework, resolved: one of them is a symlink into the Cryptex, and os.files does not
        -- follow a symlinked directory, so the glob missed its headers and the protocols in them
        for _, framework in ipairs(os.dirs(path.join(sdkdir, "System/Library/Frameworks", "*"))) do
            local resolved = framework
            if os.islink(framework) then
                local target = os.readlink(framework) or ""
                if target:sub(1, 1) ~= "/" then
                    target = path.join(path.directory(framework), target)
                end
                resolved = path.absolute(target)
            end
            scan(path.join(resolved, "Headers"))
        end
        SDK_DECLARATIONS[sdkdir] = seen
    end
    return seen
end

-- Whether the protocol a member's owner names is declared - with a body, not a forward declaration - by a
-- header this package installs or by the SDK the backport is compiled against. The owner's being a protocol is
-- not the answer: a protocol nothing declares answers nothing, and the member of one is then implemented
-- nowhere (ef271700 on ARKit, 5a505a9b on MXDiagnostic). The release's own inventory answers for a protocol
-- the release itself carries. The tree's own headers are read every call: 87 files, and they change under a
-- build, which a memo keyed on the folder cannot see.
function protocol_declared(root, owner, inventory, sdkdir)
    if inventory and inventory.protocols and inventory.protocols[owner] ~= nil then
        return true
    end
    if sdk_protocol_declarations(sdkdir)[owner] then
        return true
    end
    for _, folder in ipairs({root, path.join(root, "*")}) do
        for _, file in ipairs(os.files(path.join(folder, "*.h"))) do
            for line in io.lines(file) do
                for protocol in line:gmatch("@protocol%s+([%w_]+)") do
                    if protocol == owner and not line:find("@protocol%s+" .. protocol .. "%s*;") then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- The registry check as build() runs it, in one place: release_inventory takes the cache directory and
-- nothing else, and check_registry the SDK the objects were compiled against. A test that calls this with
-- build()'s own option shape is what keeps a wrong argument here from reaching a gate: the light guard's
-- fixtures call check_registry directly and never did.
-- Every protocol a header the package installs declares with a body, and every one it only names.
-- Objective-C emits a protocol's metadata into the image that uses or adopts it, and the runtime
-- deduplicates it, so a library need not carry a protocol for a caller to get it: what a caller needs is
-- the declaration, and a forward declaration (@protocol X;) is not one.
function declared_protocols(root)
    local declared = {}
    for _, pattern in ipairs({"*.h", "*/*.h"}) do
        for _, file in ipairs(os.files(path.join(root, pattern))) do
            for line in io.lines(file) do
                for name in line:gmatch("@protocol%s+([%w_]+)") do
                    if not line:find("@protocol%s+" .. name .. "%s*;") then
                        declared[name] = true
                    end
                end
            end
        end
    end
    return declared
end

function registry_step(opt, built, complete, exports)
    return check_registry(opt.root, built, complete, opt.deployment, exports,
                          release_inventory(opt.cache), opt.sdkdir, declared_protocols(opt.root))
end

function check_registry(root, found, complete, deployment, exports, inventory, sdkdir, declared)
    local listed, incomplete = registry(root)
    local unlisted, undocumented = {}, {}
    -- per call, not a module global: an earlier check in the same process filled it from a tree with no SDK
    -- and the next one reused that answer instead of asking declared_names about its own
    local declared_by_header
    for _, carried in ipairs({found.classes, found.members, found.symbols}) do
        for name in pairs(carried) do
            -- the protocol metadata symbols answer for the protocol rows and are not API of their own
            local protocol_metadata = name:startswith("_OBJC_PROTOCOL_$_") or name:startswith("_OBJC_LABEL_PROTOCOL_$_")
            if not protocol_metadata and not entry_of(listed, name, inventory) then
                table.insert(unlisted, name)
            end
        end
    end
    local answered = {}
    for name, entry in pairs(listed) do
        if entry.status == "absent" then
            local present = entry.kind == "class" and found.classes[name] or false
            present = present or ((entry.kind == "constant" or entry.kind == "function") and found.symbols[name:gsub("%(%)$", "")]) or false
            for spelling in pairs(spellings(name)) do
                present = present or (spelling:match("^[-+]%[") and (found.answered or {})[spelling]) or false
            end
            if present then
                table.insert(answered, name)
            end
        end
    end
    local held, missing = {}, {}
    if inventory then
        for name, entry in pairs(listed) do
            local natively = deployment and entry.introduced and dyld.compare_versions(deployment, entry.introduced) >= 0
            if entry.status == "absent" and in_range(entry, deployment) and not natively and carried_by_release(entry, inventory) then
                table.insert(held, name)
            elseif entry.status == "ignored" and in_range(entry, deployment) and carried_by_release(entry, inventory) == false then
                table.insert(missing, name)
            end
        end
    end
    local unbuilt = {}
    if complete ~= false then
        for name, entry in pairs(listed) do
            local built = false
            for spelling in pairs(spellings(name)) do
                built = built or found.classes[spelling] or found.members[spelling] or found.symbols[spelling] or false
            end
            local owner = name:match("^[-+]%[([%w_]+) ") or name:match("^([%u][%w_]*)%.")
            built = built or (owner and found.classes[owner]) or false
            built = built or (entry.kind == "class" and (found.registered or {})[name]) or false
            local carried = deployment and entry.introduced and dyld.compare_versions(entry.introduced, deployment) <= 0
            carried = carried or (exports and exports["_" .. name:gsub("%(%)$", "")]) or false
            local ours = not deployment or in_range(entry, deployment)
            -- A protocol has no accessors, so nothing else in this loop can answer for it: the row is
            -- implemented when the objects carry the protocol's own metadata and it names.
            local declared = entry.kind == "protocol" and ((declared or {})[name] or false) or
                (owner and listed[owner] and listed[owner].kind == "protocol" and
                 protocol_declared(root, owner, inventory, sdkdir)) or
                (owner and inventory and inventory.protocols and inventory.protocols[owner] ~= nil) or false
            if (entry.kind == "type" or entry.kind == "case") and not built then
                -- no symbol will ever answer for a type or an enumeration case, so the header is the build
                declared_by_header = declared_by_header or declared_names(root, sdkdir)
                built = declared_by_header[name] or false
            end
            if entry.status == "implemented" and not built and not carried and ours and not declared then
                table.insert(unbuilt, name)
            elseif entry.status == "implemented" and not entry.facts then
                table.insert(undocumented, name)
            end
        end
    end
    table.sort(unlisted)
    table.sort(unbuilt)
    table.sort(answered)
    table.sort(held)
    table.sort(missing)
    if #unlisted > 0 or #unbuilt > 0 or #answered > 0 or #held > 0 or #missing > 0 or #incomplete > 0 then
        local lines = {"the registry does not describe what the backports carry:"}
        for _, described in ipairs(incomplete) do
            table.insert(lines, "  " .. described)
        end
        if #unlisted > 0 then
            table.insert(lines, "  built, but no entry in registry/: " .. table.concat(unlisted, "; "))
        end
        if #unbuilt > 0 then
            table.insert(lines, "  listed as implemented, but nothing of that name is built: " .. table.concat(unbuilt, "; "))
        end
        if #answered > 0 then
            table.insert(lines, "  listed as absent, but what is built answers it: " .. table.concat(answered, "; "))
        end
        if #held > 0 then
            table.insert(lines, "  listed as absent, but the release carries it itself, so it is the release's own and not absent: " .. table.concat(held, "; "))
        end
        if #missing > 0 then
            table.insert(lines, "  listed as ignored because the release carries it, but the release does not: " .. table.concat(missing, "; "))
        end
        raise(table.concat(lines, "\n"))
    end
    return #undocumented
end


-- The names one object carries as API: its exported classes, functions and constants, and the members
-- its categories add. An object that carries none is a helper of the objects that do.
local function carried_names(object, architecture)
    local names, ours = {}, {}
    for _, symbol in ipairs(exported_symbols(object)) do
        local class = symbol:match("^_OBJC_CLASS_%$_(.+)$") or symbol:match("^_OBJC_METACLASS_%$_(.+)$")
        if class then
            ours[class] = true
        end
        names[class or symbol:sub(2)] = true
    end
    for _, member in ipairs(added_members(objc.binary_inventory(object, architecture), ours)) do
        names[member] = true
    end
    return table.orderkeys(names)
end

local function lower(a, b)
    if a == nil or b == "" then
        return b
    end
    if a == "" or b == nil then
        return a
    end
    return dyld.compare_versions(a, b) <= 0 and a or b
end

-- The release each object is carried from, {object = version}: the `minimum` of the registry entries
-- its API answers to, and no key for an object without one. An object whose entries name different
-- minimums (an entry without one names none) is refused, as misplaced() refuses mixed releases: the
-- earliest would carry API below its minimum, the latest would drop API the registry carries earlier.
-- A helper takes the lowest minimum among the objects that name a symbol it defines (nm -u), through
-- other helpers as well; the third answer lists the objects that carry nothing the registry can place
-- and that no object names, such as an installer whose +load adds its API at run time. Such an object
-- takes the highest minimum among the objects it names, through others of its kind as well, since it
-- links only where every one of them is carried; the fourth answer says which, {object = {minimum,
-- from, symbol}}. With nothing to take, every band keeps it. An object the registry or its callers
-- place below an object it names is refused as well: it would not link in the bands between. A minimum
-- at or below the deployment bounds nothing, so it mixes with none.
function minimums(listed, objects, architecture, deployment)
    local found, problems, bounds, helpers = {}, {}, {}, {}
    for _, object in ipairs(objects) do
        local names = carried_names(object, architecture)
        if #names == 0 then
            table.insert(helpers, object)
        else
            local by, order = {}, {}
            for _, name in ipairs(names) do
                local entry = entry_of(listed, name)
                if entry then
                    local minimum = entry.minimum or ""
                    if minimum ~= "" and deployment and dyld.compare_versions(minimum, deployment) <= 0 then
                        minimum = ""
                    end
                    if not by[minimum] then
                        by[minimum] = {}
                        table.insert(order, minimum)
                    end
                    table.insert(by[minimum], name)
                end
            end
            if #order > 1 then
                table.sort(order, function (a, b) return lower(a, b) == a and a ~= b end)
                local described = {}
                for _, minimum in ipairs(order) do
                    table.insert(described, string.format("%s with %s", table.concat(by[minimum], " "), minimum == "" and "no registry minimum" or ("registry minimum " .. minimum)))
                end
                table.insert(problems, string.format("%s defines %s; an object is carried from one release on, so split it", path.filename(object), table.concat(described, " and ")))
            end
            bounds[object] = #order == 1 and order[1] or ""
        end
    end
    local definer, helper = {}, {}
    for _, object in ipairs(objects) do
        for _, symbol in ipairs(defined_symbols(object, true)) do
            definer[symbol] = object
        end
    end
    for _, object in ipairs(helpers) do
        helper[object] = true
    end
    local changed = true
    while changed do
        changed = false
        for _, object in ipairs(objects) do
            if bounds[object] then
                for _, symbol in ipairs(undefined_symbols(object)) do
                    local named = definer[symbol]
                    if named and named ~= object and helper[named] then
                        local bound = lower(bounds[named], bounds[object])
                        if bound ~= bounds[named] then
                            bounds[named] = bound
                            changed = true
                        end
                    end
                end
            end
        end
    end
    local unreached = {}
    for _, object in ipairs(objects) do
        if bounds[object] == nil then
            table.insert(unreached, object)
        elseif bounds[object] ~= "" then
            found[object] = bounds[object]
        end
    end
    local needs, inherited = {}, {}
    for _, object in ipairs(unreached) do
        needs[object] = undefined_symbols(object)
    end
    changed = true
    while changed do
        changed = false
        for _, object in ipairs(unreached) do
            for _, symbol in ipairs(needs[object]) do
                local named = definer[symbol]
                local minimum = named and named ~= object and found[named]
                if minimum and (not found[object] or dyld.compare_versions(minimum, found[object]) > 0) then
                    found[object] = minimum
                    inherited[object] = {minimum = minimum, from = named, symbol = symbol}
                    changed = true
                end
            end
        end
    end
    for _, object in ipairs(objects) do
        if bounds[object] ~= nil then
            for _, symbol in ipairs(needs[object] or undefined_symbols(object)) do
                local named = definer[symbol]
                local minimum = named and named ~= object and found[named]
                if minimum and (not found[object] or dyld.compare_versions(minimum, found[object]) > 0) then
                    table.insert(problems, string.format("%s is carried %s and names %s, which %s defines only from %s on; it would not link below that, so give its entries that minimum or move the symbol to a file of its own",
                                                         path.filename(object), found[object] and ("from " .. found[object]) or "by every band", symbol, path.filename(named), minimum))
                end
            end
        end
    end
    local kept = {}
    for _, object in ipairs(unreached) do
        if not found[object] then
            table.insert(kept, object)
        end
    end
    return found, problems, kept, inherited
end

function build(opt)
    INVENTORY_STORE = opt.store
    local release = loaded(opt.cache, opt.architecture)
    opt = table.join(opt, {triple = opt.architecture .. "-apple-ios" .. opt.deployment})
    -- What the run spent, in the run's own output. A build that prints only its verdict cannot be
    -- improved: the split of compile, link and checks is what says where a machine's time went,
    -- and it is only comparable between runs if every run measures it the same way. The first
    -- number is compiles this run made and the second is objects it holds, and they differ by
    -- however much the compiler cache served - a line that said "compiled 969 objects in 0.4s"
    -- would be the one number a band would quote and the one that would be wrong.
    COMPILED = 0
    local compiling = os.mclock()
    local attach, objects, origins, minimums = compiled(opt)
    opt = table.join(opt, {origins = origins, minimums = minimums})
    local compiled_at = os.mclock()
    local compiled, placed = COMPILED, 0
    for _, library in ipairs(LIBRARIES) do
        placed = placed + (objects[library.name] and #objects[library.name] or 0)
    end
    check_releases(opt, objects, origins)
    local checked_at = os.mclock()
    local built = {}
    for _, library in ipairs(LIBRARIES) do
        if not opt.libraries or table.contains(opt.libraries, library.name) then
            table.insert(built, link(opt, library, attach, objects[library.name], {release}, opt.outputdir,
                                     {cache = opt.cache, release = opt.deployment}))
        end
    end
    local linked_at = os.mclock()
    dyld.check(opt.cache, built)
    check_categories(release, release_inventory(opt.cache), built, opt.architecture, opt.deployment)
    if #built == #LIBRARIES then
        check_band_caches(opt, objects)
        local undocumented = check_registry(opt.root, surface(built, opt.architecture), opt.registry, opt.deployment, release.exports, release_inventory(opt.cache))
        if undocumented > 0 then
            cprint("${color.warning}note:${clear} %d of the registry's entries name no file of facts yet", undocumented)
        end
    end
    print(string.format("build: %s compiled %d of %d objects in %.1fs, measured their releases in %.1fs, linked %d libraries in %.1fs, checked in %.1fs",
                        opt.deployment, compiled, placed, (compiled_at - compiling) / 1000,
                        (checked_at - compiled_at) / 1000, #built, (linked_at - checked_at) / 1000,
                        (os.mclock() - linked_at) / 1000))
    return built
end

function introduced_version(dump, name)
    local found, current
    for line in dump:gmatch("[^\n]+") do
        local dumping = line:match("^Dumping (.-):$")
        if dumping then
            current = dumping
        elseif current == name then
            local version = line:match("^[|`]%-AvailabilityAttr.- ios (%d+[%.%d]*) ")
            if version and (not found or dyld.compare_versions(version, found) < 0) then
                found = version
            end
        end
    end
    return found
end

function availability_names(symbols)
    local names = {}
    for _, symbol in ipairs(symbols) do
        names[symbol:match("^_OBJC_CLASS_%$_(.+)$") or symbol:match("^_OBJC_METACLASS_%$_(.+)$")
              or symbol:match("^_OBJC_IVAR_%$_(.-)%.") or symbol:sub(2)] = true
    end
    return names
end

local LISTED = {}

local function listed(root)
    LISTED[root] = LISTED[root] or registry(root)
    return LISTED[root]
end

-- The sources whose registry minimum is above the deployment, {source = {minimum, object}}: a band
-- below that release neither compiles nor keeps them, and the bands from it on carry the object
-- compiled for the minimum itself. Which entries an object answers to is known only once it is
-- compiled, so below the highest minimum the registry names, every source is compiled once for that
-- release first; a deployment at or above it has every source in range and compiles nothing extra.
function floors(opt)
    local top
    for _, entry in pairs(listed(opt.root)) do
        if entry.minimum and dyld.compare_versions(entry.minimum, opt.deployment) > 0 and (not top or dyld.compare_versions(entry.minimum, top) > 0) then
            top = entry.minimum
        end
    end
    if not top then
        return {}
    end
    local function at(release)
        return table.join(opt, {deployment = release, triple = opt.architecture .. "-apple-ios" .. release})
    end
    local objects, origins, pending = {}, {}, {}
    for _, library in ipairs(LIBRARIES) do
        for _, source in ipairs(sources(opt.root, library)) do
            local object = path.join(opt.builddir, "objects-" .. top, library.folder, path.basename(source) .. ".o")
            os.mkdir(path.directory(object))
            table.insert(pending, {opt = at(top), source = source, object = object})
            table.insert(objects, object)
            origins[object] = source
        end
    end
    compile_all(opt, pending)
    local found, problems, unreached, inherited = minimums(listed(opt.root), objects, opt.architecture, opt.deployment)
    if #problems > 0 then
        raise("%d objects cannot be placed by their registry minimum above iOS %s:\n  %s", #problems, opt.deployment, table.concat(problems, "\n  "))
    end
    local taken = {}
    for _, object in ipairs(objects) do
        local from = inherited[object]
        if from then
            table.insert(taken, string.format("%s (%s, from %s by %s)", path.filename(origins[object]), from.minimum, path.filename(origins[from.from]), from.symbol))
        end
    end
    if #taken > 0 then
        cprint("${color.warning}note:${clear} %d objects carry no API the registry can place and take the highest minimum of the objects they name: %s",
               #taken, table.concat(taken, " "))
    end
    if #unreached > 0 then
        local named = {}
        for _, object in ipairs(unreached) do
            table.insert(named, path.filename(origins[object]))
        end
        cprint("${color.warning}note:${clear} %d objects carry no API the registry can place and no other object names them, so every band from iOS %s keeps them: %s",
               #named, opt.deployment, table.concat(named, " "))
    end
    local placed, pending = {}, {}
    for _, object in ipairs(objects) do
        local minimum = found[object]
        if minimum and dyld.compare_versions(minimum, opt.deployment) > 0 then
            local source = origins[object]
            if minimum ~= top then
                object = path.join(opt.builddir, "objects-" .. minimum, path.filename(path.directory(object)), path.filename(object))
                os.mkdir(path.directory(object))
                table.insert(pending, {opt = at(minimum), source = source, object = object})
            end
            placed[source] = {minimum = minimum, object = object}
        end
    end
    compile_all(opt, pending)
    return placed
end

local LADDERS = {}

-- The cache ladder for one architecture, oldest release first: dyld.held_ladder(), which
-- release-split.lua walks as well, so this check answers to the same measurement instead of a
-- second copy of it.
local function ladder(architecture)
    LADDERS[architecture] = LADDERS[architecture] or dyld.held_ladder(compatible(architecture))
    return LADDERS[architecture]
end

-- The release each of symbols first-appears exporting, walking the real cache ladder oldest to newest --
-- the same measurement release-split.lua makes, not the SDK header's own availability annotation.
-- A header can name a later release than the one that actually already exports the symbol (measured
-- for UIKeyboardIsLocalUserInfoKey: the SDK 16.4 header says ios(9.0), the real armv7 cache of 8.0
-- already exports it), and this function exists so the same object-splitting rule answers to the
-- fact, not the annotation. A symbol counts only where a client binds it, in the library the SDK
-- puts it in (dyld.exported_at). {symbol = release}, with no entry for a symbol no held release
-- exports, where the header/registry fallback in releases_in() below is the only source left.
local function measured_introduced(opt, symbols)
    return dyld.first_releases(ladder(opt.architecture), opt.sdkdir, symbols)
end

-- The releases one object's exported API arrived in, {version = {names}}, and the names no source
-- can place at all. Measured, not judged: an object mixing releases is reported by the caller, so
-- one pass can name every such object instead of stopping at the first. A name arrives with the
-- first of its symbols: a release can export a class without its metaclass (NaturalLanguage of
-- 12.0 exports _OBJC_CLASS_$_NLTokenizer, and its metaclass only from 16.0), and the class is the API.
-- What releases_in() measures of one object before the registry is asked: its names in the order
-- of its symbols, and for each the release the held caches or the SDK's header place it at, or false.
-- It is a function of the object, the source and the headers it was compiled from and the held
-- ladder, so an object of the store keeps it beside itself; the registry, which a stack changes
-- more often than any of those, is asked again every time.
local function measured_names(opt, source, object)
    local file
    if opt.store and KEYS[object] then
        local signature = {}
        for _, step in ipairs(ladder(opt.architecture)) do
            table.insert(signature, step.release .. "=" .. step.architecture .. "=" .. step.source)
        end
        -- the measurement's own inputs (its code, the SDK's .tbd files, the rungs), and this file, whose
        -- rules name the symbols and read the header's answer
        local key = hash.strhash128("charon-releases-2\n" .. KEYS[object] .. "\n" .. opt.sdkdir .. "\n" .. table.concat(signature, "\n")
                                    .. "\n" .. dyld.first_release_key(ladder(opt.architecture), opt.sdkdir) .. "\n" .. own_text())
        file = path.join(opt.store, "releases", key:sub(1, 2), key .. ".lua")
        local saved = os.isfile(file) and io.load(file)
        if saved then
            os.touch(file)
            return saved.names, saved.earliest
        end
    end
    local names, earliest = {}, {}
    local symbols = exported_symbols(object)
    local first = measured_introduced(opt, symbols)
    for _, symbol in ipairs(symbols) do
        local name = symbol:match("^_OBJC_CLASS_%$_(.+)$") or symbol:match("^_OBJC_METACLASS_%$_(.+)$")
                     or symbol:match("^_OBJC_IVAR_%$_(.-)%.") or symbol:sub(2)
        if earliest[name] == nil then
            table.insert(names, name)
            earliest[name] = false
        end
        local version = first[symbol]
        if version and (not earliest[name] or dyld.compare_versions(version, earliest[name]) < 0) then
            earliest[name] = version
        end
    end
    for _, name in ipairs(names) do
        if not earliest[name] then
            local dump = os.iorunv(clang(opt, {"-fsyntax-only", "-w", "-Xclang", "-ast-dump", "-Xclang", "-ast-dump-filter", "-Xclang", name, source}, true))
            earliest[name] = introduced_version(dump, name) or false
        end
    end
    if file then
        store_folder(path.directory(file))
        local temporary = file .. "." .. hash.strhash32(object .. os.mclock()) .. ".tmp"
        io.save(temporary, {names = names, earliest = earliest})
        os.mv(temporary, file)
    end
    return names, earliest
end

function releases_in(opt, source, object)
    local names, measured = measured_names(opt, source, object)
    local earliest = {}
    for _, name in ipairs(names) do
        local version = measured[name] or nil
        if not version then
            -- API that is Foundation's own and in no header of the SDK, which a
            -- backport still carries under Apple's name because an archive holds
            -- it: the registry is what says when it arrived.
            -- Through entry_of, not a raw lookup: the registry spells a function with its
            -- parentheses and a member with its class, and the name here is the symbol's, so
            -- `listed[name]` misses every function the registry carries. An 18.2 function on a
            -- port whose held caches end at 18.0 is exactly that case: no cache places it, the
            -- source says nothing, and the registry is the only thing that knows.
            local entry = entry_of(listed(opt.root), name)
            version = entry and entry.status == "implemented" and entry.introduced or nil
        end
        earliest[name] = version or false
    end
    local releases, unplaced = {}, {}
    for _, name in ipairs(names) do
        local version = earliest[name] or nil
        if version then
            releases[version] = releases[version] or {}
            table.insert(releases[version], name)
        else
            table.insert(unplaced, name)
        end
    end
    return releases, unplaced
end

-- What is wrong with one object's releases, or nil when it holds API of exactly one.
local function misplaced(source, releases, unplaced)
    if #unplaced > 0 then
        return string.format("neither the SDK, the registry nor a held release's own cache says which iOS release %s arrived in, and %s defines it, so no band can hold it",
                             table.concat(unplaced, " "), path.filename(source))
    end
    local found = table.orderkeys(releases)
    table.sort(found, function (a, b) return dyld.compare_versions(a, b) < 0 end)
    if #found > 1 then
        local described = {}
        for _, version in ipairs(found) do
            table.insert(described, string.format("%s from iOS %s", table.concat(releases[version], " "), version))
        end
        return string.format("%s defines %s; an object carries API that arrived in one release, so split it", path.filename(source), table.concat(described, " and "))
    end
end

local INTRODUCED = {}

local function measured(opt, source, object)
    local key = object .. ":" .. (KEYS[object] or hash.sha256(object))
    if not INTRODUCED[key] then
        local releases, unplaced = releases_in(opt, source, object)
        INTRODUCED[key] = {releases = releases, unplaced = unplaced, problem = misplaced(source, releases, unplaced)}
    end
    return INTRODUCED[key]
end

function introduced_in(opt, source, object)
    local found = measured(opt, source, object)
    if found.problem then
        raise(found.problem)
    end
    return table.orderkeys(found.releases)[1]
end

function later_than(opt, release)
    return function (object)
        return dyld.compare_versions(introduced_in(opt, opt.origins[object], object), release) > 0
    end
end

-- Every object of every library is measured before anything is refused, so a tree with several
-- mixed objects names all of them in one run rather than one per build.
function check_releases(opt, objects, origins)
    local problems = {}
    for _, library in ipairs(LIBRARIES) do
        if not opt.libraries or table.contains(opt.libraries, library.name) then
            for _, object in ipairs(objects[library.name]) do
                if #exported_symbols(object) > 0 then
                    local problem = measured(opt, origins[object], object).problem
                    if problem then
                        table.insert(problems, string.format("  %s: %s", library.name, problem))
                    end
                end
            end
        end
    end
    if #problems > 0 then
        raise("%d objects hold API no single release introduced:\n%s", #problems, table.concat(problems, "\n"))
    end
end

-- A class the release carries but does not export is one a band cannot drop:
-- nothing says it is there in the symbols, and it cannot be re-exported. The
-- library would define a second class of that name, and the runtime would take
-- one of the two, so the band asks the release's Objective-C metadata as well
-- and refuses what it would duplicate. What it lets through is a proxy: an
-- object that defines the class under a name of Charon's own and exports the
-- release's name as an alias of it, for a port to link against while messages
-- go to the release's class.
function duplicated(objects, classes)
    local found = {}
    for _, object in ipairs(objects) do
        local defined = {}
        for _, symbol in ipairs(defined_symbols(object, true)) do
            defined[symbol] = true
        end
        for _, symbol in ipairs(exported_symbols(object)) do
            local class = symbol:match("^_OBJC_CLASS_%$_(.+)$")
            if class and classes[class] and not defined["_OBJC_CLASS_$_Charon" .. class] then
                found[class] = path.filename(object)
            end
        end
    end
    local named = table.orderkeys(found)
    local told = {}
    for _, class in ipairs(named) do
        table.insert(told, string.format("%s (%s)", class, found[class]))
    end
    return told
end

function band_ranges(points, listed)
    local ranges = {}
    for index, point in ipairs(points) do
        local following = points[index + 1]
        local first, last
        for _, version in ipairs(listed) do
            if dyld.compare_versions(version, point) >= 0 and (not following or dyld.compare_versions(version, following) < 0) then
                first = first or version
                last = version
            end
        end
        if not first and index == 1 then
            raise("no firmware in the catalog runs iOS %s or later%s, so its API has no band", point, following and (" and before " .. following) or "")
        end
        if first then
            table.insert(ranges, {point = point, first = first, last = last})
        end
    end
    return ranges
end

local function release_cache(opt, architectures, release)
    local held = held_cache(opt.architecture, release)
    if held then
        return held
    end
    local cache, found = firmware.ensure(architectures[release], release, {tool = opt.tool})
    if found ~= release then
        raise("the band of iOS %s is checked against that release, and the %s firmware nearest to it is %s", release, architectures[release], tostring(found))
    end
    return cache
end

local function staged_libraries(opt)
    local staged = {}
    for _, library in ipairs(LIBRARIES) do
        if not opt.libraries or table.contains(opt.libraries, library.name) then
            table.insert(staged, library)
        end
    end
    return staged
end

-- The bands the package stages, {point, first, last} each, and the architecture of every firmware
-- the catalog lists by release: a band point is every release an object's API arrived in after the
-- deployment and every registry minimum above it, and a band is checked against the first and the
-- last release it runs on.
local function band_plan(opt, objects)
    local points = {[opt.deployment] = true}
    for _, library in ipairs(staged_libraries(opt)) do
        for _, object in ipairs(objects[library.name]) do
            if #exported_symbols(object) > 0 then
                local version = introduced_in(opt, opt.origins[object], object)
                if dyld.compare_versions(version, opt.deployment) > 0 then
                    points[version] = true
                end
            end
            if (opt.minimums or {})[object] then
                points[opt.minimums[object]] = true
            end
        end
    end
    points = table.orderkeys(points)
    table.sort(points, function (a, b) return dyld.compare_versions(a, b) < 0 end)
    local architectures = {}
    for _, architecture in ipairs(compatible(opt.architecture)) do
        for _, version in ipairs(firmware.versions(architecture)) do
            architectures[version] = architectures[version] or architecture
        end
    end
    local listed = table.orderkeys(architectures)
    table.sort(listed, function (a, b) return dyld.compare_versions(a, b) < 0 end)
    return band_ranges(points, listed), architectures
end

-- Staging every band checks its imports against the caches of its first and last release, which a
-- build of the deployment's band alone never opens: a new band point (7.1, from one registry row)
-- passed the gate and stopped the canon on a cache nobody held. A complete build names every such
-- release up front, with its band and the command that fetches it. The answer holds for the ladder
-- as it is held: a band point is the first held release that exports an object's API, so a fetched
-- cache can move a point earlier and end the band before it on another release (measured: fetching
-- 7.1, 8.1.2 and 9.2 moved the ends to 7.0.6, 8.1.1 and 9.1, and fetching those moved them to 8.1
-- and 9.0.2). Only the whole ladder would fix the points; its size keeps it unheld. A cache is not the
-- whole release either: a public framework can ship as a file beside it (PushKit on 8.0 and 8.1.3),
-- so a band end is held only with the libraries fetch takes from outside its cache.
function check_band_caches(opt, objects)
    local ranges, architectures = band_plan(opt, objects)
    local missing = {}
    for _, range in ipairs(ranges) do
        for _, release in ipairs(table.unique({range.first, range.last})) do
            local held = held_cache(opt.architecture, release)
            local cached = held and path.filename(held):match("^dyld_shared_cache_(.+)$")
            if not held then
                table.insert(missing, string.format("  iOS %s, an end of the band of iOS %s (%s to %s): xmake firmware --arch=%s fetch %s",
                                                    release, range.point, range.first, range.last, architectures[release], release))
            elseif cached and not os.isdir(dyld.outside_source(path.directory(held), cached)) then
                table.insert(missing, string.format("  iOS %s, an end of the band of iOS %s (%s to %s), without the libraries it carries outside its shared cache: xmake firmware --arch=%s fetch %s",
                                                    release, range.point, range.first, range.last, cached, release))
            end
        end
    end
    if #missing > 0 then
        raise("the staged bands cannot have their imports checked: %s does not hold all of %d releases they are checked against\n%s",
              dyld.root(), #missing, table.concat(missing, "\n"))
    end
    return ranges
end

function stage_bands(opt)
    opt = table.join(opt, {triple = opt.architecture .. "-apple-ios" .. opt.deployment})
    local attach, objects, origins, minimums = compiled(opt)
    opt = table.join(opt, {origins = origins, minimums = minimums})
    check_releases(opt, objects, origins)
    local ranges, architectures = band_plan(opt, objects)
    local home = path.join(opt.stage, INSTALL_FOLDER)
    local lines = {}
    for _, range in ipairs(ranges) do
        local releases, signatures, caches = {}, {}, {}
        for _, release in ipairs(table.unique({range.first, range.last})) do
            local file = release_cache(opt, architectures, release)
            local found = loaded(file, opt.architecture)
            table.insert(releases, found)
            table.insert(caches, {cache = file, release = release})
            local reexported = {}
            for _, library in ipairs(staged_libraries(opt)) do
                local _, symbols = band(found.exports, objects[library.name], later_than(opt, release), {release = release, minimums = opt.minimums})
                table.join2(reexported, symbols)
            end
            signatures[release] = table.concat(reexported, " ")
        end
        if signatures[range.first] ~= signatures[range.last] then
            raise("iOS %s and %s export different backported symbols (%s, and %s), although the SDK says nothing the backports define arrived between them",
                  range.first, range.last, signatures[range.first], signatures[range.last])
        end
        local built = {}
        for _, library in ipairs(staged_libraries(opt)) do
            table.insert(built, link(opt, library, attach, objects[library.name], releases, path.join(home, "bands", range.first), caches[1]))
        end
        for index, release in ipairs(table.unique({range.first, range.last})) do
            dyld.check(release_cache(opt, architectures, release), built)
            check_categories(releases[index], release_inventory(caches[index].cache), built, opt.architecture, release)
        end
        for index = #built, 1, -1 do
            os.vrunv("xcrun", {"strip", "-x", built[index]})
            signing.sign(opt.ldid, built[index])
        end
        table.insert(lines, range.first .. " " .. range.last)
    end
    io.writefile(path.join(home, "bands", "ranges"), table.concat(lines, "\n") .. "\n")
    return ranges
end

POSTINST = [[
#!/bin/sh
set -e
root="${DPKG_ROOT:-}"
home="$root@HOME@"
version=$(sed -n '/<key>ProductVersion<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$root/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)
if [ -z "$version" ]; then
    echo "@PACKAGE@ cannot read ProductVersion from $root/System/Library/CoreServices/SystemVersion.plist, so it cannot pick the libraries for this iOS" >&2
    exit 1
fi
older() {
    left=$1 right=$2
    while [ -n "$left$right" ]; do
        a=${left%%.*} b=${right%%.*}
        if [ "$left" = "$a" ]; then left=; else left=${left#*.}; fi
        if [ "$right" = "$b" ]; then right=; else right=${right#*.}; fi
        if [ "${a:-0}" -lt "${b:-0}" ]; then return 0; fi
        if [ "${a:-0}" -gt "${b:-0}" ]; then return 1; fi
    done
    return 1
}
band=
while read -r first last; do
    if ! older "$version" "$first" && ! older "$last" "$version"; then
        band=$first
    fi
done < "$home/bands/ranges"
if [ -z "$band" ]; then
    echo "@PACKAGE@ holds no libraries built and checked for iOS $version; it holds them for iOS $(sed 's/ / to /' "$home/bands/ranges" | tr '\n' ',' | sed 's/,$//;s/,/, /g')" >&2
    exit 1
fi
for library in "$home/bands/$band"/*.dylib; do
    ln -sf "bands/$band/${library##*/}" "$home/${library##*/}"
done
]]

PRERM = [[
#!/bin/sh
set -e
if [ "$1" = remove ]; then
    for library in "${DPKG_ROOT:-}@HOME@"/*.dylib; do
        if [ -L "$library" ]; then
            rm -f "$library"
        fi
    done
fi
]]

function write_scripts(folder)
    os.tryrm(folder)
    os.mkdir(folder)
    for name, text in pairs({postinst = POSTINST, prerm = PRERM}) do
        io.writefile(path.join(folder, name), (text:gsub("@HOME@", INSTALL_FOLDER):gsub("@PACKAGE@", PACKAGE)))
    end
end

-- The 12th search bundle isn't a band: it carries none of this port's own API, only a bridge from
-- CharonSpotlightStore (libCoreSpotlightBackports.dylib, resolved by name at runtime, not linked -
-- see CharonSearchDatastore.m) to Search.framework's own SPSearchDatastore, so it needs no
-- per-release symbol-availability logic and is built once, at the port's own deployment minimum,
-- for /System/Library/SearchBundles/ - the directory
-- .agent-work/handoffs/2026-09-23-corespotlight-searchbundle-measurement.md measured
-- Search.framework's own -_loadSearchBundles to scan - rather than staged per band like the dylibs.
local function corespotlight_staged(opt)
    for _, library in ipairs(staged_libraries(opt)) do
        if library.name == "CoreSpotlightBackports" then
            return true
        end
    end
    return false
end

-- write_deb compiles the bundle, so its source keeps being checked, but does not place it in the
-- package: sending -appendResults: from -performQuery:withResultsPipe: puts searchd into
-- uninterruptible sleep until kill -9, measured on an iPad 2 (6.1.3) and recorded in
-- facts/CoreSpotlight/CoreSpotlight.md. A package carrying it hangs the system search on every
-- device that installs it. It goes back into the stage only once that hang is fixed and the query
-- path is measured green on the device; until then write_deb says so, with the reason.
local SEARCHBUNDLE_WITHHELD = "sending -appendResults: hangs searchd (measured on an iPad 2, facts/CoreSpotlight/CoreSpotlight.md)"

function write_searchbundle(opt)
    if not corespotlight_staged(opt) then
        return
    end
    local folder = path.join(opt.builddir, "searchbundle", "org.charon.corespotlight.searchBundle")
    os.tryrm(folder)
    os.mkdir(folder)
    local source = path.join(opt.root, "CoreSpotlight", "SearchBundle", "CharonSearchDatastore.m")
    local output = path.join(folder, "org.charon.corespotlight")
    local triple = opt.architecture .. "-apple-ios" .. opt.deployment
    os.vrunv(driver(opt, {"-target", triple, "-isysroot", opt.sdkdir, "-fuse-ld=" .. opt.ld, "-fobjc-arc",
                          "-bundle", "-Os", "-g0", "-Wall",
                          "-DCHARON_BACKPORTS_INSTALL_FOLDER=\"" .. INSTALL_FOLDER .. "\"", "-o", output, source, "-framework", "Foundation"}))
    os.vrunv("xcrun", {"strip", "-x", output})
    signing.sign(opt.ldid, output)
    os.cp(path.join(opt.root, "CoreSpotlight", "SearchBundle", "Info.plist"), path.join(folder, "Info.plist"))
    cprint("${color.warning}withheld:${clear} org.charon.corespotlight.searchBundle is built at %s but not packaged: %s", folder, SEARCHBUNDLE_WITHHELD)
end

function write_deb(opt)
    local debian = import("debian", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})
    local stage = path.join(opt.builddir, "stage")
    os.tryrm(stage)
    local ranges = stage_bands(table.join(opt, {stage = stage}))
    write_searchbundle(table.join(opt, {stage = stage}))
    local covered = {}
    for _, range in ipairs(ranges) do
        table.insert(covered, range.first == range.last and range.first or (range.first .. " to " .. range.last))
    end
    local control = path.join(opt.builddir, "control")
    io.writefile(control, table.concat({
        "Package: " .. PACKAGE,
        "Name: Apple API backports",
        "Architecture: iphoneos-arm",
        "Section: System",
        "Description: Objective-C classes and methods of later iOS releases for the releases that lack them, as the libraries ports built with Charon load from " .. INSTALL_FOLDER .. "; libraries built and checked for iOS " .. table.concat(covered, ", ")
    }, "\n") .. "\n")
    local scripts = path.join(opt.builddir, "scripts")
    write_scripts(scripts)
    return debian.write({control = control, version = opt.version, root = stage, scripts = scripts, outputdir = opt.outputdir}), ranges
end
