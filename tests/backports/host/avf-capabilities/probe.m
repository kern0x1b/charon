/* capabilities.m - the capture-device capability members the port carries, the port against the host, in ONE
 * binary, in one process.
 *
 * The host HAS this API (iOS 17 and macOS 14 added the reaction surface, this macOS is 27) and this Mac has a
 * camera (measured: "MacBook Pro Camera", AVCaptureDeviceTypeBuiltInWideAngleCamera, seven formats), so every
 * row below is something the host answers. What the two sides do NOT necessarily agree on is the capability
 * itself: this camera has reaction effects and background replacement, the devices of this port's bands
 * (an iPhone 4S, an iPad 2) have neither, and the hardware is the reason in both directions. So this run does
 * two things and does not mix them:
 *
 *   RESPONDS  does each side answer the accessor the registry row names, read out of the port's own header so
 *             a row whose getter=isMultichannelAudioModeSupported would be asked under that name? Both sides
 *             must answer: the claim is that the port carries what Apple's own class carries.
 *   ANSWER    what each side answers, printed side by side. run.sh compares each against
 *             expectations.tsv, which carries BOTH columns and, where they differ, the reason. A row whose two
 *             columns differ is not a failure by itself - the hardware differs - and a row whose column
 *             disagrees with the table is.
 *
 * The two CLASS properties are read out of the APPLICATION's Info.plist, so they are checked four times over,
 * with four plists the harness writes itself and an expectation it computes from the plist it just wrote:
 * tests/backports/host/avf-capabilities/run.sh, the "four Info.plists" phase.
 *
 * Controls, so a run that examined nothing cannot pass:
 *   AVCaptureNoSuchClass              a planted name                -> ABSENT on both sides
 *   AVCaptureDevice (host)            the host's own camera         -> present
 *   charon_host_AVCaptureDevice       the port's renamed copy       -> present
 *   charon_host_AVCaptureDeviceFormat the port's renamed copy       -> present
 *   AVCaptureDeviceFormat (host)      the host's active format      -> present
 */
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PORT_PREFIX "charon_host_"

/* What each side answers, as one string. The port's side is asked of the port's own renamed class, the
   stand-in this build declares; the host's of Apple's own camera, which is a real one. */
