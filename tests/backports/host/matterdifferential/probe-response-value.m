#import <Foundation/Foundation.h>
#import <Matter/Matter.h>
#import <objc/runtime.h>

static void probe(const char *label, Class cls, SEL sel, id fixture)
{
    NSError *error = nil;
    id made = [(id)cls alloc];
    made = [made initWithResponseValue:fixture error:&error];
    if (!made) {
        printf("%-34s -> nil   error domain=%s code=%ld\n", label,
               error ? [[error domain] UTF8String] : "(none handed out)",
               error ? (long)[error code] : 0L);
        if (error) { printf("%-34s    userInfo: %s\n", "", [[error localizedDescription] UTF8String]); }
        return;
    }
    printf("%-34s -> %s", label, class_getName([made class]));
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList([made class], &count);
    for (unsigned i = 0; i < count; i++) {
        const char *name = property_getName(props[i]);
        id got = [made valueForKey:[NSString stringWithUTF8String:name]];
        printf("  %s=%s", name, got ? [[got description] UTF8String] : "nil");
    }
    free(props);
    printf("\n");
}

int main(void)
{
    Class cls = NSClassFromString(@"MTRAccessControlClusterReviewFabricRestrictionsResponseParams");
    if (!cls) { printf("class not found in this SDK\n"); return 1; }
    printf("class %s, responds to initWithResponseValue:error: %d\n\n",
           class_getName(cls), [cls instancesRespondToSelector:@selector(initWithResponseValue:error:)]);

    // 1. a well-formed command data response: one unsigned-integer field, field id 0.
    NSDictionary *valid = @{
        MTRCommandPathKey: @1,
        MTRTypeKey: @{ @0: MTRUnsignedIntegerValueType },
        MTRValueKey: @{ @0: @4711 } };
    probe("valid command data response", cls, NULL, valid);

    // 2. malformed: the value for a declared field is the wrong class of object.
    NSDictionary *malformed = @{
        MTRCommandPathKey: @1,
        MTRTypeKey: @{ @0: MTRUnsignedIntegerValueType },
        MTRValueKey: @{ @0: @"not a number" } };
    probe("malformed value for the field", cls, NULL, malformed);

    // 3. malformed shape: not a command data response at all.
    probe("not a command data response", cls, NULL, @{ @"unrelated": @1 });
    // 4. nil
    probe("nil", cls, NULL, nil);
    return 0;
}
