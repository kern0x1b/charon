#import "CharonSafari.h"

extern SFSafariViewControllerPrewarmingToken *charon_prewarmingToken(void);

static NSString *const CharonMisuse = @"Misuse of SFSafariViewController interface. Use -initWithURL: or -initWithURL:configuration: instead.";
static NSString *const CharonScheme = @"The specified URL has an unsupported scheme. Only HTTP and HTTPS URLs are supported.";

@implementation SFSafariViewController


+ (SFSafariViewControllerPrewarmingToken *)prewarmConnectionsToURLs:(NSArray<NSURL *> *)URLs
{
    return charon_prewarmingToken();
}

+ (void)charon_requireWebURL:(NSURL *)URL
{
    NSString *scheme = URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        [NSException raise:NSInvalidArgumentException format:@"%@", CharonScheme];
}

- (instancetype)init
{
    [NSException raise:NSGenericException format:@"%@", CharonMisuse];
    return nil;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    [NSException raise:NSGenericException format:@"%@", CharonMisuse];
    return nil;
}

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle
{
    [NSException raise:NSGenericException format:@"%@", CharonMisuse];
    return nil;
}

- (instancetype)initWithURL:(NSURL *)URL
{
    return [self initWithURL:URL configuration:[[SFSafariViewControllerConfiguration alloc] init]];
}

- (instancetype)initWithURL:(NSURL *)URL entersReaderIfAvailable:(BOOL)entersReaderIfAvailable
{
    SFSafariViewControllerConfiguration *configuration = [[SFSafariViewControllerConfiguration alloc] init];
    configuration.entersReaderIfAvailable = entersReaderIfAvailable;
    return [self initWithURL:URL configuration:configuration];
}

- (instancetype)initWithURL:(NSURL *)URL configuration:(SFSafariViewControllerConfiguration *)configuration
{
    [SFSafariViewController charon_requireWebURL:URL];
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _initialURL = [URL copy];
        _configuration = [configuration copy];
        _currentURL = _initialURL;
        _initialLoadPending = YES;
        self.modalPresentationStyle = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
    }
    return self;
}

- (NSURL *)initialURL
{
    return _initialURL;
}

- (SFSafariViewControllerConfiguration *)configuration
{
    return _configuration;
}

- (void)dealloc
{
    [_progressTimer invalidate];
    [_webView setDelegate:nil];
    [_webView stopLoading];
}

- (void)setPreferredBarTintColor:(UIColor *)color
{
    _preferredBarTintColor = color;
    if (self.isViewLoaded)
        [self charon_applyColors];
}

- (void)setPreferredControlTintColor:(UIColor *)color
{
    _preferredControlTintColor = color;
    if (self.isViewLoaded)
        [self charon_applyColors];
}

- (void)setDismissButtonStyle:(SFSafariViewControllerDismissButtonStyle)style
{
    _dismissButtonStyle = style;
    if (self.isViewLoaded)
        [self charon_applyDismissButton];
}

@end
