/* unavailableinit.m - does Apple's own class define -init, or does it carry NSObject's?
 *
 * This is the oracle for five registry rows that say a MetalKit class has no -init of its own.
 * MetalKit's headers declare `-init NS_UNAVAILABLE` on MTKMesh, MTKSubmesh, MTKMeshBuffer,
 * MTKMeshBufferAllocator and MTKTextureLoader, so no application compiled against them can call it and
 * the port defines no such method. That is only the same answer as Apple's if Apple's class does not
 * define one either, and that is what this measures.
 *
 * `class_getInstanceMethod` SEARCHES SUPERCLASSES, so answering non-nil proves nothing on its own:
 * every NSObject subclass answers it. What is asked is whether the IMP is the superclass's own, and a
 * class that overrides -init differs there. The controls are what make that worth asking:
 *
 *   * CharonInitOverrider, a class of this file that DOES override -init, so an override is shown to
 *     be visible to this measurement. Guessing at a Foundation class for this was the first spelling
 *     and it was wrong twice over: NSObject has no superclass at all, so "the same as the
 *     superclass" cannot hold for it, and NSMutableDictionary turns out not to override -init.
 *   * ZZZNoSuchNameCharonR16, a class the framework does not have, so a class that answers cannot be
 *     confused with one that does not.
 */
#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>

/* THE CONTROL CLASS: it overrides -init, which is the thing the measurement has to be able to see. */
@interface CharonInitOverrider : NSObject
@end

@implementation CharonInitOverrider
- (instancetype)init { return [super init]; }
@end

static int failures;
static int checks;

typedef struct { BOOL found; BOOL sameAsSuper; BOOL hasOwnInit; const char *superName; } CharonInitAnswer;

static CharonInitAnswer answerFor(Class c)
{
    CharonInitAnswer a;
    Method found = class_getInstanceMethod(c, @selector(init));
    Class super = class_getSuperclass(c);
    Method inherited = super ? class_getInstanceMethod(super, @selector(init)) : NULL;
    a.found = found != NULL;
    a.sameAsSuper = found && inherited &&
        method_getImplementation(found) == method_getImplementation(inherited);
    a.superName = super ? class_getName(super) : "(none)";
    unsigned own = 0;
    Method *list = class_copyMethodList(c, &own);
    a.hasOwnInit = 0;
    for (unsigned i = 0; i < own; i++)
        if (sel_isEqual(method_getName(list[i]), @selector(init))) { a.hasOwnInit = 1; break; }
    free(list);
    return a;
}

static void check(int ok, NSString *line)
{
    checks++;
    if (ok) printf("  ok   %s\n", [line UTF8String]);
    else { printf("  FAIL %s\n", [line UTF8String]); failures++; }
}

/* THE MEASUREMENT: the class answers init, the answer is NSObject's own, and the class's OWN method
 * list has no entry for the selector. */
static void expectNoInitOfItsOwn(Class c, const char *label)
{
    CharonInitAnswer a = answerFor(c);
    check(a.found && a.sameAsSuper && !a.hasOwnInit,
          ([NSString stringWithFormat:@"%s answers init, and it is %s's own: the class defines none (superclass %s)",
            label, strcmp(a.superName, "(none)") == 0 ? "NSObject" : a.superName, a.superName]));
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        printf("does Apple's own MetalKit class define -init?\n");

        CharonInitAnswer overrider = answerFor([CharonInitOverrider class]);
        check(overrider.found && !overrider.sameAsSuper && overrider.hasOwnInit,
              @"the control: a class that overrides -init is seen to override it, so a class that does not is not hiding one");

        expectNoInitOfItsOwn([MTKMesh class], "MTKMesh");
        expectNoInitOfItsOwn([MTKSubmesh class], "MTKSubmesh");
        expectNoInitOfItsOwn([MTKMeshBuffer class], "MTKMeshBuffer");
        expectNoInitOfItsOwn([MTKMeshBufferAllocator class], "MTKMeshBufferAllocator");
        expectNoInitOfItsOwn([MTKTextureLoader class], "MTKTextureLoader");

        check(NSClassFromString(@"ZZZNoSuchNameCharonR16") == nil,
              @"the control: ZZZNoSuchNameCharonR16 is not a class of this framework");
    }
    printf("unavailableinit: %d check(s), %d failure(s)\n", checks, failures);
    return failures == 0 ? 0 : 1;
}