static void answer_of(id object, SEL selector, char *out, size_t room)
{
    @autoreleasepool {
        @try {
            if (selector == @selector(availableReactionTypes)) {
                /* The eight types sorted and comma-joined: -description of an NSSet wraps over several lines,
                   which is not one field of a tab-separated row. */
                id set = ((id (*)(id, SEL))objc_msgSend)(object, selector);
                NSArray *sorted = [[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
                snprintf(out, room, "%lu type(s): %s", (unsigned long)[sorted count],
                         [sorted componentsJoinedByString:@","].UTF8String);
            } else if (selector == @selector(reactionEffectsInProgress)) {
                id array = ((id (*)(id, SEL))objc_msgSend)(object, selector);
                snprintf(out, room, "%lu running", (unsigned long)[array count]);
            } else if (selector == @selector(supportedVideoZoomRangesForDepthDataDelivery)) {
                id array = ((id (*)(id, SEL))objc_msgSend)(object, selector);
                snprintf(out, room, "%lu range(s)", (unsigned long)[array count]);
            } else if (selector == @selector(videoFrameRateRangeForReactionEffectsInProgress)) {
                id range = ((id (*)(id, SEL))objc_msgSend)(object, selector);
                snprintf(out, room, "%s", range ? "a range" : "nil");
            } else if (selector == @selector(systemPreferredCamera) || selector == @selector(userPreferredCamera)) {
                id camera = ((id (*)(id, SEL))objc_msgSend)(object, selector);
                snprintf(out, room, "%s", camera ? "a camera" : "nil");
            } else {
                snprintf(out, room, "%d", (int)((BOOL (*)(id, SEL))objc_msgSend)(object, selector));
            }
        } @catch (NSException *exception) {
            snprintf(out, room, "%s: %s", exception.name.UTF8String,
                     exception.reason ? exception.reason.UTF8String : "(no reason)");
        }
    }
}

/* A refusal: what the call raises, which is part of its answer. */
static void raise_of(id object, SEL selector, id argument, const char *label)
{
    @autoreleasepool {
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
            printf("ANSWER\t%s\treturned\n", label);
        } @catch (NSException *exception) {
            printf("ANSWER\t%s\t%s\n", label, exception.name.UTF8String);
        }
    }
}

static void class_answer_of(Class cls, SEL selector, char *out, size_t room)
{
    @autoreleasepool {
        @try {
            if (selector == @selector(systemPreferredCamera) || selector == @selector(userPreferredCamera)) {
                id camera = ((id (*)(Class, SEL))objc_msgSend)(cls, selector);
                /* named, not just "a camera": which camera answers is the whole content of these two rows. */
                snprintf(out, room, "%s", camera ? [(NSString *)[camera valueForKey:@"uniqueID"] UTF8String] : "nil");
            } else {
                snprintf(out, room, "%d", (int)((BOOL (*)(Class, SEL))objc_msgSend)(cls, selector));
            }
        } @catch (NSException *exception) {
            snprintf(out, room, "%s: %s", exception.name.UTF8String,
                     exception.reason ? exception.reason.UTF8String : "(no reason)");
        }
    }
}

static void print_class_answer(Class host, Class port, const char *label, SEL selector)
{
    char hostAnswer[512], portAnswer[512];
    class_answer_of(host, selector, hostAnswer, sizeof hostAnswer);
    class_answer_of(port, selector, portAnswer, sizeof portAnswer);
    printf("ANSWER\t%s\thost=[%s]\tport=[%s]\n", label, hostAnswer, portAnswer);
}

/* THE PREFERRED-CAMERA PAIR, and the five rules of the header that shape it
   (AVCaptureDevice.h:661-663 for the user's choice, :674 for the system's):
     persists "across app launches and reboots"; a "short history", so a camera that is not connected now still
     reports "the next best choice"; "always returns a device that is present"; nil only "if no camera is
     available"; and "Setting the property to nil has no effect".
   None of the four is a constant, so each is asked as its own step below with its own expectation, computed in
   run.sh from the step it belongs to.

   The PORT's device list is the stand-in's, not Apple's: the copy run.sh compiles renames the class name in the
   port's SOURCES as well, so the `[AVCaptureDevice devicesWithMediaType:]` and
   `[AVCaptureDevice defaultDeviceWithMediaType:]` inside the port's code reach the stand-in class and this run
   decides which cameras are present by handing it a list. The HOST's column is asked of Apple's own camera and
   carries the process's camera authorization beside it, because a nil from a process that was never granted
   access is the answer for that process and not Apple's answer for the row. */

/* Which cameras the port's class is to see. The seam belongs to this build: it is declared in the harness's own
   prologue, never in the port's sources, so nothing the library carries depends on it. */
static void set_present(Class portDevice, NSArray *devices)
{
    ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(charon_host_setPresentDevices:), devices);
}

static id make_device(Class portDevice, NSString *identifier, NSString *name, long position)
{
    id device = [portDevice new];
    ((void (*)(id, SEL, id))objc_msgSend)(device, @selector(setUniqueID:), identifier);
    ((void (*)(id, SEL, id))objc_msgSend)(device, @selector(setLocalizedName:), name);
    ((void (*)(id, SEL, long))objc_msgSend)(device, @selector(setPosition:), position);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(device, @selector(setConnected:), YES);
    return device;
}

/* The two cameras of a device of this port's bands, on each side (facts/AVFoundation/
   AVCaptureDeviceDiscovery.md, "What the hardware has", measured on an iPhone 4S and an iPad 2). */
static id prefcam_back, prefcam_front;

static void prefcam_setup(Class portDevice)
{
    /* AVCaptureDevicePositionUnspecified 0, Back 1, Front 2 - the release's own numbering (AVFoundation.h). */
    prefcam_back = make_device(portDevice, @"back-camera", @"Back Camera", 1);
    prefcam_front = make_device(portDevice, @"front-camera", @"Front Camera", 2);
    set_present(portDevice, @[prefcam_back, prefcam_front]);
}

/* What the application's own defaults hold for the history, in one string, so a run that persisted nothing
   reads "0 entries []" and not an empty string: the comparison in run.sh is a string comparison. */
