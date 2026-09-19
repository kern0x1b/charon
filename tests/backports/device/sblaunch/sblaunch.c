#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: charon-sblaunch <bundle identifier>\n");
        return 2;
    }
    void *services = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    int (*launch)(CFStringRef, Boolean) = services ? (int (*)(CFStringRef, Boolean))dlsym(services, "SBSLaunchApplicationWithIdentifier") : NULL;
    if (!launch) {
        fprintf(stderr, "charon-sblaunch: SpringBoardServices has no SBSLaunchApplicationWithIdentifier\n");
        return 3;
    }
    mach_port_t (*server)(void) = (mach_port_t (*)(void))dlsym(services, "SBSSpringBoardServerPort");
    void (*lock_status)(mach_port_t, bool *, bool *) = (void (*)(mach_port_t, bool *, bool *))dlsym(services, "SBGetScreenLockStatus");
    bool locked = false, passcode = false;
    if (server && lock_status)
        lock_status(server(), &locked, &passcode);
    CFStringRef identifier = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
    int result = launch(identifier, false);
    CFRelease(identifier);
    if (result != 0) {
        fprintf(stderr, "charon-sblaunch: SpringBoard refused %s with %d%s\n", argv[1], result,
                locked ? (passcode ? " (the screen is locked with a passcode)" : " (the screen is locked)") : "");
        return 1;
    }
    return 0;
}
