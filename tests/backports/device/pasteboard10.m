#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "check.h"
#import "pasteboard10-cases.h"
#import "pasteboard10-expectations.h"

static NSString *image_of_method(Class class, SEL selector)
{
    Method method = class_getInstanceMethod(class, selector);
    if (!method)
        return @"<missing>";
    Dl_info info;
    if (!dladdr((void *)method_getImplementation(method), &info) || !info.dli_fname)
        return @"?";
    return @(info.dli_fname).lastPathComponent;
}

static void check_sources(void)
{
    for (NSString *name in @[@"hasStrings", @"hasURLs", @"hasImages", @"hasColors"]) {
        NSString *image = image_of_method([UIPasteboard class], NSSelectorFromString(name));
        charon_check([image isEqualToString:@"libUIKitBackports.dylib"], [NSString stringWithFormat:@"-[UIPasteboard %@] comes from the backports", name].UTF8String, image);
    }
    for (NSString *name in @[@"UIPasteboardTypeListString", @"UIPasteboardTypeListURL", @"UIPasteboardTypeListImage", @"UIPasteboardTypeListColor"]) {
        void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
        Dl_info info;
        NSString *image = (symbol && dladdr(symbol, &info) && info.dli_fname) ? @(info.dli_fname).lastPathComponent : @"<missing>";
        charon_check([image isEqualToString:@"UIKit"], [NSString stringWithFormat:@"%@ is the release's own", name].UTF8String, image);
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        (void)argc;
        (void)argv;
        check_sources();
        NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:pasteboard10_expectations length:strlen(pasteboard10_expectations)] options:0 error:NULL];
        NSMutableDictionary *records = [NSMutableDictionary dictionary];
        pasteboard10_run(^(NSString *name, NSString *value) {
            records[name] = value;
        });
        for (NSString *name in [expected.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *want = expected[name];
            NSString *got = records[name];
            if ([want isEqualToString:got])
                charon_check(YES, name.UTF8String, nil);
            else
                charon_check(NO, name.UTF8String, [NSString stringWithFormat:@"device %@, host %@", got, want]);
        }
        printf("checks=%d failures=%d\n", charon_checks, charon_failures);
        return charon_failures;
    }
}
