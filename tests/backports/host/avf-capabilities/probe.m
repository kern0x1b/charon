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
                snprintf(out, room, "%s", camera ? "a camera" : "nil");
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
        /* and the setter, then the getter: what the port stores is what it reads back. */
        ((void (*)(Class, SEL, id))objc_msgSend)(portDevice, @selector(setUserPreferredCamera:), portCamera);
        char after[512];
        class_answer_of(portDevice, @selector(userPreferredCamera), after, sizeof after);
        printf("ANSWER\tAVCaptureDevice.userPreferredCamera after the port is set\tport=[%s]\n", after);

        printf("members probed: %u  answers emitted: %u\n", members, answers);
    }
    return 0;
}
