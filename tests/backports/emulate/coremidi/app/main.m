//
//  app/main.m
//  The CoreMIDI round trip as an application: the same probe as the daemon (../roundtrip.m), run from the
//  application delegate after SpringBoard has launched the process, with the audio background mode the
//  application declares in its Info.plist and an active audio session, so that a process which the release
//  treats as an audio client is the one that asks for the endpoints.
//

#import <UIKit/UIKit.h>
#include <AudioToolbox/AudioToolbox.h>

int charon_roundtrip_run(void);

@interface CharonAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CharonAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
#ifndef CHARON_NO_AUDIO_SESSION
    OSStatus session = AudioSessionInitialize(NULL, NULL, NULL, NULL);
    UInt32 category = kAudioSessionCategory_MediaPlayback;
    OSStatus category_status = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
    OSStatus active = AudioSessionSetActive(true);
    printf("audio session: initialize %d, category %d, active %d\n", (int)session, (int)category_status, (int)active);
    fflush(stdout);
#else
    printf("audio session: not activated (CHARON_NO_AUDIO_SESSION)\n");
    fflush(stdout);
#endif
    int failures = charon_roundtrip_run();
    printf("application exit: %d\n", failures);
    fflush(stdout);
    exit(failures);
    return YES;
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CharonAppDelegate class]));
    }
}
