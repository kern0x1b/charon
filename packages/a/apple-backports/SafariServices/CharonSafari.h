#import <SafariServices/SafariServices.h>

@interface SFSafariViewController () {

    NSURL *_initialURL;
    SFSafariViewControllerConfiguration *_configuration;
    id _webView;
    UINavigationBar *_navigationBar;
    UINavigationItem *_barItem;
    UILabel *_addressLabel;
    UIProgressView *_progressView;
    UIToolbar *_toolbar;
    UIBarButtonItem *_backItem;
    UIBarButtonItem *_forwardItem;
    UIBarButtonItem *_actionItem;
    UIBarButtonItem *_reloadItem;
    UIBarButtonItem *_stopItem;
    UIPopoverController *_popover;
    NSURL *_currentURL;
    NSString *_pageTitle;
    BOOL _initialLoadPending;
    BOOL _showingError;
    BOOL _dismissing;
    NSTimer *_progressTimer;
}
@property (nonatomic, copy) BOOL (^charon_callbackMatcher)(NSURL *URL);
@property (nonatomic, copy) void (^charon_callback)(NSURL *URL);
- (void)charon_applyColors;
- (void)charon_applyDismissButton;
@end

@interface SFAuthenticationSession ()
@property (nonatomic, weak) UIWindow *charon_presentationWindow;
@end
