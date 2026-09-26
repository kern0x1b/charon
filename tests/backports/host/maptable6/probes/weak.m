#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// __weak to objects whose classes keep their own retain count (CoreFoundation's bridged ones), then the object released:
// set and nil on 5.0, 5.1.1 and 6.0, an abort for NSMutableString on 4.3 (arclite), as the facts say. Built and run by
// probes.sh (MAPTABLE6_PROBES=1 adds it to emulate/xmake.lua); 4.3 aborts partway, so its run is not a pass.
static void probe(const char *name, id (^make)(void))
{
    __weak id weak;
    printf("%s: ", name);
    @autoreleasepool {
        id object = make();
        printf("%s, ", class_getName(object_getClass(object)));
        weak = object;
        printf("weak %s, ", weak ? "set" : "nil");
    }
    printf("after release: %s\n", weak ? "STILL SET" : "nil");
    fflush(stdout);
}

int main(void)
{
    @autoreleasepool {
        int n = 1000;
        probe("NSObject", ^id { return [[NSObject alloc] init]; });
        probe("NSMutableString", ^id { return [[NSMutableString alloc] initWithFormat:@"k%d", n]; });
        probe("NSString", ^id { return [[NSString alloc] initWithFormat:@"key %d", n]; });
        probe("NSNumber", ^id { return [[NSNumber alloc] initWithInt:n * 1000]; });
        probe("NSDate", ^id { return [[NSDate alloc] initWithTimeIntervalSince1970:n]; });
        probe("NSArray", ^id { return [[NSArray alloc] initWithObjects:@"a", [NSNumber numberWithInt:n], nil]; });
    }
    return 0;
}
