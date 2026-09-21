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
        printf("%d checks, %d different\n", checks, failures);
        return failures != 0;
    }
}
