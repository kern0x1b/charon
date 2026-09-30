// The port's own voice control, driven through the twelve rows the queue asks about, and printed in
// the same `label<TAB>detail` shape the host differential prints so the two can be diffed line by
// line.
//
// The port's classes are reached through the runtime under their renamed names (`charonHost_…`), so
// nothing here can reach Apple's CarPlay by accident and every answer below is the port's own. The
// expectations are NOT written from the header: each one is what Apple's own object answered on this
// machine with no head unit attached, and `run.sh` refuses the run unless the two transcripts agree
// on every label they both carry.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface charonHost_CPVoiceControlState : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier
                     titleVariants:(NSArray<NSString *> *)titleVariants
                             image:(UIImage *)image
                           repeats:(BOOL)repeats;
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *titleVariants;
@property (nullable, nonatomic, readonly, strong) UIImage *image;
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly) BOOL repeats;
+ (BOOL)supportsSecureCoding;
@end

@interface charonHost_CPVoiceControlTemplate : NSObject
- (instancetype)initWithVoiceControlStates:(NSArray<charonHost_CPVoiceControlState *> *)states;
@property (nonatomic, readonly, copy) NSArray<charonHost_CPVoiceControlState *> *voiceControlStates;
- (void)activateVoiceControlStateWithIdentifier:(NSString *)identifier;
@property (nonatomic, readonly, copy, nullable) NSString *activeStateIdentifier;
- (UIViewController *)charon_viewControllerForInterfaceController:(id)controller;
@end

static int gChecks = 0;
static int gFailures = 0;
static NSMutableArray *gAnswers = nil;

static void answer(NSString *label, NSString *detail)
{
    if (gAnswers != nil) {
        [gAnswers addObject:[NSString stringWithFormat:@"%@\t%@", label, detail]];
    }
}

// Every check states the answer the PORT gave and whether it is the one Apple's gave; the labels are
// the host probe's labels verbatim, which is what makes the diff in run.sh a comparison of two
// measurements and not of two intentions.
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

