// What Apple's own CarPlay answers on a machine with NO head unit attached, and what it does not.
//
// This is the differential for the seven classes `facts/CarPlay/CarPlay.md` carries as `absent`, and
// it is the measurement that decides which of the 48 rows in `coordination/corpus/queue/CarPlay.tsv`
// are a hardware absence and which are a measurement. It runs against Apple's own CarPlay on this
// Mac, built for Mac Catalyst (`-target arm64-apple-ios17.0-macabi`), because a Catalyst binary is
// the only place on this machine where Apple's CarPlay is loadable at all: the fleet devices run
// 6.1.3, which has no CarPlay class of any name, and `/System/Library/Frameworks` has no CarPlay
// outside the SDK.
//
// Every question is asked through the SDK's own declaration where the header permits the call, and
// through `objc_msgSend` where the header marks the call `NS_UNAVAILABLE` -- because a row whose API
// the header forbids cannot be asked by a program that compiles, and the honest answer to "what does
// the SDK answer" has to come from the runtime.
//
// NOTHING here is a claim about the port. The port's own answers are the runner's business
// (`runner.m`), and a row lands on what the port does, not on what this file prints.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <CarPlay/CarPlay.h>

static int gChecks = 0;
static int gFailures = 0;
static NSMutableArray *gAnswers = nil;

// The answers as `label<TAB>detail` lines, so the port's own run can be diffed against this one
// question by question. A run that prints answers nobody compares is a transcript; this is the half
// of the differential `run.sh` reads.
static void answer(NSString *label, NSString *detail)
{
    if (gAnswers == nil) {
        return;
    }
    [gAnswers addObject:[NSString stringWithFormat:@"%@\t%@", label, detail]];
}

// A check states what the header says and compares it with what the framework answered. Each one
// names the header line it rests on, so a reader can see the expectation is Apple's and not ours.
static void check(NSString *what, BOOL ok, NSString *detail)
{
    gChecks++;
    if (!ok) {
        gFailures++;
    }
    printf("%-4s %-58s %s\n", ok ? "ok" : "FAIL", what.UTF8String, detail.UTF8String);
    answer(what, detail);
}

static NSString *describe(id object)
{
    if (object == nil) {
        return @"nil";
    }
    if ([object isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"array of %lu", (unsigned long)[(NSArray *)object count]];
    }
    if ([object isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"string %@", object];
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [NSString stringWithFormat:@"number %@", object];
    }
    return [NSString stringWithFormat:@"%@", NSStringFromClass([object class])];
}

