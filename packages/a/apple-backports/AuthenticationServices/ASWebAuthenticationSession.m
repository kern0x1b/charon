#import <AuthenticationServices/AuthenticationServices.h>
#import <SafariServices/SafariServices.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSErrorDomain const ASWebAuthenticationSessionErrorDomain = @"com.apple.AuthenticationServices.WebAuthenticationSession";

@implementation ASWebAuthenticationSession {
    SFAuthenticationSession *_session;
}

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

- (BOOL)start
{
    return [_session start];
}

- (void)cancel
{
    [_session cancel];
}

@end
