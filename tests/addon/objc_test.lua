import("fixtures")

local MESSAGES = [[
#import <Foundation/Foundation.h>
int main(void) { return [[NSMutableArray array] count] + [[NSObject new] hash] > 0; }
]]

local SELECTORS = [[
#import <Foundation/Foundation.h>
@protocol ProbeDelegate <NSObject>
@optional
- (void)probeDidFinishWithCount:(NSUInteger)count;
@end
@interface NSString (Probe)
- (NSString *)probe_reversed;
@end
@implementation NSString (Probe)
- (NSString *)probe_reversed { return self; }
@end
@interface Probe : NSObject
@property (nonatomic, assign) id<ProbeDelegate> delegate;
@end
@interface Listener : NSObject <ProbeDelegate>
@end
@implementation Listener
@end
@implementation Probe
- (void)finish {
    if ([self.delegate respondsToSelector:@selector(probeDidFinishWithCount:)]) {
        [self.delegate probeDidFinishWithCount:[@"x" probe_reversed].length];
    }
}
@end
]]

local function linker_version(opt)
    local out, errors = os.iorunv(opt.ld64, {"-v"})
    return ((out or "") .. (errors or "")):match("PROJECT:ld64%-(%S+)")
end

local function stub_failures(folder, opt)
    local found = {}
    local version = linker_version(opt)
    io.writefile(path.join(folder, "messages.m"), MESSAGES)
    local linked = {"-target", "arm64-apple-ios7.0", "-isysroot", opt.sdk, "-w", "-O2", "-fuse-ld=" .. opt.ld64, "-framework", "Foundation", "messages.m"}
    local unversioned = fixtures.refusal(function () fixtures.run(folder, opt.clang, table.join(linked, {"-o", "unversioned"})) end) or ""
    if not unversioned:find("objc_msgSendClass$", 1, true) then
        table.insert(found, "clang without -mlinker-version no longer emits class message stubs ld64 cannot synthesize; the toolchain may stop naming the linker version")
    end
    local errors = fixtures.refusal(function () fixtures.run(folder, opt.clang, table.join(linked, {"-mlinker-version=" .. tostring(version), "-o", "versioned"})) end)
    if errors then
        table.insert(found, "an arm64 executable for iOS 7.0 compiled for ld64 " .. tostring(version) .. " must link with it: " .. errors)
    else
        local imports = fixtures.run(folder, "xcrun", {"nm", "-u", "versioned"})
        if not imports:find("_objc_msgSend\n", 1, true) or imports:find("objc_msgSend%$") then
            table.insert(found, "messages compiled for ld64 must reach _objc_msgSend itself, not a selector stub: " .. imports)
        end
    end
    return found
end

local function selector_failures(folder, opt)
    local found = {}
    local objc = import("apple.objc", {rootdir = opt.modules, anonymous = true})
    io.writefile(path.join(folder, "selectors.m"), SELECTORS)
    for _, case in ipairs({{"armv7", "armv7-apple-ios6.0", "plain"}, {"arm64", "arm64-apple-ios7.0", "plain"},
                           {"armv7", "armv7-apple-ios6.0", "charon_catlist", {"-Wl,-rename_section,__DATA,__objc_catlist,__DATA,__charon_catlist"}}}) do
        local library = "libselectors_" .. case[1] .. "_" .. case[3] .. ".dylib"
        fixtures.run(folder, opt.clang, table.join({"-target", case[2], "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-w", "-fobjc-arc",
                                                    "-mlinker-version=" .. linker_version(opt), "-fuse-ld=" .. opt.ld64, "-dynamiclib", "-framework", "Foundation",
                                                    "selectors.m", "-o", library}, case[4] or {}))
        if case[4] and fixtures.run(folder, "xcrun", {"otool", "-l", library}):find("__objc_catlist", 1, true) then
            table.insert(found, "ld64 kept __objc_catlist under -rename_section, which the backports rely on")
        end
        local selectors = objc.binary_selectors(path.join(folder, library), case[1])
        for _, name in ipairs({"probe_reversed", "probeDidFinishWithCount:"}) do
            if not selectors.used["-" .. name] then
                table.insert(found, case[1] .. " " .. case[3] .. ": the library sends " .. name .. ", and its selector references must list it")
            elseif not selectors.implemented["-" .. name] then
                table.insert(found, case[1] .. " " .. case[3] .. ": " .. name .. " is defined by the library itself, in a category on a class it imports or a protocol it declares, and must count as implemented")
            end
        end
    end
    return found
end

function failures(opt)
    local found = {}
    local folder = fixtures.scratch()
    for _, check in ipairs({stub_failures, selector_failures}) do
        table.join2(found, check(folder, opt))
    end
    os.tryrm(folder)
    return found
end