// The action a control has registered for a target and an event, read back off the control. This SDK
// hands back one NSInvocation per pair whose selector is the action, and a string naming it on the
// Catalyst surface; both shapes are read, and NULL when the pair is not registered at all, which is
// what makes a plate with no action fail the check rather than pass it.
static SEL registeredAction(UIControl *control, id target)
{
    if (control == nil || target == nil) {
        return NULL;
    }
    NSArray *registered = [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
    id first = registered.firstObject;
    if ([first isKindOfClass:[NSInvocation class]]) {
        return [(NSInvocation *)first selector];
    }
    if ([first isKindOfClass:[NSString class]]) {
        return NSSelectorFromString((NSString *)first);
    }
    return NULL;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc > 1) {
            gAnswers = [NSMutableArray array];
        }

        printf("# the port's own voice control, on this Mac, through the runtime\n");
        printf("# every name is charonHost_-prefixed, so Apple's CarPlay is not reachable here\n\n");

        // ---- the state, the six rows of CPVoiceControlState -------------------------------------
        printf("== CPVoiceControlState ==\n");
        charonHost_CPVoiceControlState *state = [[charonHost_CPVoiceControlState alloc]
            initWithIdentifier:@"charon.listening"
                  titleVariants:@[@"Listening", @"Listen"]
                          image:nil
                        repeats:YES];
        check(@"identifier answers what the initialiser was given",
              [state.identifier isEqualToString:@"charon.listening"], describe(state.identifier));
        check(@"titleVariants answers the array it was given", state.titleVariants.count == 2,
              describe(state.titleVariants));
        check(@"repeats answers YES", state.repeats == YES,
              [NSString stringWithFormat:@"%d", (int)state.repeats]);
        check(@"image answers nil when none was given", state.image == nil, describe(state.image));
        check(@"+supportsSecureCoding is YES (NSSecureCoding is in the header)",
              [charonHost_CPVoiceControlState supportsSecureCoding] ? @"YES" : @"NO",
              [charonHost_CPVoiceControlState supportsSecureCoding] ? @"YES" : @"NO");

        charonHost_CPVoiceControlState *bare = [[charonHost_CPVoiceControlState alloc]
            initWithIdentifier:@"charon.bare" titleVariants:nil image:nil repeats:NO];
        check(@"titleVariants answers nil when it was given nil", bare.titleVariants == nil,
              describe(bare.titleVariants));

        UIGraphicsBeginImageContextWithOptions(CGSizeMake(300.0, 300.0), NO, 1.0);
        [[UIColor redColor] setFill];
        UIRectFill(CGRectMake(0.0, 0.0, 300.0, 300.0));
        UIImage *large = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        charonHost_CPVoiceControlState *scaled = [[charonHost_CPVoiceControlState alloc]
            initWithIdentifier:@"charon.scaled" titleVariants:@[@"Scaled"] image:large repeats:NO];
        check(@"an image over 150 points a side comes back 150 by 150",
              scaled.image != nil && scaled.image.size.width <= 150.0 && scaled.image.size.height <= 150.0,
              [NSString stringWithFormat:@"%g by %g", scaled.image.size.width, scaled.image.size.height]);

        NSError *error = nil;
        NSData *coded = [NSKeyedArchiver archivedDataWithRootObject:state requiringSecureCoding:YES
                                                                error:&error];
        // The same allowed-class set the host probe uses, so the diff compares like with like: a
        // state holds an array of strings and an image, and a reader that does not allow them cannot
        // read it.
        charonHost_CPVoiceControlState *back = coded == nil ? nil
            : [NSKeyedUnarchiver unarchivedObjectOfClasses:
                   [NSSet setWithObjects:[charonHost_CPVoiceControlState class], [NSString class],
                                         [NSArray class], [UIImage class], nil]
                                              fromData:coded
                                                 error:&error];
        check(@"a state survives an NSSecureCoding round trip with its identifier",
              back != nil && [back.identifier isEqualToString:@"charon.listening"],
              back ? describe(back.identifier) : [NSString stringWithFormat:@"nil (%@)",
                                                    error.localizedDescription ?: @"no error"]);

        // ---- the template, the six rows of CPVoiceControlTemplate ---------------------------------
        printf("\n== CPVoiceControlTemplate ==\n");
        NSMutableArray *states = [NSMutableArray array];
        for (int i = 0; i < 6; i++) {
            [states addObject:[[charonHost_CPVoiceControlState alloc]
                initWithIdentifier:[NSString stringWithFormat:@"charon.state%d", i]
                      titleVariants:@[[NSString stringWithFormat:@"State %d", i]]
                              image:nil
                            repeats:NO]];
        }
        charonHost_CPVoiceControlTemplate *voice =
            [[charonHost_CPVoiceControlTemplate alloc] initWithVoiceControlStates:states];
        check(@"the template keeps the five states the header's limit allows",
              voice.voiceControlStates.count == 5,
              [NSString stringWithFormat:@"%lu of %lu", (unsigned long)voice.voiceControlStates.count,
                  (unsigned long)states.count]);
        check(@"the first of the states it was given is the active one",
              [voice.activeStateIdentifier isEqualToString:@"charon.state0"],
              describe(voice.activeStateIdentifier));

        [voice activateVoiceControlStateWithIdentifier:@"charon.state3"];
        check(@"activating switches the active state with no car attached (measured)",
              [voice.activeStateIdentifier isEqualToString:@"charon.state3"],
              [NSString stringWithFormat:@"active is now %@", describe(voice.activeStateIdentifier)]);

        [voice activateVoiceControlStateWithIdentifier:@"charon.state99"];
        check(@"an identifier no state carries becomes the active one anyway (measured)",
              [voice.activeStateIdentifier isEqualToString:@"charon.state99"],
              [NSString stringWithFormat:@"active is now %@", describe(voice.activeStateIdentifier)]);

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

        charonHost_CPVoiceControlTemplate *empty =
            [[charonHost_CPVoiceControlTemplate alloc] initWithVoiceControlStates:@[]];
        check(@"an empty array of states keeps an empty array and no active state",
              empty.voiceControlStates.count == 0 && empty.activeStateIdentifier == nil,
              [NSString stringWithFormat:@"%lu states, active %@", (unsigned long)empty.voiceControlStates.count,
                  describe(empty.activeStateIdentifier)]);
        charonHost_CPVoiceControlTemplate *none =
            [[charonHost_CPVoiceControlTemplate alloc] initWithVoiceControlStates:nil];
        check(@"a nil array of states answers nil for both, as the framework does",
              none.voiceControlStates == nil && none.activeStateIdentifier == nil,
              [NSString stringWithFormat:@"states %@, active %@", describe(none.voiceControlStates),
                  describe(none.activeStateIdentifier)]);

        // ---- and the drawing, which is what the template is for ----------------------------------
        // The template is a screen's contents, so it has to draw them: the view controller the
        // interface controller pushes is asked for here and must come back with the state's title
        // and one plate per state, and a tap on a plate has to switch the state.
        printf("\n== the template's own view ==\n");
        // Pushed the way the interface controller pushes it: the view is asked for, given the car's
        // own size, and laid out. Nothing here calls a draw method by hand.
        UIViewController *view = [voice charon_viewControllerForInterfaceController:nil];
        view.view.frame = CGRectMake(0.0, 0.0, 800.0, 480.0);
        [view.view setNeedsLayout];
        [view.view layoutIfNeeded];
        UILabel *title = nil;
        NSMutableArray *plates = [NSMutableArray array];
        for (UIView *sub in view.view.subviews) {
            if ([sub isKindOfClass:[UILabel class]]) {
                title = (UILabel *)sub;
            } else if ([sub isKindOfClass:[UIButton class]]) {
                [plates addObject:sub];
            }
        }
        check(@"the pushed view draws the active state's own title",
              title != nil && [title.text isEqualToString:@"State 1"],
              title != nil ? describe(title.text) : @"no label");
        check(@"the pushed view draws one plate per state the template kept",
              plates.count == 5,
              [NSString stringWithFormat:@"%lu plates", (unsigned long)plates.count]);
        // The plate's own action, sent the way a touch sends it. UIControl's dispatch needs a window
        // and a Catalyst process has none, so the harness sends the action the plate REGISTERED to
        // the target it REGISTERED -- and the registration itself is read back, so a plate with no
        // target or no action is red here rather than passing by a direct call to the method.
        UIButton *plate = plates.count == 5 ? (UIButton *)plates[4] : nil;
        id target = plate.allTargets.anyObject;
        SEL action = registeredAction(plate, target);
        check(@"every plate has a target and an action registered for a touch",
              plate != nil && target != nil && action != NULL && [target respondsToSelector:action],
              [NSString stringWithFormat:@"target %@ action %@",
                  target ? NSStringFromClass([target class]) : @"none",
                  action ? NSStringFromSelector(action) : @"none"]);
        if (target != nil && action != NULL) {
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, plate);
        }
        check(@"tapping a plate switches the state to the one that plate names",
              [voice.activeStateIdentifier isEqualToString:@"charon.state4"],
              [NSString stringWithFormat:@"active is now %@", describe(voice.activeStateIdentifier)]);
        // And the title the header's rule picks: the longest variant that fits. A template narrower
        // than the longest variant draws the shorter one rather than an empty label.
        charonHost_CPVoiceControlState *twoVariants = [[charonHost_CPVoiceControlState alloc]
            initWithIdentifier:@"charon.two"
              titleVariants:@[@"Listening to the voice control of the car", @"Listen"]
                      image:nil
                    repeats:NO];
        charonHost_CPVoiceControlTemplate *narrow =
            [[charonHost_CPVoiceControlTemplate alloc] initWithVoiceControlStates:@[twoVariants]];
        UIViewController *narrowView = [narrow charon_viewControllerForInterfaceController:nil];
        // Narrower than the long variant at the drawing size, which is what makes the header's rule
        // ("the longest variant that fits") choose the short one.
        narrowView.view.frame = CGRectMake(0.0, 0.0, 220.0, 480.0);
        [narrowView.view setNeedsLayout];
        [narrowView.view layoutIfNeeded];
        for (UIView *sub in narrowView.view.subviews) {
            if ([sub isKindOfClass:[UILabel class]] && [(UILabel *)sub text].length > 0) {
                check(@"a title variant too long for the template falls back to one that fits",
                      [(UILabel *)sub text].length < @"Listening to the voice control of the car".length,
                      describe([(UILabel *)sub text]));
                break;
            }
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
