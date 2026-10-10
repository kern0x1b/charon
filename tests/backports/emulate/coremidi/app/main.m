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

// The measurements the 6.1.3 release owes the port (facts/CoreMIDI/Bluetooth.md, CoreMIDI.md "Disposed objects", UMPClasses.md).
// Every line names what it reads: a "status" is an OSStatus the release returned, a "value" is what the read wrote, and the
// value is meaningful only with a noErr status. The frameworks are loaded by name, so the build links nothing new. These are
// built with CHARCOREMIDI_PROBE=1 (a separate run: the round trip's own run must end within the emulator's time budget).
#ifdef CHARON_6_1_3_PROBE
static void charon_probe_read(const MIDIPacketList *packets, void *readRefCon, void *srcConnRefCon)
{
}

static void charon_probe_notify(const MIDINotification *message, void *refCon)
{
    if (message->messageID != kMIDIMsgObjectRemoved)
        return;
    const MIDIObjectAddRemoveNotification *note = (const MIDIObjectAddRemoveNotification *)message;
    printf("probe 6.1.3: removal notification: childType %d, child ref %u\n", (int)note->childType, (unsigned)note->child);
    fflush(stdout);
}

static void charon_probe_unique(const char *label, MIDIObjectRef object)
{
    SInt32 value = -1;
    OSStatus status = MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &value);
    printf("probe 6.1.3: %s, ref %u: UniqueID read status %d, value %d\n", label, (unsigned)object, (int)status, (int)value);
    fflush(stdout);
}

static void charon_probe_umpkey(const char *label, MIDIObjectRef object, CFStringRef key)
{
    SInt32 value = -1;
    OSStatus status = MIDIObjectGetIntegerProperty(object, key, &value);
    printf("probe 6.1.3: %s: status %d, value %d\n", label, (int)status, (int)value);
    fflush(stdout);
}

static void charon_probe_selectors(void)
{
    void *handle = dlopen("/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth", RTLD_NOW);
    Class peripheral = NSClassFromString(@"CBPeripheral");
    printf("probe 6.1.3: CoreBluetooth loaded %d, CBPeripheral %s\n", handle != NULL, peripheral ? "present" : "absent");
    if (peripheral) {
        printf("probe 6.1.3: CBPeripheral responds to identifier %d, to UUID %d\n",
               (int)[peripheral instancesRespondToSelector:@selector(identifier)],
               (int)[peripheral instancesRespondToSelector:@selector(UUID)]);
    }
    fflush(stdout);
}

