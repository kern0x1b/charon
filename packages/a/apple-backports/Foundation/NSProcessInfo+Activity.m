#import <Foundation/Foundation.h>

@interface CharonProcessActivity : NSObject
- (instancetype)initWithOptions:(NSActivityOptions)options reason:(NSString *)reason;
- (void)end;
@end

@implementation CharonProcessActivity {
    NSActivityOptions _options;
    NSString *_reason;
    BOOL _ended;
}

- (instancetype)initWithOptions:(NSActivityOptions)options reason:(NSString *)reason
{
    if ((self = [super init])) {
        _options = options;
        _reason = [reason copy];
    }
    return self;
}

- (void)end
{
    @synchronized (self) {
        if (_ended) {
            NSLog(@"Warning: NSActivity %@ was ended multiple times", self);
            return;
        }
        _ended = YES;
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p> {options = 0x%llx, reason = %@}", [self class], self, (unsigned long long)_options, _reason];
}

@end

static void charon_note_sleep_options(NSActivityOptions options)
{
    if (!(options & (NSActivityIdleSystemSleepDisabled | NSActivityIdleDisplaySleepDisabled)))
        return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSLog(@"NSProcessInfo activities take no power assertion on iOS 6, so they do not keep the device or its display awake; the idle timer of UIApplication decides that");
    });
}

@implementation NSProcessInfo (CharonActivity)

- (id<NSObject>)beginActivityWithOptions:(NSActivityOptions)options reason:(NSString *)reason
{
    charon_note_sleep_options(options);
    return [[CharonProcessActivity alloc] initWithOptions:options reason:reason];
}

- (void)endActivity:(id<NSObject>)activity
{
    if ([activity isKindOfClass:[CharonProcessActivity class]])
        [(CharonProcessActivity *)activity end];
}

- (void)performActivityWithOptions:(NSActivityOptions)options reason:(NSString *)reason usingBlock:(void (^)(void))block
{
    if (!reason.length)
        [NSException raise:NSInvalidArgumentException format:@"Cannot begin activity without reason string or empty reason string"];
    charon_note_sleep_options(options);
    CharonProcessActivity *activity = [[CharonProcessActivity alloc] initWithOptions:options reason:reason];
    block();
    [activity end];
}

@end
