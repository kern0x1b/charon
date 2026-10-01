#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>

@protocol LElement <NSObject>
@property (readonly) id collection;
@property (readonly) NSSet *aliases;
@property (readonly, getter=isAnalog) BOOL analog;
@property (readonly, getter=isBoundToSystemGesture) BOOL boundToSystemGesture;
@property (readonly) NSInteger preferredSystemGestureState;
@property (readonly) NSString *sfSymbolsName;
@property (readonly) NSString *localizedName;
@property (readonly) NSString *unmappedSfSymbolsName;
@property (readonly) NSString *unmappedLocalizedName;
@end

@protocol LButton <LElement>
@property (readonly) float value;
@property (readonly, getter=isPressed) BOOL pressed;
@property (readonly, getter=isTouched) BOOL touched;
@property (copy) void (^valueChangedHandler)(id, float, BOOL);
@property (copy) void (^pressedChangedHandler)(id, float, BOOL);
@property (copy) void (^touchedChangedHandler)(id, float, BOOL, BOOL);
- (void)setValue:(float)value;
@end

@protocol LAxis <LElement>
@property (readonly) float value;
@property (copy) void (^valueChangedHandler)(id, float);
- (void)setValue:(float)value;
@end

@protocol LDpad <LElement>
@property (readonly) id<LAxis> xAxis;
@property (readonly) id<LAxis> yAxis;
@property (readonly) id<LButton> up;
@property (readonly) id<LButton> down;
@property (readonly) id<LButton> left;
@property (readonly) id<LButton> right;
@property (copy) void (^valueChangedHandler)(id, float, float);
- (void)setValueForXAxis:(float)x yAxis:(float)y;
@end

// The touchpad, mirrored the way every other protocol here is: the host's own class
// behind a protocol spelled out of its declared members, so the same code drives the
// host's touchpad and the port's renamed copy without naming either.
@protocol LTouchpad <NSObject>
@property (readonly) id button;
@property (readonly) id touchSurface;
@property (readonly) NSInteger touchState;
@property (nonatomic) BOOL reportsAbsoluteTouchSurfaceValues;
@property (nonatomic, copy, nullable) void (^touchDown)(id, float, float, float, BOOL);
@property (nonatomic, copy, nullable) void (^touchMoved)(id, float, float, float, BOOL);
@property (nonatomic, copy, nullable) void (^touchUp)(id, float, float, float, BOOL);
- (void)setValueForXAxis:(float)xAxis yAxis:(float)yAxis touchDown:(BOOL)touchDown buttonValue:(float)buttonValue;
@end

@protocol LProfile <NSObject>
@property (readonly) id controller;
@property (readonly) id device;
@property (readonly) NSTimeInterval lastEventTimestamp;
@property (readonly) BOOL hasRemappedElements;
@property (readonly) NSDictionary *elements;
@property (readonly) NSDictionary *buttons;
@property (readonly) NSDictionary *axes;
@property (readonly) NSDictionary *dpads;
@property (readonly) NSDictionary *touchpads;
@property (readonly) NSSet *allElements;
@property (readonly) NSSet *allButtons;
@property (readonly) NSSet *allAxes;
@property (readonly) NSSet *allDpads;
@property (readonly) NSSet *allTouchpads;
- (id)objectForKeyedSubscript:(NSString *)key;
- (id)capture;
- (void)setStateFromExtendedGamepad:(id)other;
- (void)setStateFromMicroGamepad:(id)other;
@end

@protocol LController <NSObject>
@property (readonly) id motion;
@property (readonly) NSString *vendorName;
@property (readonly) NSString *productCategory;
@property NSInteger playerIndex;
@property (readonly, getter=isAttachedToDevice) BOOL attachedToDevice;
@property (readonly, getter=isSnapshot) BOOL snapshot;
@property (strong) dispatch_queue_t handlerQueue;
@property (readonly) id<LProfile> extendedGamepad;
@property (readonly) id<LProfile> gamepad;
@property (readonly) id<LProfile> microGamepad;
@property (readonly) id<LProfile> physicalInputProfile;
@property (readonly) id battery;
@property (readonly) id light;
@property (readonly) id haptics;
- (id<LController>)capture;
@end

@interface NSObject (LFactory)
+ (id<LController>)controllerWithExtendedGamepad;
+ (id<LController>)controllerWithMicroGamepad;
@end

