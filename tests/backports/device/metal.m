#import <Metal/Metal.h>
#include <dlfcn.h>
#import "check.h"

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1)
            charon_log_to(@(argv[1]));
        Dl_info info;
        CHECK(dladdr((void *)MTLCreateSystemDefaultDevice, &info) != 0, "the address of the function is known");
        CHECK_EQUAL(@(info.dli_fname).lastPathComponent, @"libMetalBackports.dylib", "it comes from the backports");
        CHECK(MTLCreateSystemDefaultDevice() == nil, "there is no default device");
        CHECK(MTLCreateSystemDefaultDevice() == nil, "and none the second time");
        CHECK(NSClassFromString(@"MTKView") == Nil, "MetalKit is not there");
        CHECK(NSProtocolFromString(@"MTLDevice") == nil, "the protocol of a device is not there");
        printf("%d checks, %d failed\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