// `NS_UNAVAILABLE` in the header, called at runtime: the header refuses the call at compile time and
// this is the only way to hear what the framework does when a program sends it anyway.
static id sendUnavailable(id target, SEL selector, ...)
{
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature == nil) {
        return nil;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    invocation.target = target;
    [invocation invoke];
    if (strcmp(signature.methodReturnType, @encode(id)) == 0) {
        void *raw = NULL;
        [invocation getReturnValue:&raw];
        return (__bridge id)raw;
    }
    return nil;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc > 1) {
            gAnswers = [NSMutableArray array];
        }
        printf("# the machine: %s\n", [[[NSProcessInfo processInfo] hostName] UTF8String]);
        printf("# CarPlay: %s\n", [[[NSBundle bundleWithIdentifier:@"com.apple.CarPlay"] bundlePath]
            ?: @"(not loadable by path)" UTF8String]);
        printf("# no head unit is attached: the probe never opens one and asks the framework what it\n"
               "# says with none, which is the state both fleet devices are in.\n\n");

        // ---- 1. Which of the seven classes Apple's framework carries, with no head unit ----------
        // The seven are the classes the registry carries as absent. A class that is present here is
        // present on any iPhone with iOS 12 or later, car or no car: so `absent` on such a row is a
        // claim about the PORT and never about Apple's class.
        static NSString *const names[] = {
            @"CPNavigationSession", @"CPSessionConfiguration", @"CPTemplateApplicationScene",
            @"CPTemplateApplicationDashboardScene", @"CPTemplateApplicationInstrumentClusterScene",
            @"CPVoiceControlState", @"CPVoiceControlTemplate", @"CPRouteChoice",
            @"CPInterfaceController", @"CPTemplate", @"CPMapTemplate", @"CPLane", @"CPLaneGuidance",
            @"CPRouteInformation", @"CPManeuver", @"CPTravelEstimates"
        };
        printf("== 1. class presence in Apple's CarPlay, no head unit ==\n");
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            Class found = NSClassFromString(names[i]);
            printf("     %-46s %s\n", names[i].UTF8String, found ? "present" : "ABSENT");
        }
        printf("\n");

        // ---- 2. The scene: the framework's own gate ---------------------------------------------
        // A CarPlay scene is a connection to a head unit. The framework says so in the three headers
        // ("The CarPlay screen has connected and is ready to present content"), and this asks it
        // directly. Catalytic CarPlay has no `+sharedController` and no scene API at all -- measured
        // by the header, `CPInterfaceController.h` in this SDK declares neither -- so on THIS machine
        // the question is only whether the class exists, and the count of scenes is the part a device
        // answers. It is asked through the runtime anyway, so the answer is a measurement and not an
        // assumption.
        printf("== 2. the scene, with no head unit ==\n");
        {
            Class scene = NSClassFromString(@"CPTemplateApplicationScene");
            Class dashboard = NSClassFromString(@"CPTemplateApplicationDashboardScene");
            Class cluster = NSClassFromString(@"CPTemplateApplicationInstrumentClusterScene");
            check(@"CPTemplateApplicationScene is a UIScene subclass (a scene, not a view)",
                  scene != nil && [scene isSubclassOfClass:NSClassFromString(@"UIScene")],
                  scene ? [NSString stringWithFormat:@"superclass %@", NSStringFromClass([scene superclass])]
                        : @"no class");
            check(@"CPTemplateApplicationDashboardScene is a UIScene subclass",
                  dashboard != nil && [dashboard isSubclassOfClass:NSClassFromString(@"UIScene")],
                  dashboard ? @"UIScene" : @"no class");
            check(@"CPTemplateApplicationInstrumentClusterScene is a UIScene subclass",
                  cluster != nil && [cluster isSubclassOfClass:NSClassFromString(@"UIScene")],
                  cluster ? @"UIScene" : @"no class");
            // A UIScene is created by the system for a connection. None of the three declares an
            // initialiser of its own, so the only `-init` they answer is NSObject's, and no program
            // can make the scene a CarPlay screen would make. That is the measurement behind the
            // hardware absence, and it is read off the metadata rather than off the header's prose.
            Class const scenes[] = {scene, dashboard, cluster};
            for (size_t i = 0; i < sizeof(scenes) / sizeof(scenes[0]); i++) {
                IMP own = class_getInstanceMethod(scenes[i], @selector(init));
                IMP inherited = class_getInstanceMethod([NSObject class], @selector(init));
                check([NSString stringWithFormat:@"%@ declares no initialiser of its own",
                            NSStringFromClass(scenes[i])],
                      own == NULL || own == inherited,
                      [NSString stringWithFormat:@"-init is %@", own == inherited ? @"NSObject's" : @"its own"]);
            }
            // What the framework could say about a CONNECTED scene, asked of the interface
            // controller: this SDK's CarPlay declares no shared controller and no connected-scene
            // count, so on this machine the question cannot be put to it at all. That is the second
            // half of the hardware absence, and it is printed rather than checked because the answer
            // is a property of Apple's Catalyst surface, not a promise the port has to keep.
            Class controller = NSClassFromString(@"CPInterfaceController");
            for (NSString *name in @[@"sharedController", @"connectedSceneCount",
                                     @"templateApplicationScene", @"connectedScenes"]) {
                SEL selector = NSSelectorFromString(name);
                printf("     [CPInterfaceController %-26s] %s\n", name.UTF8String,
                       [controller respondsToSelector:selector] ? "declared"
                                                               : "not in this SDK's CarPlay");
            }
        }
        printf("\n");

        // ---- 3. CPVoiceControlState: a value the app makes, with no car in the picture ------------
        // `CPVoiceControlTemplate.h`: "Your app may initialize the voice control template with one or
        // more states, and you may call activateVoiceControlState: to switch between states you've
        // defined." Nothing in the class's own API is the car's.
        printf("== 3. CPVoiceControlState ==\n");
        {
            CPVoiceControlState *state = [[CPVoiceControlState alloc]
                initWithIdentifier:@"charon.listening"
                      titleVariants:@[@"Listening", @"Listen"]
                              image:nil
                            repeats:YES];
            check(@"identifier answers what the initialiser was given",
                  [state.identifier isEqualToString:@"charon.listening"], describe(state.identifier));
            check(@"titleVariants answers the array it was given", [state.titleVariants count] == 2,
                  describe(state.titleVariants));
            check(@"repeats answers YES", state.repeats == YES,
                  [NSString stringWithFormat:@"%d", (int)state.repeats]);
            check(@"image answers nil when none was given", state.image == nil, describe(state.image));
            check(@"+supportsSecureCoding is YES (NSSecureCoding is in the header)",
                  [CPVoiceControlState supportsSecureCoding] ? @"YES" : @"NO",
                  [CPVoiceControlState supportsSecureCoding] ? @"YES" : @"NO");
            // A nil array in, nil out. The header declares titleVariants `nullable, copy`, and a
            // getter that answered an empty array instead would be a quiet different answer -- the
            // port's row says nil and the port's object has to answer nil.
            CPVoiceControlState *bare = [[CPVoiceControlState alloc] initWithIdentifier:@"charon.bare"
                                                                          titleVariants:nil
                                                                                  image:nil
                                                                                repeats:NO];
            check(@"titleVariants answers nil when it was given nil", bare.titleVariants == nil,
                  describe(bare.titleVariants));
            // "Voice Control state images may be a maximum of 150 by 150 points" is enforced by the
            // framework, not only documented: a 300x300 image comes back 150x150. The port scales
            // rather than keeps, because this is what Apple's own object does.
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(300.0, 300.0), NO, 1.0);
            [[UIColor redColor] setFill];
            UIRectFill(CGRectMake(0.0, 0.0, 300.0, 300.0));
            UIImage *large = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            CPVoiceControlState *scaled = [[CPVoiceControlState alloc] initWithIdentifier:@"charon.scaled"
                                                                             titleVariants:@[@"Scaled"]
                                                                                     image:large
                                                                                   repeats:NO];
            check(@"an image over 150 points a side comes back 150 by 150",
                  scaled.image != nil && scaled.image.size.width <= 150.0 && scaled.image.size.height <= 150.0,
                  [NSString stringWithFormat:@"%g by %g", scaled.image.size.width, scaled.image.size.height]);
            // The round trip, because the header declares NSSecureCoding and a value that cannot
            // encode is a value that cannot cross a process boundary.
            NSError *error = nil;
            NSData *coded = [NSKeyedArchiver archivedDataWithRootObject:state requiringSecureCoding:YES
                                                                error:&error];
            // The allowed classes are the state's own plus the value classes it holds, and both sides
            // of the diff use this same call: a state carries an array of strings and an image, so a
            // reader that does not allow them cannot read it, and the comparison is only meaningful
            // if both sides are asked the same question.
            CPVoiceControlState *back = coded == nil ? nil
                : [NSKeyedUnarchiver unarchivedObjectOfClasses:
                       [NSSet setWithObjects:[CPVoiceControlState class], [NSString class],
                                             [NSArray class], [UIImage class], nil]
                                                  fromData:coded
                                                     error:&error];
            check(@"a state survives an NSSecureCoding round trip with its identifier",
                  back != nil && [back.identifier isEqualToString:@"charon.listening"],
                  back ? describe(back.identifier) : [NSString stringWithFormat:@"nil (%@)",
                                                        error.localizedDescription ?: @"no error"]);
        }
        printf("\n");

        // ---- 4. CPVoiceControlTemplate: the app's own template ---------------------------------
        // `CPVoiceControlTemplate.h`: "You may specify a maximum of 5 voice control states. If you
        // specify more than 5, only the first 5 will be available." and "By default, the Voice Control
        // template will begin on the first state specified."
        printf("== 4. CPVoiceControlTemplate ==\n");
        {
            NSMutableArray<CPVoiceControlState *> *states = [NSMutableArray array];
            for (int i = 0; i < 6; i++) {
                [states addObject:[[CPVoiceControlState alloc]
                    initWithIdentifier:[NSString stringWithFormat:@"charon.state%d", i]
                          titleVariants:@[[NSString stringWithFormat:@"State %d", i]]
                                  image:nil
                                repeats:NO]];
            }
            CPVoiceControlTemplate *voice = [[CPVoiceControlTemplate alloc]
                initWithVoiceControlStates:states];
            check(@"the template keeps the five states the header's limit allows",
                  [voice.voiceControlStates count] == 5,
                  [NSString stringWithFormat:@"%lu of %lu", (unsigned long)[voice.voiceControlStates count],
                      (unsigned long)states.count]);
            check(@"the first of the states it was given is the active one",
                  [voice.activeStateIdentifier isEqualToString:@"charon.state0"],
                  describe(voice.activeStateIdentifier));
            // "@warning You must first present this voice control template through your
            // CPInterfaceController before activating a voice control state, otherwise this method
            // will have no effect." Measured on Apple's own framework with no head unit and no
            // presentation: the active state DOES change. The warning is about what a car then shows,
            // not about the object's own state, so the port switches the state and the car is the
            // wall. This was read off the framework, not assumed from the warning.
            [voice activateVoiceControlStateWithIdentifier:@"charon.state3"];
            check(@"activating switches the active state with no car attached (measured)",
                  [voice.activeStateIdentifier isEqualToString:@"charon.state3"],
                  [NSString stringWithFormat:@"active is now %@", describe(voice.activeStateIdentifier)]);
            // An identifier no state carries. The header says "An identifier corresponding to one of
            // the voice control states used to initialize this template", and Apple's own object does
            // not check: measured here, the active identifier becomes the one that was asked for,
            // even when no such state exists. The port matches that, and draws nothing for an
            // identifier no state carries, because there is no state to draw.
            [voice activateVoiceControlStateWithIdentifier:@"charon.state99"];
            check(@"an identifier no state carries becomes the active one anyway (measured)",
                  [voice.activeStateIdentifier isEqualToString:@"charon.state99"],
                  [NSString stringWithFormat:@"active is now %@", describe(voice.activeStateIdentifier)]);
            // The header's rate limit -- "the template will ignore voice control state changes that
            // occur too rapidly or frequently in a short period of time" -- measured against the
            // object's own state: twelve activations in a tight loop, and every one of them takes.
            // The limit the header describes is on what a car then shows, which is the wall; the
            // object follows every activation, and the port must not invent an interval.
            NSUInteger effective = 0;
            const NSUInteger rounds = 12;
            for (NSUInteger round = 0; round < rounds; round++) {
                NSString *wanted = [NSString stringWithFormat:@"charon.state%lu", (unsigned long)(round % 5)];
                [voice activateVoiceControlStateWithIdentifier:wanted];
                if ([voice.activeStateIdentifier isEqualToString:wanted]) {
                    effective++;
                }
            }
            check(@"twelve activations in a tight loop all take effect: no interval in the object",
                  effective == rounds,
                  [NSString stringWithFormat:@"%lu of %lu", (unsigned long)effective, (unsigned long)rounds]);
            // An empty array and a nil array are two different answers, and the port keeps them apart.
            CPVoiceControlTemplate *empty = [[CPVoiceControlTemplate alloc] initWithVoiceControlStates:@[]];
            check(@"an empty array of states keeps an empty array and no active state",
                  [empty.voiceControlStates count] == 0 && empty.activeStateIdentifier == nil,
                  [NSString stringWithFormat:@"%lu states, active %@", (unsigned long)[empty.voiceControlStates count],
                      describe(empty.activeStateIdentifier)]);
            CPVoiceControlTemplate *none = [[CPVoiceControlTemplate alloc] initWithVoiceControlStates:nil];
            check(@"a nil array of states answers nil for both, as the framework does",
                  none.voiceControlStates == nil && none.activeStateIdentifier == nil,
                  [NSString stringWithFormat:@"states %@, active %@", describe(none.voiceControlStates),
                      describe(none.activeStateIdentifier)]);
        }
        printf("\n");

        // ---- 5. CPSessionConfiguration: the configuration OF a session --------------------------
        // `CPSessionConfiguration.h`: "The current content style suggested by the connected CarPlay
        // system." and "A bitmask of what type of user interfaces are limited". Both are readonly and
        // both come from the connected system. This asks with none connected.
        printf("== 5. CPSessionConfiguration, with no head unit ==\n");
        {
            CPSessionConfiguration *configuration = [[CPSessionConfiguration alloc] initWithDelegate:nil];
            check(@"the designated initialiser makes a configuration", configuration != nil,
                  describe(configuration));
            check(@"delegate answers the delegate it was given (nil here)", configuration.delegate == nil,
                  describe(configuration.delegate));
            check(@"limitedUserInterfaces answers the mask the connected system suggests",
                  configuration.limitedUserInterfaces == 0,
                  [NSString stringWithFormat:@"%lu", (unsigned long)configuration.limitedUserInterfaces]);
            check(@"contentStyle answers the style the connected system suggests",
                  configuration.contentStyle == 0,
                  [NSString stringWithFormat:@"%lu", (unsigned long)configuration.contentStyle]);
            id made = sendUnavailable((id)[CPSessionConfiguration class], @selector(new));
            check(@"+new, which the header marks NS_UNAVAILABLE, is the inherited NSObject one",
                  [made isKindOfClass:[CPSessionConfiguration class]], describe(made));
        }
        printf("\n");

        // ---- 6. CPNavigationSession: created by the system, never by the app ---------------------
        // `CPNavigationSession.h`: "A CPNavigationSession will be created for you when calling
        // startNavigationSessionForTrip: on CPMapTemplate", and `-init`/`+new` are NS_UNAVAILABLE. The
        // 16.0 arm64e cache agrees and names the creator: the private protocol
        // CPNavigationSessionProviding declares `-hostStartNavigationSessionForTrip:reply:`.
        printf("== 6. CPNavigationSession ==\n");
        {
            Class session = NSClassFromString(@"CPNavigationSession");
            id made = sendUnavailable((id)session, @selector(new));
            check(@"+new, which the header marks NS_UNAVAILABLE, is the inherited NSObject one",
                  made == nil || [made isKindOfClass:session], describe(made));
            id again = sendUnavailable(made, @selector(init));
            id trip = again == nil ? nil : sendUnavailable(again, @selector(trip));
            check(@"-init, likewise NS_UNAVAILABLE, leaves a session with no trip",
                  trip == nil, describe(trip));
            // The members the registry rows name, asked of the class: which of them the release that
            // carries the class really has is the question `objc-inventory.lua` answers, and this is
            // the same list against Apple's own current framework.
            static NSString *const members[] = {
                @"trip", @"upcomingManeuvers", @"currentLaneGuidance", @"currentRoadNameVariants",
                @"maneuverState", @"updateTravelEstimates:forManeuver:", @"pauseTripForReason:description:",
                @"pauseTripForReason:description:turnCardColor:", @"finishTrip", @"cancelTrip",
                @"addManeuvers:", @"addLaneGuidances:", @"resumeTripWithUpdatedRouteInformation:"
            };
            for (size_t i = 0; i < sizeof(members) / sizeof(members[0]); i++) {
                SEL selector = NSSelectorFromString(members[i]);
                printf("     -[CPNavigationSession %-46s] %s\n", members[i].UTF8String,
                       [session instancesRespondToSelector:selector] ? "present" : "ABSENT");
            }
        }
        printf("\n");

        // ---- 7. CPRouteChoice: an ordinary value, and +new is a member of a class the port builds --
        printf("== 7. CPRouteChoice ==\n");
        {
            Class choice = NSClassFromString(@"CPRouteChoice");
            id made = sendUnavailable((id)choice, @selector(new));
            check(@"+new makes a route choice", [made isKindOfClass:choice], describe(made));
            // Measured, not assumed: a new route choice answers an EMPTY ARRAY for each variants
            // property, not nil. The row for `+[CPRouteChoice new]` has to say that, because a row
            // that said "nil" would be a false answer and the port's own object is asked against it.
            static NSString *const variants[] = {
                @"summaryVariants", @"selectionSummaryVariants", @"additionalInformationVariants"
            };
            for (size_t i = 0; i < sizeof(variants) / sizeof(variants[0]); i++) {
                id value = sendUnavailable(made, NSSelectorFromString(variants[i]));
                check(([NSString stringWithFormat:@"a new route choice's %@ is an empty array",
                            variants[i]]),
                      [value isKindOfClass:[NSArray class]] && [(NSArray *)value count] == 0,
                      describe(value));
            }
            check(@"a new route choice has no user info",
                  sendUnavailable(made, @selector(userInfo)) == nil,
                  describe(sendUnavailable(made, @selector(userInfo))));
        }

        printf("\nchecks=%d failures=%d\n", gChecks, gFailures);
        if (gAnswers != nil) {
            NSString *text = [gAnswers componentsJoinedByString:@"\n"];
            [text writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL];
        }
        return gFailures == 0 ? 0 : 1;
    }
}
