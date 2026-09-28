#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import <stdlib.h>
#import <dlfcn.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// -imageBySettingProperties: and the -properties that reads it back, as **named C functions** with
// (id, SEL) so that anything can call them: the host differential calls them directly on a host
// CIImage, and dladdr over the function then names the image it came from. That matters because the
// macOS framework carries all three of these selectors - the 16.4 iOS header says iOS 6.1.3 has none
// of them, and the 6.1.3 cache has no CoreImage symbol for any of them - so a category is **shadowed**
// on the host and the two processes would measure the framework against itself. Measured, with
// dladdr: 0x198ccfe8c in both processes for imageBySettingProperties:, 0x198cd0a94 for properties.
//
// The +load installs each where the release lacks the selector, and says on stderr which it did, so a
// probe can see that the install ran and what it decided.

static const void *CharonCIPropertiesKey = &CharonCIPropertiesKey;

// -properties as the **framework** had it. Captured by walking the class's own method list and taking
// the first implementation that is not in this image: the runtime attaches a file's categories before
// it runs that file's +load, so class_getInstanceMethod here would return this file's own
// -[CIImage properties] and capture the cycle - the replacement, then the category, then the
// replacement again, which is a stack overflow (measured: 501 hits before the guard page).
//
// The capture is asserted with dladdr: if the implementation chosen is inside this image, the install
// aborts loudly rather than installing a two-frame cycle.
static IMP CharonCIPropertiesRelease;
typedef NSDictionary *(*CharonCIPropertiesFunction)(id, SEL);

// The image this file was loaded from, so "is this implementation ours" is a comparison and not a hope.
static const char *CharonCIPropertiesOwnImage(void)
{
    static const char *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        memset(&info, 0, sizeof info);
        image = dladdr((const void *)&CharonCIPropertiesOwnImage, &info) && info.dli_fname
                    ? strdup(info.dli_fname) : "?";
    });
    return image;
}

static bool CharonCIPropertiesIsOurs(const void *implementation)
{
    Dl_info info;
    memset(&info, 0, sizeof info);
    if (!implementation || !dladdr(implementation, &info) || !info.dli_fname)
        return true;  // cannot tell, so treat it as ours and refuse the install
    return strcmp(info.dli_fname, CharonCIPropertiesOwnImage()) == 0;
}

// The framework's implementation of selector on cls: the first one the class knows that is not ours.
static IMP CharonCIPropertiesReleaseImplementation(Class cls, SEL selector)
{
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    IMP found = NULL;
    for (unsigned i = 0; i < count && !found; i++)
        if (method_getName(methods[i]) == selector && !CharonCIPropertiesIsOurs(method_getImplementation(methods[i])))
            found = method_getImplementation(methods[i]);
    free(methods);
    return found;
}

NSDictionary *charon_CIImage_properties(id image, SEL _cmd)
{
    NSDictionary *held = objc_getAssociatedObject(image, CharonCIPropertiesKey);
    if (held)
        return held;
    if (CharonCIPropertiesRelease)
        return ((CharonCIPropertiesFunction)CharonCIPropertiesRelease)(image, _cmd);
    return @{};
}

CIImage *charon_CIImage_imageBySettingProperties(id image, SEL _cmd, NSDictionary *properties)
{
    // A distinct image, which is what the host hands back: the identity affine transform is the
    // release's own and its output is a new image over the same pixels, so the properties belong to
    // that image and not to the one they were set on.
    if (!properties.count)
        return image;
    CIImage *made = [image imageByApplyingTransform:CGAffineTransformIdentity];
    if (!made)
        return image;
    NSMutableDictionary *merged = [made.properties mutableCopy] ?: [NSMutableDictionary dictionary];
    [merged addEntriesFromDictionary:properties];
    objc_setAssociatedObject(made, CharonCIPropertiesKey, merged, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return made;
}

@interface CharonCIPropertiesInstaller : NSObject
@end

@implementation CharonCIPropertiesInstaller

+ (void)load
{
    struct { const char *key; SEL selector; IMP implementation; const char *types; } entries[] = {
        {"properties", @selector(properties), (IMP)charon_CIImage_properties, "@@:"},
        {"imageBySettingProperties:", @selector(imageBySettingProperties:), (IMP)charon_CIImage_imageBySettingProperties, "@@:@"},
    };
    for (size_t i = 0; i < sizeof entries / sizeof *entries; i++) {
        Method method = class_getInstanceMethod([CIImage class], entries[i].selector);
        if (method) {
            if (strcmp(entries[i].key, "properties") == 0) {
                CharonCIPropertiesRelease = CharonCIPropertiesReleaseImplementation([CIImage class], entries[i].selector);
                if (!CharonCIPropertiesRelease || CharonCIPropertiesIsOurs(CharonCIPropertiesRelease)) {
                    fprintf(stderr, "charon: REFUSING to install -[properties]: the captured implementation is this "
                                    "image's own, and installing it would be a cycle\n");
                    abort();
                }
                fprintf(stderr, "charon: captured the framework's -[properties] outside this image\n");
            }
            method_setImplementation(method, entries[i].implementation);
            fprintf(stderr, "charon: replaced -[%s]\n", entries[i].key);
        } else if (class_addMethod([CIImage class], entries[i].selector, entries[i].implementation, entries[i].types)) {
            fprintf(stderr, "charon: added -[%s], the release does not have it\n", entries[i].key);
        } else {
            fprintf(stderr, "charon: could not install -[%s]\n", entries[i].key);
        }
    }
}

@end

@implementation CIImage (CharonProperties)

// The same selector as the replacement, beside it, so the registry check sees the selector in a
// category. On a release that has the method the installer has already replaced it, and this is what
// it was replaced with.
- (NSDictionary *)properties
{
    return charon_CIImage_properties(self, _cmd);
}

- (CIImage *)imageBySettingProperties:(NSDictionary *)properties
{
    return charon_CIImage_imageBySettingProperties(self, _cmd, properties);
}

@end