static NSString *sorted(NSSet *set)
{
    return [[[set allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
}

static NSString *kind(id element)
{
    if ([element respondsToSelector:@selector(xAxis)])
        return @"dpad";
    if ([element respondsToSelector:@selector(isPressed)])
        return @"button";
    return @"axis";
}

// The host raises on some of these calls - measured, -[GCGamepadSnapshot setSnapshotData:] drives
// an axis input that has no profile behind it and raises - so a call that may raise is recorded as
// what it did rather than taking the process down and losing every line after it.
static id attemptOut(id (^block)(void), NSString **what)
{
    @try {
        id value = block();
        *what = value ? @"non-nil" : @"(nil)";
        return value;
    } @catch (NSException *raised) {
        *what = [NSString stringWithFormat:@"raised %@: %@", raised.name, raised.reason];
        return nil;
    }
}

static NSString *attempt(id (^block)(void))
{
    @try {
        id value = block();
        return value ? [NSString stringWithFormat:@"%@", value] : @"(nil)";
    } @catch (NSException *raised) {
        return [NSString stringWithFormat:@"raised %@: %@", raised.name, raised.reason];
    }
}

static id send0(id o, SEL s)
{
    return o ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}

static NSString *f(float value)
{
    if (value == 0)
        return @"0";
    return [NSString stringWithFormat:@"%.9g", value];
}

static NSString *describeElement(id<LElement> e)
{
    NSString *collection = e.collection ? sorted([e.collection aliases]) : @"-";
    return [NSString stringWithFormat:@"%@ aliases=%@ local=%@ unmappedLocal=%@ sf=%@ unmappedSf=%@ analog=%d system=%d preferred=%ld collection=%@", kind(e), sorted(e.aliases),
            e.localizedName, e.unmappedLocalizedName, e.sfSymbolsName, e.unmappedSfSymbolsName, e.analog, e.boundToSystemGesture, (long)e.preferredSystemGestureState, collection];
}

static NSString *stateOf(id<LProfile> profile)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [[profile.elements allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        id e = profile.elements[key];
        NSString *k = kind(e);
        if ([k isEqual:@"button"])
            [parts addObject:[NSString stringWithFormat:@"%@=%@/%d/%d", key, f([(id<LButton>)e value]), [(id<LButton>)e isPressed], [(id<LButton>)e isTouched]]];
        else if ([k isEqual:@"axis"])
            [parts addObject:[NSString stringWithFormat:@"%@=%@", key, f([(id<LAxis>)e value])]];
    }
    return [parts componentsJoinedByString:@" "];
}

static void spin(void)
{
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.004, false);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.001, false);
}

static void hook(id<LProfile> profile, NSMutableArray *log)
{
    for (NSString *key in [[profile.elements allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        id e = profile.elements[key];
        NSString *k = kind(e);
        NSString *first = [[[[(id<LElement>)e aliases] allObjects] sortedArrayUsingSelector:@selector(compare:)] firstObject];
        if (![key isEqual:first])
            continue;
        if ([k isEqual:@"button"]) {
            id<LButton> b = e;
            b.valueChangedHandler = ^(id x, float v, BOOL p) { [log addObject:[NSString stringWithFormat:@"%@ vch %@ %d", key, f(v), p]]; };
            b.pressedChangedHandler = ^(id x, float v, BOOL p) { [log addObject:[NSString stringWithFormat:@"%@ pch %@ %d", key, f(v), p]]; };
            b.touchedChangedHandler = ^(id x, float v, BOOL p, BOOL t) { [log addObject:[NSString stringWithFormat:@"%@ tch %@ %d %d", key, f(v), p, t]]; };
        } else if ([k isEqual:@"axis"]) {
            id<LAxis> a = e;
            a.valueChangedHandler = ^(id x, float v) { [log addObject:[NSString stringWithFormat:@"%@ vch %@", key, f(v)]]; };
        } else {
            id<LDpad> d = e;
            d.valueChangedHandler = ^(id x, float xv, float yv) { [log addObject:[NSString stringWithFormat:@"%@ vch %@ %@", key, f(xv), f(yv)]]; };
        }
    }
}

@protocol LMotion <NSObject>
@property (readonly) id controller;
@property (copy) void (^valueChangedHandler)(id);
@property (readonly) BOOL sensorsRequireManualActivation;
@property BOOL sensorsActive;
@property (readonly) BOOL hasGravityAndUserAcceleration;
@property (readonly) BOOL hasAttitude;
@property (readonly) BOOL hasRotationRate;
@property (readonly) BOOL hasAttitudeAndRotationRate;
- (void)setStateFromMotion:(id)motion;
@end

static NSArray *drive(Class controllerClass, BOOL micro)
{
    NSMutableArray *log = [NSMutableArray array];
    id<LController> controller = micro ? [controllerClass controllerWithMicroGamepad] : [controllerClass controllerWithExtendedGamepad];
    id<LProfile> profile = micro ? controller.microGamepad : controller.extendedGamepad;
    [log addObject:[NSString stringWithFormat:@"controller vendor=%@ product=%@ player=%ld attached=%d snapshot=%d queueMain=%d", controller.vendorName, controller.productCategory,
                    (long)controller.playerIndex, controller.attachedToDevice, controller.snapshot, controller.handlerQueue == dispatch_get_main_queue()]];
    [log addObject:[NSString stringWithFormat:@"identity ext=%d gamepad=%d micro=%d physical=%d battery=%d light=%d haptics=%d", controller.extendedGamepad != nil,
                    controller.gamepad == controller.extendedGamepad && controller.gamepad != nil, controller.microGamepad == profile, controller.physicalInputProfile == profile,
                    controller.battery != nil, controller.light != nil, controller.haptics != nil]];
    [log addObject:[NSString stringWithFormat:@"profile controller=%d device=%d timestamp=%g remapped=%d", profile.controller == controller, profile.device == controller,
                    profile.lastEventTimestamp, profile.hasRemappedElements]];
    NSArray *keys = [[profile.elements allKeys] sortedArrayUsingSelector:@selector(compare:)];
    [log addObject:[NSString stringWithFormat:@"counts elements=%lu buttons=%lu axes=%lu dpads=%lu touchpads=%lu all=%lu allButtons=%lu allAxes=%lu allDpads=%lu allTouchpads=%lu",
                    (unsigned long)profile.elements.count, (unsigned long)profile.buttons.count, (unsigned long)profile.axes.count, (unsigned long)profile.dpads.count,
                    (unsigned long)profile.touchpads.count, (unsigned long)profile.allElements.count, (unsigned long)profile.allButtons.count, (unsigned long)profile.allAxes.count,
                    (unsigned long)profile.allDpads.count, (unsigned long)profile.allTouchpads.count]];
    for (NSString *key in keys)
        [log addObject:[NSString stringWithFormat:@"element %@: %@", key, describeElement(profile.elements[key])]];
    for (NSString *key in keys)
        [log addObject:[NSString stringWithFormat:@"subscript %@ same=%d", key, profile[key] == profile.elements[key]]];
    NSArray *names = micro ? @[@"dpad", @"buttonA", @"buttonX", @"buttonMenu"]
                           : @[@"dpad", @"buttonA", @"buttonB", @"buttonX", @"buttonY", @"buttonMenu", @"buttonOptions", @"buttonHome", @"leftThumbstick", @"rightThumbstick", @"leftShoulder",
                               @"rightShoulder", @"leftTrigger", @"rightTrigger", @"leftThumbstickButton", @"rightThumbstickButton"];
    for (NSString *name in names)
        [log addObject:[NSString stringWithFormat:@"property %@ -> %@", name, sorted([(id<LElement>)[(NSObject *)profile valueForKey:name] aliases])]];
    id<LDpad> dpad = [(NSObject *)profile valueForKey:@"dpad"];
    [log addObject:[NSString stringWithFormat:@"dpad parts x=%@ y=%@ up=%@ down=%@ left=%@ right=%@", sorted(dpad.xAxis.aliases), sorted(dpad.yAxis.aliases), sorted(dpad.up.aliases),
                    sorted(dpad.down.aliases), sorted(dpad.left.aliases), sorted(dpad.right.aliases)]];
    hook(profile, log);

    NSMutableArray *buttons = [NSMutableArray array], *axes = [NSMutableArray array], *dpads = [NSMutableArray array];
    for (NSString *key in keys) {
        id e = profile.elements[key];
        NSString *first = [[[[(id<LElement>)e aliases] allObjects] sortedArrayUsingSelector:@selector(compare:)] firstObject];
        if (![key isEqual:first])
            continue;
        NSString *k = kind(e);
        [([k isEqual:@"button"] ? buttons : [k isEqual:@"axis"] ? axes : dpads) addObject:key];
    }
    static const float values[] = {0, 1, 0.5, 0.2, 0.01, 1e-6, -0.5, -1, 1.5, -1.5, 0.7, 0.3, 0.49, 0.51, 2, -0.2, 1e-9, 3e-8, 2.9e-8, 0.001953125f, 0.002f, 0.0019531251f, -0.0f, 1.0000001f};
    srandom(20260921);
    for (int step = 0; step < 4000; step++) {
        int which = random() % 3;
        float a = values[random() % 24], b = values[random() % 24];
        NSString *op;
        if (which == 0) {
            NSString *key = buttons[random() % buttons.count];
            [(id<LButton>)profile.elements[key] setValue:a];
            op = [NSString stringWithFormat:@"button %@ setValue %@", key, f(a)];
        } else if (which == 1) {
            NSString *key = axes[random() % axes.count];
            [(id<LAxis>)profile.elements[key] setValue:a];
            op = [NSString stringWithFormat:@"axis %@ setValue %@", key, f(a)];
        } else {
            NSString *key = dpads[random() % dpads.count];
            [(id<LDpad>)profile.elements[key] setValueForXAxis:a yAxis:b];
            op = [NSString stringWithFormat:@"dpad %@ set %@ %@", key, f(a), f(b)];
        }
        NSUInteger before = log.count;
        spin();
        NSMutableArray *events = [NSMutableArray array];
        for (NSUInteger i = before; i < log.count; i++)
            [events addObject:log[i]];
        [log removeObjectsInRange:NSMakeRange(before, log.count - before)];
        [log addObject:[NSString stringWithFormat:@"%@ => %@", op, [events componentsJoinedByString:@"; "]]];
        if (step % 25 == 0)
            [log addObject:[NSString stringWithFormat:@"state %@", stateOf(profile)]];
    }
    id<LProfile> captured = [profile capture];
    [log addObject:[NSString stringWithFormat:@"capture same-class=%d controller=%d state-equal=%d", [captured isMemberOfClass:[(NSObject *)profile class]], captured.controller == nil,
                    [stateOf(captured) isEqual:stateOf(profile)]]];
    id<LController> other = micro ? [controllerClass controllerWithMicroGamepad] : [controllerClass controllerWithExtendedGamepad];
    NSMutableArray *copyLog = [NSMutableArray array];
    id<LProfile> target = micro ? other.microGamepad : other.extendedGamepad;
    hook(target, copyLog);
    if (micro)
        [target setStateFromMicroGamepad:profile];
    else
        [target setStateFromExtendedGamepad:profile];
    spin();
    [log addObject:[NSString stringWithFormat:@"setState events: %@", [copyLog componentsJoinedByString:@"; "]]];
    [log addObject:[NSString stringWithFormat:@"setState state-equal=%d", [stateOf(target) isEqual:stateOf(profile)]]];
    id<LController> capturedController = [controller capture];
    [log addObject:[NSString stringWithFormat:@"controller capture vendor=%@ product=%@ snapshot=%d ext=%d", capturedController.vendorName, capturedController.productCategory,
                    capturedController.snapshot, capturedController.extendedGamepad != nil]];
    controller.playerIndex = 2;

    {
        id<LController> mc = micro ? [controllerClass controllerWithMicroGamepad] : [controllerClass controllerWithExtendedGamepad];
        id m = mc.motion;
        NSMutableArray *fired = [NSMutableArray array];
        [(id<LMotion>)m setValueChangedHandler:^(id x) { [fired addObject:@"changed"]; }];
        typedef struct { double x, y, z; } V3;
        typedef struct { double x, y, z, w; } V4;
        NSString *(^dump)(id) = ^NSString *(id object) {
            V3 (*vec)(id, SEL) = (V3 (*)(id, SEL))objc_msgSend;
            V4 (*quat)(id, SEL) = (V4 (*)(id, SEL))objc_msgSend;
            V3 g = vec(object, @selector(gravity)), u = vec(object, @selector(userAcceleration)), a = vec(object, @selector(acceleration)), r = vec(object, @selector(rotationRate));
            V4 q = quat(object, @selector(attitude));
            id<LMotion> lm = object;
            return [NSString stringWithFormat:@"req=%d active=%d hasGU=%d hasAtt=%d hasRot=%d hasAR=%d g=(%g %g %g) u=(%g %g %g) a=(%g %g %g) att=(%g %g %g %g) rot=(%g %g %g) controller=%d", lm.sensorsRequireManualActivation,
                    lm.sensorsActive, lm.hasGravityAndUserAcceleration, lm.hasAttitude, lm.hasRotationRate, lm.hasAttitudeAndRotationRate, g.x, g.y, g.z, u.x, u.y, u.z, a.x, a.y, a.z, q.x, q.y, q.z, q.w, r.x, r.y, r.z, lm.controller == mc];
        };
        [log addObject:[NSString stringWithFormat:@"motion initial %@", dump(m)]];
        void (^setVec)(SEL, V3) = ^(SEL selector, V3 v) { ((void (*)(id, SEL, V3))objc_msgSend)(m, selector, v); };
        setVec(@selector(setGravity:), (V3){0, -1, 0});
        setVec(@selector(setUserAcceleration:), (V3){0.1, 0.2, 0.3});
        setVec(@selector(setAcceleration:), (V3){1, 2, 3});
        setVec(@selector(setRotationRate:), (V3){4, 5, 6});
        ((void (*)(id, SEL, V4))objc_msgSend)(m, @selector(setAttitude:), (V4){0.1, 0.2, 0.3, 0.9});
        [(id<LMotion>)m setSensorsActive:NO];
        spin();
        [log addObject:[NSString stringWithFormat:@"motion after setters %@ fired=%lu", dump(m), (unsigned long)fired.count]];
        id<LController> other = micro ? [controllerClass controllerWithMicroGamepad] : [controllerClass controllerWithExtendedGamepad];
        NSMutableArray *copyFired = [NSMutableArray array];
        [(id<LMotion>)other.motion setValueChangedHandler:^(id x) { [copyFired addObject:@"changed"]; }];
        [(id<LMotion>)other.motion setStateFromMotion:m];
        [(id<LMotion>)other.motion setStateFromMotion:m];
        spin();
        [log addObject:[NSString stringWithFormat:@"motion copied %@ fired=%lu", dump(other.motion), (unsigned long)copyFired.count]];
        id<LController> cap = [mc capture];
        [log addObject:[NSString stringWithFormat:@"motion captured %@", dump(cap.motion)]];
    }

    [log addObject:[NSString stringWithFormat:@"player after set %ld", (long)controller.playerIndex]];

    {
        id<LController> extra = micro ? [controllerClass controllerWithMicroGamepad] : [controllerClass controllerWithExtendedGamepad];
        id<LProfile> p = micro ? extra.microGamepad : extra.extendedGamepad;
        id<LButton> a = [(NSObject *)p valueForKey:@"buttonA"];
        NSMutableArray *events = [NSMutableArray array];
        a.valueChangedHandler = ^(id x, float v, BOOL pr) { [events addObject:[NSString stringWithFormat:@"first %g", v]]; };
        [a setValue:0.5];
        a.valueChangedHandler = ^(id x, float v, BOOL pr) { [events addObject:[NSString stringWithFormat:@"second %g", v]]; };
        spin();
        [log addObject:[NSString stringWithFormat:@"handler replaced before delivery: %@", [events componentsJoinedByString:@","]]];
        [events removeAllObjects];
        [a setValue:0.7];
        a.valueChangedHandler = nil;
        spin();
        [log addObject:[NSString stringWithFormat:@"handler removed before delivery: %@", [events componentsJoinedByString:@","]]];
        dispatch_queue_t queue = dispatch_queue_create("custom-label", DISPATCH_QUEUE_SERIAL);
        extra.handlerQueue = queue;
        [events removeAllObjects];
        a.valueChangedHandler = ^(id x, float v, BOOL pr) { [events addObject:[NSString stringWithFormat:@"%g on %s main=%d", v, dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), [NSThread isMainThread]]]; };
        [a setValue:0.1];
        [a setValue:0.2];
        [a setValue:0.3];
        dispatch_sync(queue, ^{});
        [log addObject:[NSString stringWithFormat:@"custom queue: %@ queueKept=%d", [events componentsJoinedByString:@","], extra.handlerQueue == queue]];
        id<LElement> element = [(NSObject *)p valueForKey:@"buttonA"];
        [(NSObject *)element setValue:@"Custom" forKey:@"localizedName"];
        [(NSObject *)element setValue:@"custom.symbol" forKey:@"sfSymbolsName"];
        [(NSObject *)element setValue:@"Unmapped" forKey:@"unmappedLocalizedName"];
        [(NSObject *)element setValue:@"unmapped.symbol" forKey:@"unmappedSfSymbolsName"];
        [(NSObject *)element setValue:@2 forKey:@"preferredSystemGestureState"];
        [log addObject:[NSString stringWithFormat:@"element setters: %@ %@ %@ %@ %ld", element.localizedName, element.sfSymbolsName, element.unmappedLocalizedName, element.unmappedSfSymbolsName, (long)element.preferredSystemGestureState]];
        __weak id weakProfile;
        @autoreleasepool {
            id<LController> temp = micro ? [controllerClass controllerWithMicroGamepad] : [controllerClass controllerWithExtendedGamepad];
            id<LProfile> tp = micro ? temp.microGamepad : temp.extendedGamepad;
            weakProfile = tp;
            [log addObject:[NSString stringWithFormat:@"temp controller kept profile=%d", [tp controller] != nil]];
        }
                id direct = [[NSClassFromString(micro ? (controllerClass == NSClassFromString(@"GCController") ? @"GCMicroGamepad" : @"CharonHostGCMicroGamepad") : (controllerClass == NSClassFromString(@"GCController") ? @"GCExtendedGamepad" : @"CharonHostGCExtendedGamepad")) alloc] init];
        id<LProfile> dp = direct;
        [log addObject:[NSString stringWithFormat:@"direct init: profile=%d elements=%lu controller=%d device=%d", dp != nil, (unsigned long)dp.elements.count, dp.controller != nil, dp.device != nil]];
    }
    return log;
}



// ---- the snapshot structures (iOS 7.0 and 9.0) --------------------------------------------
// The structures and the host's own functions come from the framework's header; the rest of this
// file talks to both sides through its own protocols, so it depends on neither copy's class names.
// The port's copy of each function carries its own name (run.sh renames it), and both copies fill
// the same public header structure, so one variable stands for both sides.

#import <GameController/GameController.h>

extern BOOL charonHost_GCGamepadSnapShotDataV100FromNSData(GCGamepadSnapShotDataV100 *, NSData *);
extern NSData *charonHost_NSDataFromGCGamepadSnapShotDataV100(GCGamepadSnapShotDataV100 *);
extern BOOL charonHost_GCExtendedGamepadSnapShotDataV100FromNSData(GCExtendedGamepadSnapShotDataV100 *, NSData *);
extern NSData *charonHost_NSDataFromGCExtendedGamepadSnapShotDataV100(GCExtendedGamepadSnapShotDataV100 *);
extern BOOL charonHost_GCExtendedGamepadSnapshotDataFromNSData(GCExtendedGamepadSnapshotData *, NSData *);
extern NSData *charonHost_NSDataFromGCExtendedGamepadSnapshotData(GCExtendedGamepadSnapshotData *);
extern BOOL charonHost_GCMicroGamepadSnapShotDataV100FromNSData(GCMicroGamepadSnapShotDataV100 *, NSData *);
extern NSData *charonHost_NSDataFromGCMicroGamepadSnapShotDataV100(GCMicroGamepadSnapShotDataV100 *);
extern BOOL charonHost_GCMicroGamepadSnapshotDataFromNSData(GCMicroGamepadSnapshotData *, NSData *);
extern NSData *charonHost_NSDataFromGCMicroGamepadSnapshotData(GCMicroGamepadSnapshotData *);
extern const long charonHost_GCCurrentExtendedGamepadSnapshotDataVersion;
extern const long charonHost_GCCurrentMicroGamepadSnapshotDataVersion;

// A blob a caller may hand a reader: a pattern of printable bytes, so a reader that copies it
// verbatim and one that checks it cannot both be right by accident.
static NSData *pattern(unsigned length)
{
    NSMutableData *d = [NSMutableData dataWithLength:length];
    unsigned char *b = d.mutableBytes;
    for (unsigned i = 0; i < length; i++)
        b[i] = (unsigned char)(0x40 + (i % 26));
    return d;
}

// A whole data as text, so two encodings are compared byte for byte and not by their length alone.
static NSString *whole(NSData *d)
{
    if (!d)
        return @"(nil)";
    const unsigned char *b = d.bytes;
    NSMutableString *s = [NSMutableString stringWithFormat:@"%lu:", (unsigned long)d.length];
    for (NSUInteger i = 0; i < d.length; i++)
        [s appendFormat:@"%02x", b[i]];
    return s;
}

static NSArray *snapshotFunctionGroup(BOOL port)
{
    NSMutableArray *log = [NSMutableArray array];
    // the encoders: a zeroed structure, one with values, one whose version and size are already set
    GCGamepadSnapShotDataV100 g1;
    memset(&g1, 0, sizeof(g1));
    g1.dpadX = 0.25f;
    g1.buttonA = 1.0f;
    g1.buttonY = 0.125f;
    GCGamepadSnapShotDataV100 g2 = g1;
    g2.version = 0x0200;
    g2.size = 999;
    for (int which = 0; which < 2; which++) {
        GCGamepadSnapShotDataV100 *in = which ? &g2 : &g1;
        [log addObject:[NSString stringWithFormat:@"gamepad NSDataFrom(%d) = %@", which,
                                                  whole(port ? charonHost_NSDataFromGCGamepadSnapShotDataV100(in)
                                                             : NSDataFromGCGamepadSnapShotDataV100(in))]];
        [log addObject:[NSString stringWithFormat:@"gamepad NSDataFrom(NULL) = %@",
                                                  port ? charonHost_NSDataFromGCGamepadSnapShotDataV100(NULL) : NSDataFromGCGamepadSnapShotDataV100(NULL)]];
    }
    GCExtendedGamepadSnapShotDataV100 e1;
    memset(&e1, 0, sizeof(e1));
    e1.buttonB = 0.5f;
    e1.leftTrigger = 0.75f;
    [log addObject:[NSString stringWithFormat:@"extended NSDataFromV100 = %@",
                                              whole(port ? charonHost_NSDataFromGCExtendedGamepadSnapShotDataV100(&e1)
                                                         : NSDataFromGCExtendedGamepadSnapShotDataV100(&e1))]];
    GCExtendedGamepadSnapshotData e2;
    memset(&e2, 0, sizeof(e2));
    e2.buttonA = 1.0f;
    e2.leftThumbstickX = 0.5f;
    e2.supportsClickableThumbsticks = 1;
    e2.leftThumbstickButton = 1;
    [log addObject:[NSString stringWithFormat:@"extended NSDataFrom = %@",
                                              whole(port ? charonHost_NSDataFromGCExtendedGamepadSnapshotData(&e2)
                                                         : NSDataFromGCExtendedGamepadSnapshotData(&e2))]];
    GCExtendedGamepadSnapshotData e3 = e2;
    e3.version = GCExtendedGamepadSnapshotDataVersion1;
    e3.size = sizeof(GCExtendedGamepadSnapShotDataV100);
    [log addObject:[NSString stringWithFormat:@"extended NSDataFrom with the V100 header = %@",
                                              whole(port ? charonHost_NSDataFromGCExtendedGamepadSnapshotData(&e3)
                                                         : NSDataFromGCExtendedGamepadSnapshotData(&e3))]];
    GCMicroGamepadSnapshotData m1;
    memset(&m1, 0, sizeof(m1));
    m1.dpadX = -1.0f;
    m1.buttonA = 0.5f;
    [log addObject:[NSString stringWithFormat:@"micro NSDataFrom = %@",
                                              whole(port ? charonHost_NSDataFromGCMicroGamepadSnapshotData(&m1)
                                                         : NSDataFromGCMicroGamepadSnapshotData(&m1))]];
    GCMicroGamepadSnapShotDataV100 m2;
    memset(&m2, 0, sizeof(m2));
    m2.buttonX = 1.0f;
    [log addObject:[NSString stringWithFormat:@"micro NSDataFromV100 = %@",
                                              whole(port ? charonHost_NSDataFromGCMicroGamepadSnapShotDataV100(&m2)
                                                         : NSDataFromGCMicroGamepadSnapShotDataV100(&m2))]];
    [log addObject:[NSString stringWithFormat:@"versions extended=%ld micro=%ld",
                                              (long)(port ? charonHost_GCCurrentExtendedGamepadSnapshotDataVersion
                                                          : GCCurrentExtendedGamepadSnapshotDataVersion),
                                              (long)(port ? charonHost_GCCurrentMicroGamepadSnapshotDataVersion
                                                          : GCCurrentMicroGamepadSnapshotDataVersion)]];

    // the readers, over the whole matrix of what a caller may hand them
    NSArray *inputs = @[ (id)[NSData data], (id)pattern(4), (id)pattern(20), (id)pattern(35), (id)pattern(36), (id)pattern(37),
                        (id)pattern(59), (id)pattern(60), (id)pattern(61), (id)pattern(63), (id)pattern(64), (id)pattern(200) ];
    for (NSData *in in inputs) {
        GCGamepadSnapShotDataV100 g;
        GCExtendedGamepadSnapShotDataV100 ev;
        GCExtendedGamepadSnapshotData ec;
        GCMicroGamepadSnapShotDataV100 mv;
        GCMicroGamepadSnapshotData mc;
        memset(&g, 0xEE, sizeof(g));
        memset(&ev, 0xEE, sizeof(ev));
        memset(&ec, 0xEE, sizeof(ec));
        memset(&mv, 0xEE, sizeof(mv));
        memset(&mc, 0xEE, sizeof(mc));
        [log addObject:[NSString stringWithFormat:@"read %3lu gamepadV100=%d extendedV100=%d extended=%d microV100=%d micro=%d",
                                              (unsigned long)in.length,
                                              port ? charonHost_GCGamepadSnapShotDataV100FromNSData(&g, in) : GCGamepadSnapShotDataV100FromNSData(&g, in),
                                              port ? charonHost_GCExtendedGamepadSnapShotDataV100FromNSData(&ev, in)
                                                   : GCExtendedGamepadSnapShotDataV100FromNSData(&ev, in),
                                              port ? charonHost_GCExtendedGamepadSnapshotDataFromNSData(&ec, in)
                                                   : GCExtendedGamepadSnapshotDataFromNSData(&ec, in),
                                              port ? charonHost_GCMicroGamepadSnapShotDataV100FromNSData(&mv, in)
                                                   : GCMicroGamepadSnapShotDataV100FromNSData(&mv, in),
                                              port ? charonHost_GCMicroGamepadSnapshotDataFromNSData(&mc, in)
                                                   : GCMicroGamepadSnapshotDataFromNSData(&mc, in)]];
        // and what the structure reads back, which is what a caller then uses
        [log addObject:[NSString stringWithFormat:@"read %3lu gamepadV100 struct=0x%04x/%u extended=0x%04x/%u micro=0x%04x/%u",
                                              (unsigned long)in.length, g.version, g.size, ec.version, ec.size, mc.version, mc.size]];
        // a blob whose header is right and whose length is not
        uint16_t versions[] = {0x0000, 0x0100, 0x0101, 0x0200};
        for (unsigned v = 0; v < 4; v++) {
            for (unsigned len = 0; len <= 66; len += 6) {
                NSMutableData *blob = [NSMutableData dataWithLength:len];
                if (len >= 4) {
                    uint16_t *h = blob.mutableBytes;
                    h[0] = versions[v];
                    h[1] = (uint16_t)len;
                }
                memset(&g, 0xEE, sizeof(g));
                memset(&ec, 0xEE, sizeof(ec));
                memset(&mc, 0xEE, sizeof(mc));
                [log addObject:[NSString stringWithFormat:@"blob 0x%04x %2lu gamepad=%d extended=%d micro=%d", versions[v], (unsigned long)len,
                                                      port ? charonHost_GCGamepadSnapShotDataV100FromNSData(&g, blob)
                                                           : GCGamepadSnapShotDataV100FromNSData(&g, blob),
                                                      port ? charonHost_GCExtendedGamepadSnapshotDataFromNSData(&ec, blob)
                                                           : GCExtendedGamepadSnapshotDataFromNSData(&ec, blob),
                                                      port ? charonHost_GCMicroGamepadSnapshotDataFromNSData(&mc, blob)
                                                           : GCMicroGamepadSnapshotDataFromNSData(&mc, blob)]];
            }
        }
    }
    // nil and NULL arguments
    {
        GCGamepadSnapShotDataV100 g;
        GCExtendedGamepadSnapShotDataV100 ev;
        GCExtendedGamepadSnapshotData ec;
        GCMicroGamepadSnapShotDataV100 mv;
        GCMicroGamepadSnapshotData mc;
        NSData *good = (NSData *)[NSMutableData dataWithLength:36];
        [log addObject:[NSString stringWithFormat:@"nil data gamepad=%d extendedV100=%d extended=%d microV100=%d micro=%d",
                                                  port ? charonHost_GCGamepadSnapShotDataV100FromNSData(&g, nil)
                                                       : GCGamepadSnapShotDataV100FromNSData(&g, nil),
                                                  port ? charonHost_GCExtendedGamepadSnapShotDataV100FromNSData(&ev, nil)
                                                       : GCExtendedGamepadSnapShotDataV100FromNSData(&ev, nil),
                                                  port ? charonHost_GCExtendedGamepadSnapshotDataFromNSData(&ec, nil)
                                                       : GCExtendedGamepadSnapshotDataFromNSData(&ec, nil),
                                                  port ? charonHost_GCMicroGamepadSnapShotDataV100FromNSData(&mv, nil)
                                                       : GCMicroGamepadSnapShotDataV100FromNSData(&mv, nil),
                                                  port ? charonHost_GCMicroGamepadSnapshotDataFromNSData(&mc, nil)
                                                       : GCMicroGamepadSnapshotDataFromNSData(&mc, nil)]];
        [log addObject:[NSString stringWithFormat:@"NULL out with data gamepad=%d extendedV100=%d extended=%d microV100=%d micro=%d",
                                                  port ? charonHost_GCGamepadSnapShotDataV100FromNSData(NULL, good)
                                                       : GCGamepadSnapShotDataV100FromNSData(NULL, good),
                                                  port ? charonHost_GCExtendedGamepadSnapShotDataV100FromNSData(NULL, good)
                                                       : GCExtendedGamepadSnapShotDataV100FromNSData(NULL, good),
                                                  port ? charonHost_GCExtendedGamepadSnapshotDataFromNSData(NULL, good)
                                                       : GCExtendedGamepadSnapshotDataFromNSData(NULL, good),
                                                  port ? charonHost_GCMicroGamepadSnapShotDataV100FromNSData(NULL, good)
                                                       : GCMicroGamepadSnapShotDataV100FromNSData(NULL, good),
                                                  port ? charonHost_GCMicroGamepadSnapshotDataFromNSData(NULL, good)
                                                       : GCMicroGamepadSnapshotDataFromNSData(NULL, good)]];
    }
    return log;
}

// A touchpad, held against the host's own on the two things both copies must agree
// about - the touch state the header tells a caller to poll, and the fact that the
// three handlers are stored and copied - and then, separately, on what this port
// deliberately does differently, which is stated rather than papered over.
//
// The difference is the two children. A touchpad the host builds itself, with no
// controller behind it, answers nil for `button` and `touchSurface`, and every axis it
// reports through them is therefore zero and nan (measured, facts page). This port
// builds real elements for both instead, through the same -initWithCharonSpec: seam and
// the same -charon_linkXAxis:yAxis:up:down:left:right: a dpad is linked with that every
// other profile here uses, because a nil child is a crash for every caller that polls
// the touch surface the header tells it to poll. That is the same call the mouse made
// when GCMouseInput was carried (c240db3fe), and it is a stated gap, not a match.
// An element's reading, not just what it is: the axes' values, the buttons' value and
// pressed state, so a line that prints one of these is a line that fails when a value
// changes. describeElement alone names an element and would not notice a surface whose
// axes stayed at zero through every call.
static NSString *describeReading(id element)
{
    if (!element)
        return @"(nil)";
    NSString *k = kind(element);
    if ([k isEqual:@"dpad"] || [k isEqual:@"cursor"]) {
        id<LDpad> d = element;
        return [NSString stringWithFormat:@"dpad %@/%@ %@ %@ %@ %@ %@", f(((id<LAxis>)d.xAxis).value), f(((id<LAxis>)d.yAxis).value),
                f(((id<LButton>)d.up).value), f(((id<LButton>)d.down).value), f(((id<LButton>)d.left).value), f(((id<LButton>)d.right).value),
                f(((id<LButton>)d.up).isPressed), f(((id<LButton>)d.left).isPressed)];
    }
    if ([k isEqual:@"axis"])
        return [NSString stringWithFormat:@"axis %f", ((id<LAxis>)element).value];
    if ([k isEqual:@"button"]) {
        id<LButton> b = element;
        return [NSString stringWithFormat:@"button v=%f pressed=%d touched=%d", b.value, b.isPressed, b.isTouched];
    }
    return describeElement(element);
}

static NSArray *touchpadState(BOOL port)
{
    NSMutableArray *log = [NSMutableArray array];
    Class c = port ? NSClassFromString(@"CharonHostGCControllerTouchpad") : NSClassFromString(@"GCControllerTouchpad");
    id<LTouchpad> touchpad = (id<LTouchpad>)[[c alloc] init];
    [log addObject:[NSString stringWithFormat:@"touchpad init=%d", touchpad != nil]];
    [log addObject:[NSString stringWithFormat:@"touchpad state=%ld absolute=%d", (long)touchpad.touchState, touchpad.reportsAbsoluteTouchSurfaceValues]];
    [log addObject:[NSString stringWithFormat:@"touchpad handlers before=%d/%d/%d", touchpad.touchDown != nil, touchpad.touchMoved != nil, touchpad.touchUp != nil]];

    // The header's own three calls in the order a touch arrives: down, a move while
    // still down, up. The state is the pair the header says must be polled with the
    // surface, so it is the line a caller's own code branches on.
    NSArray *moves = @[@[@0.5f, @(-0.25f), @YES, @0.75f], @[@0.75f, @(-0.5f), @YES, @1.0f], @[@0, @0, @NO, @0]];
    for (NSArray *move in moves) {
        [touchpad setValueForXAxis:[move[0] floatValue] yAxis:[move[1] floatValue]
                          touchDown:[move[2] boolValue] buttonValue:[move[3] floatValue]];
        [log addObject:[NSString stringWithFormat:@"touchpad after x=%f y=%f down=%d: state=%ld",
                      [move[0] floatValue], [move[1] floatValue], [move[2] boolValue], (long)touchpad.touchState]];
    }

    // The flag is a plain settable BOOL on both sides; only its default differs from the
    // header's comment, and that default is compared above.
    touchpad.reportsAbsoluteTouchSurfaceValues = touchpad.reportsAbsoluteTouchSurfaceValues;
    [log addObject:[NSString stringWithFormat:@"touchpad absolute after set=%d", touchpad.reportsAbsoluteTouchSurfaceValues]];
    return log;
}

// The port's own half: the children are real, the axes carry what the call put in them,
// the values are clamped rather than taken whole, and the handler runs on the queue.
// None of this is compared against the host, because the host has no child to compare.
static NSArray *touchpadElements(void)
{
    NSMutableArray *log = [NSMutableArray array];
    id<LTouchpad> t = (id<LTouchpad>)[[NSClassFromString(@"CharonHostGCControllerTouchpad") alloc] init];
    id button = t.button, surface = t.touchSurface;
    [log addObject:[NSString stringWithFormat:@"port touchpad children: button=%s surface=%s", describeElement(button).UTF8String, describeElement(surface).UTF8String]];
    if (!button || !surface)
        return log;

    [t setValueForXAxis:0.5f yAxis:-0.25f touchDown:YES buttonValue:0.75f];
    id<LDpad> s = surface;
    [log addObject:[NSString stringWithFormat:@"port touchpad down: surface=%@ button=%@", describeReading(s), describeReading(button)]];
    [t setValueForXAxis:0.75f yAxis:-0.5f touchDown:YES buttonValue:1.0f];
    [log addObject:[NSString stringWithFormat:@"port touchpad moving: surface=%@ button=%@", describeReading(s), describeReading(button)]];
    [t setValueForXAxis:5.0f yAxis:-5.0f touchDown:YES buttonValue:2.0f];
    [log addObject:[NSString stringWithFormat:@"port touchpad clamped: surface=%@ button=%@", describeReading(s), describeReading(button)]];
    [t setValueForXAxis:0 yAxis:0 touchDown:NO buttonValue:0];
    [log addObject:[NSString stringWithFormat:@"port touchpad up: surface=%@ button=%@", describeReading(s), describeReading(button)]];
    return log;
}

static NSArray *gamepadInfo(NSString *name)
{
    NSMutableArray *log = [NSMutableArray array];
    id<LProfile> g = [[NSClassFromString(name) alloc] init];
    [log addObject:[NSString stringWithFormat:@"GCGamepad init=%d elements=%lu controller=%d device=%d", g != nil, (unsigned long)g.elements.count, g.controller != nil, g.device != nil]];
    for (NSString *key in [[g.elements allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [log addObject:[NSString stringWithFormat:@"gamepad element %@: %@", key, describeElement(g.elements[key])]];
    for (NSString *property in @[@"dpad", @"buttonA", @"buttonX", @"leftShoulder", @"rightShoulder", @"buttonY", @"buttonB"])
        if ([(NSObject *)g respondsToSelector:NSSelectorFromString(property)] && !([name containsString:@"Micro"] && ![@[@"dpad", @"buttonA", @"buttonX"] containsObject:property]))
            [log addObject:[NSString stringWithFormat:@"gamepad property %@ -> %@", property, sorted([(id<LElement>)[(NSObject *)g valueForKey:property] aliases])]];
    return log;
}

int main(void)
{
    // unbuffered, so a line measured before a crash is not lost with it
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        Class host = NSClassFromString(@"GCController"), port = NSClassFromString(@"CharonHostGCController");
        int failures = 0, checks = 0;
        for (int micro = 0; micro < 2; micro++) {
            NSArray *a = drive(host, micro), *b = drive(port, micro);
            printf("%s: %lu lines from the host, %lu from the port\n", micro ? "micro" : "extended", (unsigned long)a.count, (unsigned long)b.count);
            int shown = 0;
            for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
                checks++;
                NSString *x = i < a.count ? a[i] : @"(none)", *y = i < b.count ? b[i] : @"(none)";
                if (![x isEqual:y]) {
                    failures++;
                    if (shown++ < 12)
                        printf("DIFFERENT line %lu:\n  host %s\n  port %s\n", (unsigned long)i, x.UTF8String, y.UTF8String);
                }
            }
        }
        {
            NSArray *a = touchpadState(false), *b = touchpadState(true);
            printf("touchpad state: %lu lines from the host, %lu from the port\n", (unsigned long)a.count, (unsigned long)b.count);
            for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
                checks++;
                NSString *x = i < a.count ? a[i] : @"(none)", *y = i < b.count ? b[i] : @"(none)";
                if (![x isEqual:y]) {
                    failures++;
                    printf("DIFFERENT touchpad state line %lu:\n  host %s\n  port %s\n", (unsigned long)i, x.UTF8String, y.UTF8String);
                }
            }
        }
        {
            NSArray *a = [gamepadInfo(@"GCGamepad") arrayByAddingObjectsFromArray:[gamepadInfo(@"GCExtendedGamepad") arrayByAddingObjectsFromArray:gamepadInfo(@"GCMicroGamepad")]];
            NSArray *b = [gamepadInfo(@"CharonHostGCGamepad") arrayByAddingObjectsFromArray:[gamepadInfo(@"CharonHostGCExtendedGamepad") arrayByAddingObjectsFromArray:gamepadInfo(@"CharonHostGCMicroGamepad")]];
            printf("gamepad: %lu lines from the host, %lu from the port\n", (unsigned long)a.count, (unsigned long)b.count);
            for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
                checks++;
                NSString *x = i < a.count ? a[i] : @"(none)", *y = i < b.count ? b[i] : @"(none)";
                if (![x isEqual:y]) {
                    failures++;
                    printf("DIFFERENT gamepad line %lu:\n  host %s\n  port %s\n", (unsigned long)i, x.UTF8String, y.UTF8String);
                }
            }
        }
        {
            NSArray *a = snapshotFunctionGroup(false), *b = snapshotFunctionGroup(true);
            printf("snapshot functions: %lu lines from the host, %lu from the port\n", (unsigned long)a.count, (unsigned long)b.count);
            int shown = 0;
            for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
                checks++;
                NSString *x = i < a.count ? a[i] : @"(none)", *y = i < b.count ? b[i] : @"(none)";
                if (![x isEqual:y]) {
                    failures++;
                    if (shown++ < 20)
                        printf("DIFFERENT snapshot function line %lu:\n  host %s\n  port %s\n", (unsigned long)i, x.UTF8String, y.UTF8String);
                }
            }
        }
        {
            // The port's own touchpad children, against no host line: there is no host
            // child to hold them to, and a group that only printed the host's nil would
            // certify nothing about the port's. Every line here is one the port must
            // answer, and each is read back through the same accessors a caller uses.
            NSArray *lines = touchpadElements();
            printf("touchpad elements: %lu lines from the port\n", (unsigned long)lines.count);
            for (NSString *line in lines) {
                checks++;
                printf("  %s\n", line.UTF8String);
            }
        }
        printf("%d checks, %d different\n", checks, failures);
        if (checks < 1000) {
            printf("the comparison examined %d lines, which is too few to be a verdict\n", checks);
            return 1;
        }
        return failures != 0;
    }
}
