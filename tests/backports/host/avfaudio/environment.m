// AVAudioEnvironmentNode's outputType and listenerHeadTrackingEnabled.
//
// The port's rules are in packages/a/apple-backports/AVFAudio/CharonEnvironmentOutput.h, the header the port's node includes,
// so this probe checks the very mapping the node applies. Checked here:
//   - the resolution of AVAudioEnvironmentOutputTypeAuto over the four route classes, against the header's rule: a wired
//     route is headphones, the built-in hardware is built-in speakers, every other route is external speakers;
//   - an explicit type is kept on every route, whatever the route is;
//   - the host's own outputType keeps the value it is set to, for every type, which is what the port's setter does too;
//   - the port's listenerHeadTrackingEnabled answers NO for both values. The host keeps YES (measured on macOS 27), which
//     is a recorded divergence: it is printed, not counted, because the 6.1.3 device has no head pose for a YES to mean anything.
// The route itself is read from AudioSession on the device, which this host does not have, so the route's class is passed in
// here. That part is not measured by this file.
#import <AVFoundation/AVFoundation.h>
#include <stdio.h>
#include "../../../../packages/a/apple-backports/AVFAudio/CharonEnvironmentOutput.h"

static int checks = 0;
static int failures = 0;

static void check(int passed, const char *name)
{
    checks++;
    if (!passed) {
        failures++;
        printf("FAIL %s\n", name);
    }
}

int main(void)
{
    @autoreleasepool {
        check(CharonResolveEnvironmentOutputType(AVAudioEnvironmentOutputTypeAuto, CharonEnvironmentRouteClassWired)
              == AVAudioEnvironmentOutputTypeHeadphones, "auto on a wired route is headphones");
        check(CharonResolveEnvironmentOutputType(AVAudioEnvironmentOutputTypeAuto, CharonEnvironmentRouteClassBuiltIn)
              == AVAudioEnvironmentOutputTypeBuiltInSpeakers, "auto on the built-in hardware is built-in speakers");
        check(CharonResolveEnvironmentOutputType(AVAudioEnvironmentOutputTypeAuto, CharonEnvironmentRouteClassExternal)
              == AVAudioEnvironmentOutputTypeExternalSpeakers, "auto on an external route is external speakers");
        check(CharonResolveEnvironmentOutputType(AVAudioEnvironmentOutputTypeAuto, CharonEnvironmentRouteClassUnknown)
              == AVAudioEnvironmentOutputTypeExternalSpeakers, "auto on a route the port does not name is external speakers");

        for (NSInteger requested = AVAudioEnvironmentOutputTypeHeadphones; requested <= AVAudioEnvironmentOutputTypeExternalSpeakers; requested++) {
            for (int route = CharonEnvironmentRouteClassUnknown; route <= CharonEnvironmentRouteClassExternal; route++) {
                check(CharonResolveEnvironmentOutputType((AVAudioEnvironmentOutputType)requested, (CharonEnvironmentRouteClass)route) == requested,
                      "an explicit output type is kept on every route");
            }
        }

        check(CharonEnvironmentHeadTrackingAnswer(YES) == NO, "head tracking answers NO when YES is set");
        check(CharonEnvironmentHeadTrackingAnswer(NO) == NO, "head tracking answers NO when NO is set");

        AVAudioEnvironmentNode *host = [[AVAudioEnvironmentNode alloc] init];
        check(host.outputType == AVAudioEnvironmentOutputTypeAuto, "the host's outputType defaults to auto");
        for (NSInteger type = AVAudioEnvironmentOutputTypeAuto; type <= AVAudioEnvironmentOutputTypeExternalSpeakers; type++) {
            host.outputType = (AVAudioEnvironmentOutputType)type;
            check(host.outputType == type, "the host's outputType reads back the type it was set to");
        }

        host.listenerHeadTrackingEnabled = YES;
        printf("divergence: the host's listenerHeadTrackingEnabled reads %d after YES; the port answers %d\n",
               (int)host.listenerHeadTrackingEnabled, (int)CharonEnvironmentHeadTrackingAnswer(YES));

        printf("checks=environment-output failures=%d\n", failures);
        return failures == 0 ? 0 : 1;
    }
}