static NSString *stored_history(void)
{
    id history = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"CharonCaptureUserPreferredCameraHistory"];
    NSArray *entries = [history isKindOfClass:[NSArray class]] ? history : [NSArray array];
    return [NSString stringWithFormat:@"%lu entr%s [%@]", (unsigned long)entries.count,
                                      entries.count == 1 ? "y" : "ies",
                                      entries.count ? [entries componentsJoinedByString:@","] : @""];
}

static void prefcam_step(Class portDevice, const char *label)
{
    char user[512], system[512], stored[512];
    class_answer_of(portDevice, @selector(userPreferredCamera), user, sizeof user);
    class_answer_of(portDevice, @selector(systemPreferredCamera), system, sizeof system);
    /* What the application's own defaults hold, so a run that persisted nothing shows an empty history and a
       second launch over the same bundle can be compared against the first one's. */
    snprintf(stored, sizeof stored, "%s", stored_history().UTF8String);
    printf("PREFCAM\t%s\tuser=[%s]\tsystem=[%s]\tdefaults=[%s]\n", label, user, system, stored);
}

/* ACROSS LAUNCHES. argv[2] = "persist" makes this a launch of the persistence pair instead: "set" chooses the
   front camera and leaves it, "read" chooses nothing and only reports what this process finds. The header's
   promise is "across app launches and reboots" (AVCaptureDevice.h:661), which one process's own memory cannot
   answer, so run.sh runs two of these over one bundle and a third over a bundle of its own. */
static void persist_phase(Class portDevice, const char *mode)
{
    if (!strcmp(mode, "set")) {
        /* A launch that MAKES the choice starts by forgetting any earlier one, so the pair does not inherit a
           domain an earlier run of this harness left behind: the count printed below is this launch's own. */
        [[NSUserDefaults standardUserDefaults]
            removeObjectForKey:@"CharonCaptureUserPreferredCameraHistory"];
        ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(setUserPreferredCamera:), prefcam_front);
    }
    char user[512], system[512];
    class_answer_of(portDevice, @selector(userPreferredCamera), user, sizeof user);
    class_answer_of(portDevice, @selector(systemPreferredCamera), system, sizeof system);
    id history = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"CharonCaptureUserPreferredCameraHistory"];
    NSArray *entries = [history isKindOfClass:[NSArray class]] ? history : [NSArray array];
    printf("PERSIST\t%s\t%s\tsystem=[%s]\t%lu entr%s in this bundle's own defaults\n",
           strcmp(mode, "set") ? "second-launch" : "first-launch", user, system, (unsigned long)entries.count,
           entries.count == 1 ? "y" : "ies");
}

