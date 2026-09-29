//
//  probe.m
//  The avf-3a descriptor classes, host against port, with two plants.
//
//  One program, linked twice by run.sh. Linked plain, every name is Apple's own; linked with the
//  rename list and the port's five objects, the same names are the port's own classes in the same
//  binary.
//
//  **No class in this slice is named as a type, and that is forced.** Read out of the SDK's headers on
//  this host:
//
//      AVCaptureAutoExposureBracketedStillImageSettings  API_UNAVAILABLE(macos)
//      AVCaptureManualExposureBracketedStillImageSettings API_UNAVAILABLE(macos)
//      +[AVPlayerMediaSelectionCriteria preferredMediaSelectionCriteriaWithPreferredLanguages:
//                                     preferredMediaCharacteristics:]  API_UNAVAILABLE(macos)
//
//  So a host probe that writes the class or the factory as an expression does not COMPILE - the first
//  version of this did, and the compiler said so three times. Every class here is therefore reached
//  by name with NSClassFromString, and every member with -respondsToSelector: and a typed call, which
//  is the same shape the port's differential for the metadata objects needed, and the same reason.
//
//  What that buys, and what it costs, is stated rather than glossed:
//
//    STRUCTURE  compared against the host, class by class: does the name resolve, what is it a
//               subclass of, and does an instance answer the header's members. The host HAS these
//               classes - they are unavailable to COMPILE against, not absent - so this half is a real
//               differential.
//    VALUES     the port's answers, held against the unmutated baseline. There is no host oracle for
//               them: the host's own factory is unavailable here, and the header's value for a bracketed
//               settings object is a configuration, not a measurement. These rows are marked with a
//               leading ~ and are NOT compared to the host - the avf-metadata harness's port-only rows,
//               for the same reason and so that a mutation of them can be seen.
//
//  Two plants, and this is the check's own falsifiability: AVFDESCPROBE=plant-all corrupts every
//  row, plant-one corrupts exactly one. The all-wrong plant must go red on every row and the one-wrong
//  plant on exactly one. A harness that passes while the probe is corrupting every answer is not a
//  check.
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "CharonAVFDescriptorConstruction.h"

#include <stdio.h>

static int plants;      // 0 none, 1 all rows wrong, 2 exactly one row wrong
static int plantRow;
static int rowIndex;

// "no oracle" is the honest answer when the CLASS declares the member and the INSTANCE cannot answer
// it: the class exists in this build and the framework is the oracle, but this particular instance is
// a forwarding object, so there is nothing here to read. The row is then held against the port's own
// unmutated baseline instead of against the host, which is the port-only row the metadata harness
// uses, and which is the only way a mutation of it can still be seen.
#define NO_ORACLE @"no-oracle-forwarding-object"

