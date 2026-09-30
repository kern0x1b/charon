#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <objc/runtime.h>

static void show(const char *label, id object)
{
    printf("%-46s %s", label, object ? class_getName([object class]) : "(nil)");
    if (object) {
        unsigned n = 0;
        objc_property_t *props = class_copyPropertyList([object class], &n);
        for (unsigned i = 0; i < n; i++) {
            id got = [object valueForKey:[NSString stringWithUTF8String:property_getName(props[i])]];
            printf("  %s=%s", property_getName(props[i]),
                   got ? [[got description] UTF8String] : "nil");
        }
        free(props);
        printf("  hash=%lu", (unsigned long)[object hash]);
        printf("  description=%s", [[object description] UTF8String]);
    }
    printf("\n");
}

int main(void)
{
    MTRCommandPath *cmd = [MTRCommandPath commandPathWithEndpointID:@1 clusterID:@2 commandID:@3];
    show("commandPath(1,2,3)", cmd);
    MTRAttributePath *attr = [MTRAttributePath attributePathWithEndpointID:@1 clusterID:@2 attributeID:@7];
    show("attributePath(1,2,7)", attr);
    MTREventPath *event = [MTREventPath eventPathWithEndpointID:@1 clusterID:@2 eventID:@5];
    show("eventPath(1,2,5)", event);

    // copy, equality, hash
    MTRCommandPath *copy = [cmd copy];
    printf("copy is a %s, isEqual to the original: %d, same hash: %d\n",
           class_getName([copy class]), [copy isEqual:cmd], [copy hash] == [cmd hash]);
    MTRCommandPath *same = [MTRCommandPath commandPathWithEndpointID:@1 clusterID:@2 commandID:@3];
    printf("an equal path built again: isEqual %d, same hash %d\n", [same isEqual:cmd], [same hash] == [cmd hash]);
    MTRCommandPath *other = [MTRCommandPath commandPathWithEndpointID:@1 clusterID:@2 commandID:@4];
    printf("a different path: isEqual %d, same hash %d\n", [other isEqual:cmd], [other hash] == [cmd hash]);

    // the initialisers the header makes unavailable
    // -init is NS_UNAVAILABLE on the header, so it is read through the runtime rather than called:
    // the port has to make the same call fail, and a compile-time check cannot see a runtime one.
    Class base = NSClassFromString(@"MTRClusterPath");
    printf("MTRClusterPath declares -init unavailable in the header; the runtime selector %s\n",
           class_getInstanceMethod(base, @selector(init)) ? "EXISTS" : "does not exist");
    printf("responds to NSCopying %d, NSSecureCoding %d\n",
           [cmd conformsToProtocol:@protocol(NSCopying)], [attr conformsToProtocol:@protocol(NSSecureCoding)]);
    return 0;
}