static void charon_probe_objects(void)
{
    MIDIClientRef client = 0;
    OSStatus clientStatus = MIDIClientCreate(CFSTR("charon-probe"), NULL, NULL, &client);
    printf("probe 6.1.3: client create status %d\n", (int)clientStatus);
    fflush(stdout);
    if (clientStatus != noErr)
        return;
    charon_probe_unique("client live", client);

    MIDIEndpointRef dest = 0;
    OSStatus created = MIDIDestinationCreate(client, CFSTR("charon-probe-dest"), charon_probe_read, NULL, &dest);
    printf("probe 6.1.3: destination create status %d\n", (int)created);
    fflush(stdout);
    if (created == noErr) {
        charon_probe_unique("destination live", dest);
        charon_probe_umpkey("destination UMP key 'active group bitmap'", dest, CFSTR("active group bitmap"));
        charon_probe_umpkey("destination UMP key 'ump endpoint'", dest, CFSTR("ump endpoint"));
        charon_probe_umpkey("destination UMP key 'associated endpoint'", dest, CFSTR("associated endpoint"));
        MIDIEndpointDispose(dest);
        charon_probe_unique("destination disposed", dest);
    }

    MIDIEndpointRef src = 0;
    OSStatus srcStatus = MIDISourceCreate(client, CFSTR("charon-probe-src"), &src);
    printf("probe 6.1.3: source create status %d\n", (int)srcStatus);
    fflush(stdout);
    if (srcStatus == noErr) {
        charon_probe_unique("source live", src);
        MIDIEndpointDispose(src);
        charon_probe_unique("source disposed", src);
    }

    MIDIPortRef port = 0;
    OSStatus portStatus = MIDIInputPortCreate(client, CFSTR("charon-probe-in"), charon_probe_read, NULL, &port);
    printf("probe 6.1.3: input port create status %d\n", (int)portStatus);
    fflush(stdout);
    if (portStatus == noErr) {
        charon_probe_unique("input port live", port);
        MIDIPortDispose(port);
        charon_probe_unique("input port disposed", port);
    }

    // The entity written by MIDIDeviceNewEntity (the library's, MIDIDevice14.m) on a device of the emulated setup, if the setup
    // has one: the status of the call, the protocol read back from the entity, and the status of its removal. An application
    // cannot make a device (MIDIDeviceCreate is the plug-in driver's call), so the setup's own device is the only one there is.
    ItemCount devices = MIDIGetNumberOfDevices();
    printf("probe 6.1.3: setup devices %lu\n", (unsigned long)devices);
    fflush(stdout);
    if (devices > 0) {
        MIDIDeviceRef device = MIDIGetDevice(0);
        MIDIEntityRef entity = 0;
        OSStatus entityStatus = MIDIDeviceNewEntity(device, CFSTR("charon-probe-entity"), kMIDIProtocol_2_0, false, 0, 0, &entity);
        printf("probe 6.1.3: MIDIDeviceNewEntity (protocol 2.0) status %d, entity ref %u\n", (int)entityStatus, (unsigned)entity);
        fflush(stdout);
        if (entityStatus == noErr) {
            charon_probe_umpkey("entity protocol read back", entity, CFSTR("protocol"));
            OSStatus removed = MIDIDeviceRemoveEntity(device, entity);
            printf("probe 6.1.3: MIDIDeviceRemoveEntity status %d\n", (int)removed);
            fflush(stdout);
        }
    }
    MIDIClientDispose(client);
    charon_probe_unique("client disposed", client);

    // The reference reuse after a dispose: a new destination's ref against the disposed one's.
    MIDIClientRef notifying = 0;
    if (MIDIClientCreate(CFSTR("charon-probe-notify"), charon_probe_notify, NULL, &notifying) == noErr) {
        MIDIEndpointRef first = 0, second = 0;
        MIDIDestinationCreate(notifying, CFSTR("charon-probe-first"), charon_probe_read, NULL, &first);
        MIDIEndpointDispose(first);
        MIDIDestinationCreate(notifying, CFSTR("charon-probe-second"), charon_probe_read, NULL, &second);
        printf("probe 6.1.3: destination ref after a dispose: first %u, second %u\n", (unsigned)first, (unsigned)second);
        fflush(stdout);
        MIDIEndpointDispose(second);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
        MIDIClientDispose(notifying);
    }
}

#endif

// The armv7 wraps: word counts whose byte sizes wrap the 32-bit size_t. The library must refuse them; before its fix, the
// send copies or reads far beyond the buffer and the application dies on a signal (the run then fails).
// MIDISendEventList: one packet of 536870913 words, 8 * count + 26 wraps to 34 bytes, so the capacity is small and the
// conversion reads the words past the 64-byte list.
static void charon_probe_wrap_send(void)
{
    Byte buffer[64];
    MIDIEventList *list = (MIDIEventList *)buffer;
    list->protocol = kMIDIProtocol_2_0;
    list->numPackets = 1;
    list->packet[0].timeStamp = 0;
    list->packet[0].wordCount = 536870913;
    printf("probe 6.1.3 wrap: MIDISendEventList, one packet of wordCount 536870913, list of 64 bytes\n");
    fflush(stdout);
    OSStatus status = MIDISendEventList(0, 0, list);
    printf("probe 6.1.3 wrap: MIDISendEventList status %d\n", (int)status);
    fflush(stdout);
}

// MIDIEventListAdd: end (8) + the packet header and the words (12 + 4 * 1073741819) is 2^32, which wraps to 0, so the room
// check passes and a 4 GB copy follows into a 64-byte list.
static void charon_probe_wrap_add(void)
{
    Byte buffer[64];
    MIDIEventList *list = (MIDIEventList *)buffer;
    list->protocol = kMIDIProtocol_2_0;
    list->numPackets = 0;
    UInt32 word = 0;
    printf("probe 6.1.3 wrap: MIDIEventListAdd, wordCount 1073741819, into 64 bytes\n");
    fflush(stdout);
    MIDIEventPacket *next = MIDIEventListAdd(list, sizeof(buffer), &list->packet[0], 0, 1073741819, &word);
    printf("probe 6.1.3 wrap: MIDIEventListAdd %s, numPackets %u\n", next ? "accepted" : "refused", (unsigned)list->numPackets);
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
#ifdef CHARON_6_1_3_PROBE
    charon_probe_selectors();
#endif
    charon_probe_wrap_send();
    charon_probe_wrap_add();
#ifdef CHARON_6_1_3_PROBE
    charon_probe_objects();
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
