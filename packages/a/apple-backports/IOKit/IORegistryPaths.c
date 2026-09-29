#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

// What iOS 15 and 9 added to IOKit, over the two functions the release already exports.
// IORegistryEntryCopyFromPath is the release's own IORegistryEntryFromPath with the path a caller
// has as a CFString, and IORegistryEntryCopyPath is the release's own IORegistryEntryGetPath with
// the path it fills a buffer with given back as a CFString; both are +1 as their names promise.
// kIOMainPortDefault is the MACH_PORT_NULL the IOKit headers call a synonym for NULL, and is 0 in
// the arm64e shared cache of iOS 18.0 as well (facts/IOKit/IORegistryPaths.md).
//
// A .c file of this package is compiled hidden, so what it must export says so itself, the way
// Foundation's CFBoolean constants do. An entry of 0 and a nil path are answered rather than
// dereferenced: the host reads through both and crashes, and an API of this port never crashes the
// caller.

#define CHARON_IOKIT_EXPORT __attribute__((visibility("default")))

CHARON_IOKIT_EXPORT const mach_port_t kIOMainPortDefault = MACH_PORT_NULL;

CHARON_IOKIT_EXPORT kern_return_t IOMainPort(mach_port_t bootstrapPort, mach_port_t *mainPort)
{
    if (mainPort == 0) {
        return KERN_INVALID_ARGUMENT;
    }
    *mainPort = kIOMainPortDefault;
    return KERN_SUCCESS;
}

CHARON_IOKIT_EXPORT CFStringRef IORegistryEntryCopyPath(io_registry_entry_t entry, const io_name_t plane)
{
    io_string_t path;

    if (entry == 0 || IORegistryEntryGetPath(entry, plane, path) != KERN_SUCCESS) {
        return 0;
    }
    return CFStringCreateWithCString(0, path, kCFStringEncodingUTF8);
}

CHARON_IOKIT_EXPORT io_registry_entry_t IORegistryEntryCopyFromPath(mach_port_t mainPort, CFStringRef path)
{
    io_string_t buffer;

    if (path == 0 || !CFStringGetCString(path, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
        return MACH_PORT_NULL;
    }
    return IORegistryEntryFromPath(mainPort, buffer);
}
