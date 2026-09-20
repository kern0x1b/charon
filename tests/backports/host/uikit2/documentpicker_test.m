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

@interface CharonHostUIDocumentPickerViewController (Browser)
- (BOOL)charon_acceptsPath:(NSString *)path;
- (void)charon_pickPaths:(NSArray *)paths;
- (void)charon_chooseFolder:(NSString *)path;
- (NSArray *)charon_locations;
@end

@interface PickRecorder : NSObject
@property (nonatomic, copy) NSArray *urls;
@property (nonatomic) NSInteger cancels;
@end
@implementation PickRecorder
- (void)documentPicker:(id)picker didPickDocumentsAtURLs:(NSArray *)urls { self.urls = urls; }
- (void)documentPickerWasCancelled:(id)picker { self.cancels++; }
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

        NSFileManager *manager = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [manager createDirectoryAtPath:[root stringByAppendingPathComponent:@"dest"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"hello" writeToFile:[root stringByAppendingPathComponent:@"a.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"x" writeToFile:[root stringByAppendingPathComponent:@"b.png"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"y" writeToFile:[root stringByAppendingPathComponent:@"noext"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        CharonHostUIDocumentPickerViewController *text = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.text"] inMode:UIDocumentPickerModeOpen];
        CharonHostUIDocumentPickerViewController *image = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image"] inMode:UIDocumentPickerModeOpen];
        CharonHostUIDocumentPickerViewController *any = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeOpen];
        CharonHostUIDocumentPickerViewController *none = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[] inMode:UIDocumentPickerModeOpen];
        NSString *a = [root stringByAppendingPathComponent:@"a.txt"], *b = [root stringByAppendingPathComponent:@"b.png"], *n = [root stringByAppendingPathComponent:@"noext"];
        charon_check([text charon_acceptsPath:a] && ![text charon_acceptsPath:b], "public.text takes a text file and not a picture", @"filter");
        charon_check([image charon_acceptsPath:b] && ![image charon_acceptsPath:a], "public.image takes a picture and not a text file", @"filter");
        charon_check([any charon_acceptsPath:a] && [any charon_acceptsPath:n] && [none charon_acceptsPath:b], "public.item and no types take every file", @"filter");
        charon_check(![text charon_acceptsPath:n], "a file without an extension is not text", @"filter");
        charon_check([[ours charon_locations] count] >= 1 && [[[[ours charon_locations] firstObject] objectForKey:@"path"] isEqual:NSHomeDirectory()], "the first location is the application's home", @"locations");

        PickRecorder *recorder = [[PickRecorder alloc] init];
        CharonHostUIDocumentPickerViewController *open = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeOpen];
        open.delegate = recorder;
        [open charon_pickPaths:@[a]];
        charon_check(recorder.urls.count == 1 && [[recorder.urls[0] path] isEqualToString:a], "open answers the file itself", @"open");
        CharonHostUIDocumentPickerViewController *import = [[CharonHostUIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"] inMode:UIDocumentPickerModeImport];
        import.delegate = recorder;
        [import charon_pickPaths:@[a, b]];
        NSURL *copy = recorder.urls.firstObject;
        charon_check(recorder.urls.count == 2 && ![copy.path isEqualToString:a] && [copy.lastPathComponent isEqualToString:@"a.txt"] && [[NSString stringWithContentsOfURL:copy encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"hello"], "import answers copies with the same names, in the order chosen", @"import");

        NSString *dest = [root stringByAppendingPathComponent:@"dest"];
        CharonHostUIDocumentPickerViewController *export = [[CharonHostUIDocumentPickerViewController alloc] initWithURLs:@[[NSURL fileURLWithPath:a]] inMode:UIDocumentPickerModeExportToService];
        export.delegate = recorder;
        [export charon_chooseFolder:dest];
        [export charon_chooseFolder:dest];
        NSURL *second = recorder.urls.firstObject;
        charon_check([manager fileExistsAtPath:a] && [manager fileExistsAtPath:[dest stringByAppendingPathComponent:@"a.txt"]] && [second.lastPathComponent isEqualToString:@"a 2.txt"] && [manager fileExistsAtPath:second.path], "export copies into the folder and numbers a name already taken", @"export");
        CharonHostUIDocumentPickerViewController *move = [[CharonHostUIDocumentPickerViewController alloc] initWithURL:[NSURL fileURLWithPath:b] inMode:UIDocumentPickerModeMoveToService];
        move.delegate = recorder;
        [move charon_chooseFolder:dest];
        charon_check(![manager fileExistsAtPath:b] && [manager fileExistsAtPath:[dest stringByAppendingPathComponent:@"b.png"]] && [[recorder.urls[0] lastPathComponent] isEqualToString:@"b.png"], "move takes the file out of where it was", @"move");
        [manager removeItemAtPath:root error:NULL];
    }
    printf("checks=%d failures=%d\n", charon_checks, charon_failures);
    return charon_failures;
}
