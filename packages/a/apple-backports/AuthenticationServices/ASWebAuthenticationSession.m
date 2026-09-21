#import <AuthenticationServices/AuthenticationServices.h>
#import <SafariServices/SafariServices.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSErrorDomain const ASWebAuthenticationSessionErrorDomain = @"com.apple.AuthenticationServices.WebAuthenticationSession";

@implementation ASWebAuthenticationSession {
    SFAuthenticationSession *_session;
    __weak id<ASWebAuthenticationPresentationContextProviding> _presentationContextProvider;
    BOOL _spent;
}

@dynamic prefersEphemeralWebBrowserSession;

- (instancetype)initWithURL:(NSURL *)URL callbackURLScheme:(NSString *)callbackURLScheme completionHandler:(ASWebAuthenticationSessionCompletionHandler)completionHandler
{
    self = [super init];
    if (self) {
        ASWebAuthenticationSessionCompletionHandler handler = [completionHandler copy];
        _session = [[SFAuthenticationSession alloc] initWithURL:URL callbackURLScheme:callbackURLScheme completionHandler:^(NSURL *callbackURL, NSError *error) {
            if (!handler)
                return;
            NSError *mapped = error ? [NSError errorWithDomain:ASWebAuthenticationSessionErrorDomain code:ASWebAuthenticationSessionErrorCodeCanceledLogin userInfo:nil] : nil;
            handler(callbackURL, mapped);
        }];
    }
    return self;
}

- (id<ASWebAuthenticationPresentationContextProviding>)presentationContextProvider
{
    return _presentationContextProvider;
}

- (void)setPresentationContextProvider:(id<ASWebAuthenticationPresentationContextProviding>)presentationContextProvider
{
    _presentationContextProvider = presentationContextProvider;
}

- (BOOL)canStart
{
    return !_spent;
}

- (BOOL)start
{
    BOOL started = [_session start];
    _spent = _spent || started;
    return started;
}

- (void)cancel
{
    _spent = YES;
    [_session cancel];
}

@end
