// The classes a release carries without exporting them, which the port exports as aliases
// (packages/a/apple-backports/charon_alias.h): NSTextTab until iOS 7.0 and NSTextList until 9.0.
// The name links, +class is the release's class, what is made is the release's class, and
// the categories written on the name reach the release's class through the library's loader.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#import "check.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wnonnull"

static NSString *image_of(const void *address)
{
    Dl_info info;
    return address && dladdr(address, &info) ? @(info.dli_fname).lastPathComponent : @"?";
}

static NSString *image_of_method(Method method)
{
    return method ? image_of((const void *)method_getImplementation(method)) : @"none";
}

static BOOL own_class_method(Class cls, SEL selector)
{
    unsigned count = 0;
    Method *methods = cls ? class_copyMethodList(object_getClass(cls), &count) : NULL;
    BOOL found = NO;
    for (unsigned index = 0; index < count && !found; index++)
        found = method_getName(methods[index]) == selector;
    free(methods);
    return found;
}

static void check_text_tab(void)
{
    Class release = objc_getClass("NSTextTab");
    CHECK(release != Nil, "NSTextTab: the release carries the class");
    CHECK_EQUAL(image_of((__bridge const void *)release), @"UIFoundation", "NSTextTab: the class by name is UIFoundation's");
    CHECK([NSTextTab class] == release, "NSTextTab: the linked name answers the release's class");
    NSTextTab *tab = [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:40 options:nil];
    CHECK(object_getClass(tab) == release && [tab isKindOfClass:[NSTextTab class]], "NSTextTab: a tab made through the name is the release's");
    CHECK_EQUAL(image_of_method(class_getClassMethod(release, @selector(columnTerminatorsForLocale:))), @"libUIKitBackports.dylib",
                "NSTextTab: the category's class method is on the release's class");
    CHECK([[NSTextTab columnTerminatorsForLocale:nil] characterIsMember:'.'], "NSTextTab: the class method answers through the name");
    CHECK(!own_class_method(objc_getClass("CharonNSTextTab"), @selector(load)), "NSTextTab: the alias has no +load of its own");
}

static void check_text_list(void)
{
    Class release = objc_getClass("NSTextList");
    SEL three = @selector(initWithMarkerFormat:options:startingItemNumber:);
    CHECK(release != Nil, "NSTextList: the release carries the class");
    CHECK_EQUAL(image_of((__bridge const void *)release), @"UIFoundation", "NSTextList: the class by name is UIFoundation's");
    CHECK([NSTextList class] == release, "NSTextList: the linked name answers the release's class");
    CHECK_EQUAL(image_of_method(class_getInstanceMethod(release, @selector(initWithMarkerFormat:options:))), @"UIFoundation",
                "NSTextList: the two-argument initializer is the release's own");
    CHECK_EQUAL(image_of_method(class_getInstanceMethod(release, three)), @"libUIKitBackports.dylib",
                "NSTextList: the category's three-argument initializer is on the release's class");
    CHECK(objc_getClass("CharonTextListInit16") == Nil, "NSTextList: no class of the library adds the initializer by name");
    // The format as a string: iOS 6 exports none of the NSTextListMarker constants.
    NSTextList *list = [[NSTextList alloc] initWithMarkerFormat:@"{decimal}" options:0 startingItemNumber:5];
    CHECK(object_getClass(list) == release && [list isKindOfClass:[NSTextList class]], "NSTextList: a list made through the name is the release's");
    CHECK(list.startingItemNumber == 5 && [list.markerFormat isEqualToString:@"{decimal}"], "NSTextList: the list keeps its format and its starting number");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1)
            charon_log_to(@(argv[1]));
        check_text_tab();
        check_text_list();
        printf("%d checks, %d failed\n", charon_checks, charon_failures);
    }
    return charon_failures;
}