static void prefcam_phase(Class hostDevice, Class portDevice, const char *mode)
{
    /* The host's own answer, with the authorization printed beside it - the measurement the coordinator asked
       for after a run read the host's nil as Apple's answer for the row. */
    long auth = (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    const char *authName = auth == 0 ? "notDetermined" : auth == 1 ? "restricted" : auth == 2 ? "denied" : "authorized";
    char hostSystem[512];
    class_answer_of(hostDevice, @selector(systemPreferredCamera), hostSystem, sizeof hostSystem);
    char hostUser[512];
    class_answer_of(hostDevice, @selector(userPreferredCamera), hostUser, sizeof hostUser);
    printf("PREFCAM\thost\tauth=%ld (%s)\tuser=[%s]\tsystem=[%s]\tdefault=[%s]\n", auth, authName, hostUser,
           hostSystem,
           [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] ? "a camera" : "nil");

/* Nothing was ever chosen: the measured host answer for a property that has not been set is nil, with a
       camera present. */
    prefcam_step(portDevice, "before-any-set");

    if (mode) {
        /* One launch of the persistence pair: nothing else, and no step that would clear the history. */
        persist_phase(portDevice, mode);
        return;
    }

    /* The choice, then the getter, and a second choice, so the history holds two entries. */
    ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(setUserPreferredCamera:), prefcam_front);
    prefcam_step(portDevice, "after-front-is-chosen");
    ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(setUserPreferredCamera:), prefcam_back);
    prefcam_step(portDevice, "after-back-is-chosen");

    /* "Setting the property to nil has no effect" (:663): a nil adds nothing, so the choice survives it. */
    ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(setUserPreferredCamera:), nil);
    prefcam_step(portDevice, "after-nil-is-set");

    /* "if your user's most recent preferred camera is not currently connected, it still reports the next best
       choice" (:662): the back is the most recent and it goes, so the front - the entry before it - answers. */
    set_present(portDevice, @[prefcam_front]);
    prefcam_step(portDevice, "most-recent-gone-next-best-answers");

    /* No camera at all: nil is the header's own answer for both properties (:663, :674). */
    set_present(portDevice, @[]);
    prefcam_step(portDevice, "no-camera-at-all");

    /* Only the front was ever chosen and it is gone: the history is exhausted, and the release's own best
       camera is the next best choice one step further - the back, which is what +defaultDeviceWithMediaType:
       answers over the list this run handed the stand-in. */
    set_present(portDevice, @[prefcam_back, prefcam_front]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CharonCaptureUserPreferredCameraHistory"];
    ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(setUserPreferredCamera:), prefcam_front);
    set_present(portDevice, @[prefcam_back]);
    prefcam_step(portDevice, "history-exhausted");

    /* And a launch that chooses nothing: the measured host answer for a property that has not been set is nil,
       while the system's answer is the release's own best camera. */
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CharonCaptureUserPreferredCameraHistory"];
    set_present(portDevice, @[prefcam_back, prefcam_front]);
    prefcam_step(portDevice, "nothing-ever-chosen");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "FAIL: no member list was named, so nothing was examined\n");
            return 1;
        }
        if (dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation",
                   RTLD_LAZY | RTLD_GLOBAL) == NULL) {
            fprintf(stderr, "FAIL: AVFoundation did not load\n");
            return 1;
        }
        Class hostDevice = NSClassFromString(@"AVCaptureDevice");
        Class hostFormat = NSClassFromString(@"AVCaptureDeviceFormat");
        Class portDevice = objc_getClass(PORT_PREFIX "AVCaptureDevice");
        Class portFormat = objc_getClass(PORT_PREFIX "AVCaptureDeviceFormat");
        AVCaptureDevice *camera = hostDevice ? [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] : nil;
        AVCaptureDeviceFormat *format = camera ? [camera activeFormat] : nil;
        printf("CONTROL\tAVCaptureNoSuchClass\t%s\n",
               NSClassFromString(@"AVCaptureNoSuchClass") ? "HAS" : "ABSENT");
        printf("CONTROL\tAVCaptureDevice\t%s\tcamera=%s\n", hostDevice ? "HAS" : "ABSENT",
               camera ? "one" : "NONE");
        printf("CONTROL\tAVCaptureDeviceFormat\t%s\tactive format=%s\n", hostFormat ? "HAS" : "ABSENT",
               format ? "one" : "NONE");
        printf("CONTROL\tcharon_host_AVCaptureDevice\t%s\n", portDevice ? "HAS" : "ABSENT");
        printf("CONTROL\tcharon_host_AVCaptureDeviceFormat\t%s\n", portFormat ? "HAS" : "ABSENT");
        if (hostDevice == nil || camera == nil || format == nil || portDevice == nil || portFormat == nil) {
            fprintf(stderr, "FAIL: a side of this run is missing, so every row below would be read off "
                            "nothing\n");
            return 1;
        }
        printf("CAMERA\t%s\t%lu format(s)\n", [camera.localizedName UTF8String],
               (unsigned long)camera.formats.count);
        /* The port's own objects: a stand-in class each, so the port's answers are asked of the port's code
           and not of Apple's, which is what the rename is for. */
        id portCamera = [portDevice new];
        id portFormatObject = [portFormat new];
        /* The preferred-camera pair reads a device list, so the stand-in is given one before anything is asked:
           two cameras, on each side. And the history is cleared here rather than in the phase that writes it,
           because the member loop below asks +userPreferredCamera too and must not see a previous run's choice. */
        prefcam_setup(portDevice);
        /* Not in a launch of the persistence pair: clearing the key there would erase what the launch before
           this one left, which is the only thing that launch is there to leave. */
        if (argc <= 2)
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CharonCaptureUserPreferredCameraHistory"];

        FILE *list = fopen(argv[1], "r");
        if (list == NULL) {
            fprintf(stderr, "FAIL: the list did not open, so nothing was examined\n");
            return 1;
        }
        char line[512];
        unsigned members = 0, answers = 0;
        while (fgets(line, sizeof line, list) != NULL) {
            char *save = NULL;
            char *api = strtok_r(line, "\t\n", &save);
            char *owner = strtok_r(NULL, "\t\n", &save);
            char *selector = strtok_r(NULL, "\t\n", &save);
            char *kind = strtok_r(NULL, "\t\n", &save);
            if (api == NULL || owner == NULL || selector == NULL) {
                continue;
            }
            /* Whether this is a class member comes from the list's own KIND column and not from the sign in
               the selector: a class PROPERTY is written with no sign at all, and a probe that reads the sign
               asks every class property of its class's instance side and finds nothing on either. */
            int classMember = kind != NULL && !strcmp(kind, "class");
            const char *name = (selector[0] == '+' || selector[0] == '-') ? selector + 1 : selector;
            SEL asked = sel_registerName(name);
            Class hostOwner = NSClassFromString([NSString stringWithUTF8String:owner]);
            char prefixed[512];
            snprintf(prefixed, sizeof prefixed, "%s%s", PORT_PREFIX, owner);
            Class portOwner = objc_getClass(prefixed);
            Method hostMethod = classMember ? class_getClassMethod(hostOwner, asked)
                                            : class_getInstanceMethod(hostOwner, asked);
            Method portMethod = classMember ? class_getClassMethod(portOwner, asked)
                                            : class_getInstanceMethod(portOwner, asked);
            printf("RESPONDS\t%c[%s %s]\thost=%s\tport=%s\n", classMember ? '+' : '-', owner, name,
                   hostMethod ? "yes" : "no", portMethod ? "yes" : "no");
            members++;

            char hostAnswer[512], portAnswer[512];
            if (!strcmp(kind, "class")) {
                class_answer_of(hostOwner, asked, hostAnswer, sizeof hostAnswer);
                class_answer_of(portOwner, asked, portAnswer, sizeof portAnswer);
            } else {
                /* The FORMAT rows are asked of the active format and the port's own stand-in format; the rest
                   of the device rows, of the camera and the port's stand-in device. */
                int onFormat = !strcmp(owner, "AVCaptureDeviceFormat");
                answer_of(onFormat ? (id)format : (id)camera, asked, hostAnswer, sizeof hostAnswer);
                answer_of(onFormat ? (id)portFormatObject : (id)portCamera, asked, portAnswer, sizeof portAnswer);
            }
            printf("ANSWER\t%s\thost=[%s]\tport=[%s]\n", api, hostAnswer, portAnswer);
            answers++;
        }
        fclose(list);

        /* The two members whose answer is a refusal rather than a value. */
        raise_of(portCamera, @selector(performEffectForReaction:), @"ReactionHeart", "AVCaptureDevice.performEffectForReaction:");
        raise_of(camera, @selector(performEffectForReaction:), @"ReactionHeart", "AVCaptureDevice.performEffectForReaction: host");

        /* The class properties, which the four Info.plists phase reads. Printed here too, so a run with no
           plist phase at all still shows them. */
        print_class_answer(hostDevice, portDevice, "AVCaptureDevice.reactionEffectsEnabled",
                           @selector(reactionEffectsEnabled));
        print_class_answer(hostDevice, portDevice, "AVCaptureDevice.reactionEffectGesturesEnabled",
                           @selector(reactionEffectGesturesEnabled));
        print_class_answer(hostDevice, portDevice, "AVCaptureDevice.systemPreferredCamera",
                           @selector(systemPreferredCamera));
        print_class_answer(hostDevice, portDevice, "AVCaptureDevice.userPreferredCamera",
                           @selector(userPreferredCamera));
        prefcam_phase(hostDevice, portDevice, argc > 2 ? argv[2] : NULL);

        printf("members probed: %u  answers emitted: %u\n", members, answers);
    }
    return 0;
}
