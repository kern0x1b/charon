//
//  app/main.m
//  The CoreMIDI round trip as an application: the same probe as the daemon (../roundtrip.m), run from the
//  application delegate after SpringBoard has launched the process, with the audio background mode the
//  application declares in its Info.plist and an active audio session, so that a process which the release
//  treats as an audio client is the one that asks for the endpoints.
//

#import <UIKit/UIKit.h>
#include <AudioToolbox/AudioToolbox.h>
#import <CoreMIDI/CoreMIDI.h>
#include <dlfcn.h>
#import <objc/runtime.h>

int charon_roundtrip_run(void);

// The measurements the 6.1.3 release owes the port (facts/CoreMIDI/Bluetooth.md, CoreMIDI.md "Disposed objects"): the
// selectors of CoreBluetooth's peripheral, and a destination's UniqueID before and after its dispose. The framework is
// loaded by name, so the application's build does not link it. One line per answer; the round trip's verdict is separate.
static void charon_probe_read(const MIDIPacketList *packets, void *readRefCon, void *srcConnRefCon)
{
}

static void charon_probe_6_1_3(void)
{
    void *handle = dlopen("/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth", RTLD_NOW);
    Class peripheral = NSClassFromString(@"CBPeripheral");
    printf("probe 6.1.3: CoreBluetooth loaded %d, CBPeripheral %s\n", handle != NULL, peripheral ? "present" : "absent");
    if (peripheral) {
        printf("probe 6.1.3: CBPeripheral responds to identifier %d, to UUID %d\n",
               (int)[peripheral instancesRespondToSelector:@selector(identifier)],
               (int)[peripheral instancesRespondToSelector:@selector(UUID)]);
    }
    MIDIClientRef client = 0;
    OSStatus clientStatus = MIDIClientCreate(CFSTR("charon-probe"), NULL, NULL, &client);
    MIDIEndpointRef dest = 0;
    OSStatus created = clientStatus == noErr ? MIDIDestinationCreate(client, CFSTR("charon-probe-dest"), charon_probe_read, NULL, &dest) : clientStatus;
    SInt32 uniqueID = 0;
    OSStatus live = created == noErr ? MIDIObjectGetIntegerProperty(dest, kMIDIPropertyUniqueID, &uniqueID) : created;
    printf("probe 6.1.3: client %d, destination %d, UniqueID before dispose %d\n", (int)clientStatus, (int)created, (int)live);
    if (created == noErr) {
        MIDIEndpointDispose(dest);
        OSStatus gone = MIDIObjectGetIntegerProperty(dest, kMIDIPropertyUniqueID, &uniqueID);
        printf("probe 6.1.3: UniqueID after dispose %d\n", (int)gone);
    }
    if (clientStatus == noErr)
        MIDIClientDispose(client);
    fflush(stdout);
}

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
    charon_probe_6_1_3();
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
