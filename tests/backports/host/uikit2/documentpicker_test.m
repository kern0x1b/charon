#import <UIKit/UIKit.h>
#import "check.h"

@interface CharonHostUIDocumentPickerViewController : UIViewController
- (instancetype)initWithDocumentTypes:(NSArray<NSString *> *)types inMode:(UIDocumentPickerMode)mode;
- (instancetype)initWithURL:(NSURL *)url inMode:(UIDocumentPickerMode)mode;
- (instancetype)initWithURLs:(NSArray<NSURL *> *)urls inMode:(UIDocumentPickerMode)mode;
@property (nonatomic, readonly) UIDocumentPickerMode documentPickerMode;
@property (nonatomic, weak) id delegate;
@property (nonatomic) BOOL allowsMultipleSelection;
@property (nonatomic) BOOL shouldShowFileExtensions;
@property (nonatomic, copy) NSURL *directoryURL;
@end

static NSString *raised(id (^block)(void))
{
    @try {
        id result = block();
        return [NSString stringWithFormat:@"made %ld", (long)[[result valueForKey:@"documentPickerMode"] integerValue]];
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
    }
}

int main(void)
{
    @autoreleasepool {
        NSURL *file = [NSURL fileURLWithPath:@"/tmp/x.txt"];
        for (NSInteger mode = 0; mode < 4; mode++) {
            NSString *one = raised(^{ return [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.text"] inMode:(UIDocumentPickerMode)mode]; });
            NSString *two = raised(^{ return [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.text"] inMode:(UIDocumentPickerMode)mode]; });
            charon_check([one isEqualToString:two], [[NSString stringWithFormat:@"a picker for documents in mode %ld", (long)mode] UTF8String], ([NSString stringWithFormat:@"%@ != %@", one, two]));
            one = raised(^{ return [[CharonHostUIDocumentPickerViewController alloc] initWithURL:file inMode:(UIDocumentPickerMode)mode]; });
            two = raised(^{ return [[UIDocumentPickerViewController alloc] initWithURL:file inMode:(UIDocumentPickerMode)mode]; });
            charon_check([one isEqualToString:two], [[NSString stringWithFormat:@"a picker for a URL in mode %ld", (long)mode] UTF8String], ([NSString stringWithFormat:@"%@ != %@", one, two]));
            one = raised(^{ return [[CharonHostUIDocumentPickerViewController alloc] initWithURLs:@[file] inMode:(UIDocumentPickerMode)mode]; });
            two = raised(^{ return [[UIDocumentPickerViewController alloc] initWithURLs:@[file] inMode:(UIDocumentPickerMode)mode]; });
            charon_check([one isEqualToString:two], [[NSString stringWithFormat:@"a picker for URLs in mode %ld", (long)mode] UTF8String], ([NSString stringWithFormat:@"%@ != %@", one, two]));
        }
        NSString *one = raised(^{ return [[CharonHostUIDocumentPickerViewController alloc] init]; });
        NSString *two = raised(^{ return [[UIDocumentPickerViewController alloc] init]; });
        charon_check([one isEqualToString:two], "a picker made with init is refused with the system's reason", ([NSString stringWithFormat:@"%@ != %@", one, two]));
        one = raised(^{ return [[CharonHostUIDocumentPickerViewController alloc] initWithNibName:nil bundle:nil]; });
        two = raised(^{ return [[UIDocumentPickerViewController alloc] initWithNibName:nil bundle:nil]; });
        charon_check([one isEqualToString:two], "and one made with a nib", ([NSString stringWithFormat:@"%@ != %@", one, two]));

        CharonHostUIDocumentPickerViewController *ours = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image"] inMode:UIDocumentPickerModeOpen];
        UIDocumentPickerViewController *system = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image"] inMode:UIDocumentPickerModeOpen];
        charon_check(ours.delegate == nil && system.delegate == nil && ours.allowsMultipleSelection == system.allowsMultipleSelection && ours.shouldShowFileExtensions == system.shouldShowFileExtensions && ours.directoryURL == system.directoryURL, "a new picker has no delegate, no multiple selection, no file extensions and no directory", @"a field differs");
        ours.allowsMultipleSelection = YES;
        system.allowsMultipleSelection = YES;
        ours.directoryURL = file;
        system.directoryURL = file;
        charon_check(ours.allowsMultipleSelection == system.allowsMultipleSelection && [ours.directoryURL isEqual:system.directoryURL], "the multiple selection and the directory are kept", @"a field differs");
        NSObject *object = [[NSObject alloc] init];
        ours.delegate = object;
        system.delegate = (id)object;
        object = nil;
        charon_check(ours.delegate == nil && system.delegate == nil, "the delegate is held weakly", @"it is held");
    }
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures;
}