static void row(const char *key, NSString *v)
{
    // The plants corrupt the value AFTER the real answer is taken, so a plant cannot crash the probe
    // and cannot hide a real difference: it makes the table differ and the harness must see it.
    rowIndex++;
    if (plants == 1) {
        v = [NSString stringWithFormat:@"WRONG-ALL-%d", rowIndex];
    } else if (plants == 2 && rowIndex == plantRow) {
        v = @"WRONG-ONE";
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    // Printing a value is inside its own @try, and a value that cannot be printed is recorded as
    // unprintable rather than allowed to take the run down. This host hands back FORWARDING OBJECTS
    // for members it declares - -respondsToSelector: says yes, the call returns an object no
    // selector understands, and asking it for a description throws - so the formatting itself is the
    // last place a run can die, and it is contained here.
    NSString *text = @"(nil)";
    @try {
        text = v ? [v description] : @"(nil)";
    } @catch (NSException *e) {
        text = NO_ORACLE;
    }
    printf("%-76s = %s\n", key, [text UTF8String] ?: "(unprintable)");
    fflush(stdout);
}

// The port build asks for the RENAMED name, so it finds the port's own class; the host build asks for
// the real one. The ROW keys stay the real name on both sides, so a row compares across the builds -
// the same arrangement the constants harness needed, and the same reason: without it the port build
// silently read APPLE's class and the port's own values were never asked for at all. That is what
// made every ~VALUES row read "no oracle" on both sides the first time.
static Class lookup(const char *name)
{
    // The port build asks for the RENAMED name, so it finds the port's own class; the host build
    // asks for the real one. The ROW keys stay the real name on both sides, so a row compares across
    // the builds. The name is CONCATENATED at run time rather than by the preprocessor: a macro that
    // expands to `"charon_host_" name` is adjacent-literal syntax with a variable in it, and that is
    // not valid in any position - the compiler pointed at all three attempts in turn.
    NSString *asked = [NSString stringWithUTF8String:name];
#ifdef CHARON_PORT_BUILD
    asked = [@"charon_host_" stringByAppendingString:asked];
#endif
    return NSClassFromString(asked);
}

// An instance of a class reached by name, or nil. The class is never named as a type.
static id instance(const char *name)
{
    Class c = lookup(name);
    if (!c) {
        return nil;
    }
    @try {
        return [[c alloc] init];
    } @catch (NSException *e) {
        return nil;
    }
}

// A BOOL for "does this CLASS answer a CLASS method". A class method lives on the METACLASS, so
// class_respondsToSelector(class, sel) - which asks the instance table - says no to every factory.
// That is why the bracket and criteria value rows read "no oracle" on the port while the selection
// rows, which go through -init, read real values: the bug was the gate, not the classes.
static BOOL classMethodAnswers(Class c, SEL sel)
{
    if (!c) {
        return NO;
    }
    return [c respondsToSelector:sel];
}

// A BOOL for "does this INSTANCE answer", and nothing else: no class-level fallback, because the
// class answering yes is not licence to call. This host's AVAssetResourceRenewalRequest hands back a
// forwarding object from -init, and calling a member on one throws; asking the class instead says yes
// for a member the instance still cannot handle, which is how the last version of this died.
static BOOL answersSelector(id made, SEL sel)
{
    if (!made) {
        return NO;
    }
    @try {
        return [made respondsToSelector:sel];
    } @catch (NSException *e) {
        return NO;
    }
}

static NSString *answersValue(id made, SEL sel, BOOL classDeclares)
{
    if (answersSelector(made, sel)) {
        return @"yes";
    }
    if (classDeclares) {
        return NO_ORACLE;
    }
    return @"no";
}

static void structure(const char *name, const char *const *members, unsigned count)
{
    Class c = lookup(name);
    // The KEY names the class. Seven classes writing PRESENT/SUPERCLASS/RESPONDS into one table put
    // the last class's answers under the first class's key, and the join then reported differences
    // that were two different classes colliding - `RESPONDS selectedMediaOptions host=[no] port=[yes]`
    // was AVMediaSelection saying no and AVMutableMediaSelection saying yes. And the superclass NAME
    // is printed with this build's rename prefix taken off, so a row compares on which class it is
    // and not on what this build called it.
    NSString *label = [NSString stringWithUTF8String:name];
    row([[label stringByAppendingString:@" PRESENT"] UTF8String], c ? @"yes" : @"NO");
    NSString *superName = c ? [NSString stringWithUTF8String:class_getName(class_getSuperclass(c))] : @"(no class)";
    row([[label stringByAppendingString:@" SUPERCLASS"] UTF8String],
        [superName stringByReplacingOccurrencesOfString:@"charon_host_" withString:@""]);
    id made = instance(name);
    row([[label stringByAppendingString:@" ALLOC-INIT"] UTF8String], made ? @"yes" : @"no");
    for (unsigned i = 0; i < count; i++) {
        SEL sel = sel_registerName(members[i]);
        row([[NSString stringWithFormat:@"%@ RESPONDS %s", label, members[i]] UTF8String],
            answersValue(made, sel, c ? class_respondsToSelector(c, sel) : NO));
    }
}

int main(void)
{
    @autoreleasepool {
        const char *plant = getenv("AVFDESCPROBE");
        plants = plant && strcmp(plant, "plant-one") == 0 ? 2
              : (plant && strcmp(plant, "plant-all") == 0 ? 1 : 0);
        const char *which = getenv("AVFDESCPROW");
        plantRow = which ? atoi(which) : 1;

        // ---- the selection criteria, and the 12.0 initializer the category beside the class object
        // carries. Responds and then called, on whichever instance is in the binary: the class object
        // warns that the definition is in the category, so the shape has to be PROVED to work, not
        // argued for.
        {
            static const char *members[] = {"preferredLanguages", "preferredMediaCharacteristics",
                                            "principalMediaCharacteristics",
                                            "initWithPrincipalMediaCharacteristics:preferredLanguages:preferredMediaCharacteristics:"};
            structure("AVPlayerMediaSelectionCriteria", members, 4);
            id criteria = instance("AVPlayerMediaSelectionCriteria");
            SEL principal = NSSelectorFromString(@"initWithPrincipalMediaCharacteristics:preferredLanguages:preferredMediaCharacteristics:");
            row("12.0-INITIALIZER responds (instance)",
                answersSelector(criteria, principal) ? @"yes" : @"no");
            if (answersSelector(criteria, principal)) {
                id made = ((id (*)(id, SEL, id, id, id))objc_msgSend)(criteria, principal,
                                                                          (@[@"public.video"]),
                                                                          (@[@"en"]),
                                                                          (@[@"public.audio"]));
                SEL out = NSSelectorFromString(@"principalMediaCharacteristics");
                id value = answersSelector(made, out)
                    ? ((id (*)(id, SEL))objc_msgSend)(made, out) : nil;
                row("~VALUES 12.0 initializer answers principalMediaCharacteristics", value);
                SEL languages = NSSelectorFromString(@"preferredLanguages");
                row("~VALUES 12.0 initializer kept the preferred languages",
                    answersSelector(made, languages) ? ((id (*)(id, SEL))objc_msgSend)(made, languages) : nil);
            } else {
                row("~VALUES 12.0 initializer answers principalMediaCharacteristics", @"(not answered)");
                row("~VALUES 12.0 initializer CALL on this build", NO_ORACLE);
            }
            // The three arrays, built through the 7.0 factory the class itself carries, and read back
            // through the members - also ~, because the host's own factory is unavailable here.
            Class criteriaClass = lookup("AVPlayerMediaSelectionCriteria");
            SEL factory = NSSelectorFromString(@"preferredMediaSelectionCriteriaWithPreferredLanguages:preferredMediaCharacteristics:");
            if (criteriaClass && classMethodAnswers(criteriaClass, factory)) {
                id made = ((id (*)(id, SEL, id, id))objc_msgSend)(criteriaClass, factory,
                                                                    (@[@"en"]), (@[@"public.audio"]));
                for (unsigned i = 0; i < 2; i++) {
                    SEL out = sel_registerName(i == 0 ? "preferredLanguages" : "preferredMediaCharacteristics");
                    row([[NSString stringWithFormat:@"~VALUES criteria %s after the factory",
                          sel_getName(out)] UTF8String],
                        answersSelector(made, out)
                            ? ((id (*)(id, SEL))objc_msgSend)(made, out) : nil);
                }
            } else {
                row("~VALUES criteria preferredLanguages after the factory", NO_ORACLE);
                row("~VALUES criteria preferredMediaCharacteristics after the factory", NO_ORACLE);
            }
        }

        // ---- the bracket settings, and the three numbers the port STORES. The factories are the
        // header's own; the values are read back through the members. There is no host oracle for the
        // values - the host's factories are unavailable here and the header's value for a bracketed
        // settings object is a configuration, not a measurement - so these rows are ~ and are held
        // against the port's own unmutated baseline. They are here so that a mutation of what the
        // port STORES has a row to move, which is the row the first mutant had not.
        {
            static const char *members[] = {"exposureTargetBias",
                                            "autoExposureSettingsWithExposureTargetBias:"};
            structure("AVCaptureBracketedStillImageSettings", members, 0);
            structure("AVCaptureAutoExposureBracketedStillImageSettings", members, 2);
            static const char *manual[] = {"ISO", "exposureDuration",
                                           "manualExposureSettingsWithExposureDuration:ISO:"};
            structure("AVCaptureManualExposureBracketedStillImageSettings", manual, 3);

            Class autoClass = lookup("AVCaptureAutoExposureBracketedStillImageSettings");
            SEL autoFactory = NSSelectorFromString(@"autoExposureSettingsWithExposureTargetBias:");
            if (autoClass && classMethodAnswers(autoClass, autoFactory)) {
                id made = ((id (*)(id, SEL, float))objc_msgSend)(autoClass, autoFactory, 1.5f);
                SEL bias = NSSelectorFromString(@"exposureTargetBias");
                row("~VALUES auto-exposure bias after the factory",
                    answersSelector(made, bias)
                        ? [NSString stringWithFormat:@"%g", (double)((float (*)(id, SEL))objc_msgSend)(made, bias)]
                        : NO_ORACLE);
            } else {
                row("~VALUES auto-exposure bias after the factory", NO_ORACLE);
            }
            Class manualClass = lookup("AVCaptureManualExposureBracketedStillImageSettings");
            SEL manualFactory = NSSelectorFromString(@"manualExposureSettingsWithExposureDuration:ISO:");
            if (manualClass && classMethodAnswers(manualClass, manualFactory)) {
                id made = ((id (*)(id, SEL, CMTime, float))objc_msgSend)(manualClass, manualFactory,
                                                                          kCMTimeZero, 400.0f);
                SEL iso = NSSelectorFromString(@"ISO");
                row("~VALUES manual-exposure ISO after the factory",
                    answersSelector(made, iso)
                        ? [NSString stringWithFormat:@"%g", (double)((float (*)(id, SEL))objc_msgSend)(made, iso)]
                        : NO_ORACLE);
                SEL duration = NSSelectorFromString(@"exposureDuration");
                if (answersSelector(made, duration)) {
                    CMTime t = ((CMTime (*)(id, SEL))objc_msgSend)(made, duration);
                    row("~VALUES manual-exposure duration after the factory",
                        [NSString stringWithFormat:@"%lld/%lld", (long long)t.value, (long long)t.timescale]);
                } else {
                    row("~VALUES manual-exposure duration after the factory", NO_ORACLE);
                }
            } else {
                row("~VALUES manual-exposure ISO after the factory", NO_ORACLE);
                row("~VALUES manual-exposure duration after the factory", NO_ORACLE);
            }
        }

        // ---- the renewal request: no own member, so what is asked is that it exists, what it is a
        // subclass of, and that an instance answers the superclass's members.
        {
            static const char *members[] = {"contentInformationRequest", "finishLoading",
                                            "loadingRequest", "asset"};
            structure("AVAssetResourceRenewalRequest", members, 4);
        }

        // ---- the media selection pair.
        {
            static const char *members[] = {"asset", "mediaSelectionGroups", "selectedMediaOptions",
                                            "selectedMediaOptionInMediaSelectionGroup:"};
            structure("AVMediaSelection", members, 4);
            static const char *mutableMembers[] = {"selectMediaOption:inMediaSelectionGroup:"};
            structure("AVMutableMediaSelection", mutableMembers, 1);
            // What the port STORES, read back through -selectedMediaOptions and -mediaSelectionGroups.
            // The renewal request stores nothing of its own - the host declares no member on it and
            // its state is its superclass's - so there is no value row for it and that is the fact.
            id made = [[lookup("AVMediaSelection") alloc] init];
            for (unsigned i = 0; i < 2; i++) {
                SEL out = sel_registerName(i == 0 ? "selectedMediaOptions" : "mediaSelectionGroups");
                row([[NSString stringWithFormat:@"~VALUES selection %s after -init",
                      sel_getName(out)] UTF8String],
                    answersSelector(made, out)
                        ? [NSString stringWithFormat:@"%lu",
                           (unsigned long)[((id (*)(id, SEL))objc_msgSend)(made, out) count]]
                        : NO_ORACLE);
            }
        }
        printf("rows: %d plants: %d\n", rowIndex, plants);
    }
    return 0;
}
