#import <UIKit/UIKit.h>

@implementation UIDocumentPickerViewController {
    UIDocumentPickerMode _documentPickerMode;
    __weak id<UIDocumentPickerDelegate> _delegate;
    BOOL _allowsMultipleSelection;
    BOOL _shouldShowFileExtensions;
    NSURL *_directoryURL;
    NSArray<NSString *> *_documentTypes;
    NSArray<NSURL *> *_URLs;
}

- (instancetype)initWithDocumentTypes:(NSArray<NSString *> *)allowedUTIs inMode:(UIDocumentPickerMode)mode
{
    if (mode != UIDocumentPickerModeImport && mode != UIDocumentPickerModeOpen)
        [NSException raise:NSInternalInconsistencyException format:@"-[UIDocumentPickerViewController initWithDocumentTypes:inMode:] can only be called with mode Import or Open"];
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _documentTypes = [allowedUTIs copy];
        _documentPickerMode = mode;
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url inMode:(UIDocumentPickerMode)mode
{
    if (mode != UIDocumentPickerModeExportToService && mode != UIDocumentPickerModeMoveToService)
        [NSException raise:NSInternalInconsistencyException format:@"-[UIDocumentPickerViewController initWithURL:inMode:] can only be called with mode Export or Move"];
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _URLs = url ? @[url] : @[];
        _documentPickerMode = mode;
    }
    return self;
}

- (instancetype)initWithURLs:(NSArray<NSURL *> *)urls inMode:(UIDocumentPickerMode)mode
{
    if (mode != UIDocumentPickerModeExportToService && mode != UIDocumentPickerModeMoveToService)
        [NSException raise:NSInternalInconsistencyException format:@"-[UIDocumentPickerViewController initWithURLs:inMode:] can only be called with mode Export or Move"];
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _URLs = [urls copy];
        _documentPickerMode = mode;
    }
    return self;
}

- (instancetype)init
{
    [NSException raise:NSInvalidArgumentException format:@"You cannot initialize a UIDocumentPickerViewController except by the initWithDocumentTypes:inMode: and initWithURL:inMode: initializers."];
    return nil;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    [NSException raise:NSInvalidArgumentException format:@"You cannot initialize a UIDocumentPickerViewController except by the initWithDocumentTypes:inMode: and initWithURL:inMode: initializers."];
    return nil;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (UIDocumentPickerMode)documentPickerMode
{
    return _documentPickerMode;
}

- (id<UIDocumentPickerDelegate>)delegate
{
    return _delegate;
}

- (void)setDelegate:(id<UIDocumentPickerDelegate>)delegate
{
    _delegate = delegate;
}

- (BOOL)allowsMultipleSelection
{
    return _allowsMultipleSelection;
}

- (void)setAllowsMultipleSelection:(BOOL)allows
{
    _allowsMultipleSelection = allows;
}

- (BOOL)shouldShowFileExtensions
{
    return _shouldShowFileExtensions;
}

- (void)setShouldShowFileExtensions:(BOOL)shows
{
    _shouldShowFileExtensions = shows;
}

- (NSURL *)directoryURL
{
    return _directoryURL;
}

- (void)setDirectoryURL:(NSURL *)URL
{
    _directoryURL = [URL copy];
}

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    UINavigationBar *bar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, view.bounds.size.width, 44)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UINavigationItem *item = [[UINavigationItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Locations", @"Localizable", [NSBundle bundleForClass:[UIView class]], nil)];
    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(charon_cancel)];
    bar.items = @[item];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(view.bounds, 24, 0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor grayColor];
    label.backgroundColor = [UIColor clearColor];
    label.text = @"No document locations are available on this device.";
    [view addSubview:label];
    [view addSubview:bar];
    self.view = view;
}

- (void)charon_cancel
{
    id<UIDocumentPickerDelegate> delegate = _delegate;
    void (^report)(void) = ^{
        if ([delegate respondsToSelector:@selector(documentPickerWasCancelled:)])
            [delegate documentPickerWasCancelled:self];
    };
    if (self.presentingViewController)
        [self.presentingViewController dismissViewControllerAnimated:YES completion:report];
    else
        report();
}

@end
