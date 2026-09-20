#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

static const char charon_notify_entry_key;
static const char charon_notify_exit_key;

static BOOL charon_notify_flag(id region, const void *key)
{
    NSNumber *kept = objc_getAssociatedObject(region, key);
    return kept ? kept.boolValue : YES;
}

@implementation CLRegion (CharonNotify)

- (BOOL)notifyOnEntry
{
    return charon_notify_flag(self, &charon_notify_entry_key);
}

- (void)setNotifyOnEntry:(BOOL)notifyOnEntry
{
    objc_setAssociatedObject(self, &charon_notify_entry_key, @(notifyOnEntry), OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)notifyOnExit
{
    return charon_notify_flag(self, &charon_notify_exit_key);
}

- (void)setNotifyOnExit:(BOOL)notifyOnExit
{
    objc_setAssociatedObject(self, &charon_notify_exit_key, @(notifyOnExit), OBJC_ASSOCIATION_RETAIN);
}

@end
