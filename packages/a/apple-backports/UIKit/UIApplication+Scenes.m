#import "CharonScenes.h"

static void charon_say_once(NSString *key, NSString *text)
{
    static NSMutableSet *said;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        said = [[NSMutableSet alloc] init];
    });
    @synchronized (said) {
        if ([said containsObject:key])
            return;
        [said addObject:key];
    }
    NSLog(@"%@", text);
}

static void charon_scene_error(void (^handler)(NSError *), NSInteger code)
{
    if (!handler)
        return;
    NSError *error = [NSError errorWithDomain:UISceneErrorDomain code:code userInfo:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(error);
    });
}

@implementation UIApplication (CharonScenes)

- (UIWindowScene *)charon_scene
{
    return charon_scene();
}

- (NSSet<UIScene *> *)connectedScenes
{
    UIWindowScene *scene = charon_scene();
    return scene ? [NSSet setWithObject:scene] : [NSSet set];
}

- (NSSet<UISceneSession *> *)openSessions
{
    UIWindowScene *scene = charon_scene();
    return scene ? [NSSet setWithObject:scene.session] : [NSSet set];
}

- (BOOL)supportsMultipleScenes
{
    return NO;
}

- (void)requestSceneSessionActivation:(UISceneSession *)sceneSession userActivity:(NSUserActivity *)userActivity options:(UISceneActivationRequestOptions *)options errorHandler:(void (^)(NSError *))errorHandler
{
    if (sceneSession && sceneSession == charon_scene().session)
        return;
    charon_scene_error(errorHandler, 0);
}

- (void)requestSceneSessionDestruction:(UISceneSession *)sceneSession options:(UISceneDestructionRequestOptions *)options errorHandler:(void (^)(NSError *))errorHandler
{
    charon_scene_error(errorHandler, 1);
}

- (void)requestSceneSessionRefresh:(UISceneSession *)sceneSession
{
    charon_say_once(@"scene-refresh", @"UIApplication requestSceneSessionRefresh: has no scene snapshot to refresh on this release and does nothing");
}

@end
