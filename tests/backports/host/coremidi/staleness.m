// The rows of CharonMIDIPorts.m go stale when the release no longer knows the object (a property read answers paramErr) and when
// the release has given the reference to a new object (the stamp the library wrote is not on it). A row of a live object keeps
// what it holds whatever its creator does to the object's UniqueID, which is the creator's to set (MIDIServices.h,
// kMIDIPropertyUniqueID). Each row's retained block is released when its row goes, and a row of a live object keeps its block.
//
// The host release cannot be made to reuse a reference, so this test stands in for the two release calls the rows make,
// MIDIObjectGetIntegerProperty and MIDIObjectSetIntegerProperty (run.sh renames them in CharonMIDIPorts.m and here to
// charon_test_...); nothing is linked from the release for them. The stand-in answers what the release was measured to answer
// (oracle/stamp-macos.txt, and the 6.1.3 application's lines in facts/CoreMIDI/CoreMIDI.md): a disposed or never-made reference
// answers paramErr, a live object answers -10835 for a key it does not hold and noErr with the value for one it does, and the
// owner's write of the UniqueID changes the UniqueID alone.
#import <CoreMIDI/CoreMIDI.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

#import "CharonCoreMIDI.h"

static int gLive;
static int gFailures;

// A block stand-in whose release is counted: CharonMIDIOwnBlock takes a retained reference, as MIDIBlocks9.m gives it.
@interface Token : NSObject
@end
@implementation Token
- (void)dealloc
{
    gLive--;
}
@end

#define OBJECTS 64
typedef struct {
    int exists;          // the release knows the reference
    int hasUniqueID;     // a client and a port have none (-10835)
    SInt32 uniqueID;
    int hasStamp;
    SInt32 stamp;
    OSStatus refused;    // a status that every read answers instead (the release is not answering, say)
    OSStatus setStatus;  // the status of the write of the library's stamp (noErr unless the test makes it refuse)
} StubObject;
static StubObject gObject[OBJECTS];

// The key is the library's or it is the UniqueID, the one other key the rows read or an owner sets. (The host's property name
// constants are NULL until the release is first used, which this test never does, so the UniqueID is not compared by name.)
static int is_owner_key(CFStringRef propertyID)
{
    return propertyID && CFEqual(propertyID, CHARON_OWNER_KEY);
}

OSStatus charon_test_MIDIObjectGetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 *outValue)
{
    if (object >= OBJECTS || !gObject[object].exists)
        return charon_paramErr;
    StubObject *held = &gObject[object];
    if (held->refused != noErr)
        return held->refused;
    if (is_owner_key(propertyID)) {
        if (!held->hasStamp)
            return kMIDIUnknownProperty;
        *outValue = held->stamp;
        return noErr;
    }
    if (!held->hasUniqueID)
        return kMIDIUnknownProperty;
    *outValue = held->uniqueID;
    return noErr;
}

OSStatus charon_test_MIDIObjectSetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 value)
{
    if (object >= OBJECTS || !gObject[object].exists)
        return charon_paramErr;
    StubObject *held = &gObject[object];
    if (is_owner_key(propertyID)) {
        if (held->setStatus != noErr)
            return held->setStatus;
        held->hasStamp = 1;
        held->stamp = value;
        return noErr;
    }
    held->hasUniqueID = 1;
    held->uniqueID = value;
    return noErr;
}

static void expect(int passed, const char *name)
{
    printf("%s %s\n", passed ? "ok" : "FAIL", name);
    if (!passed)
        gFailures++;
}

// Makes an object the stand-in answers for, and owns a token for it (what MIDIBlocks9.m does for a client or a port).
static void own(MIDIObjectRef object, SInt32 uniqueID)
{
    gObject[object].exists = 1;
    gObject[object].hasUniqueID = 1;
    gObject[object].uniqueID = uniqueID;
    Token *token = [[Token alloc] init];
    gLive++;
    CharonMIDIOwnBlock(object, (__bridge_retained void *)token);
}

// The same for an object that has no UniqueID (a client, a port). A helper, so that no local keeps the token alive.
static void own_without_uniqueid(MIDIObjectRef object)
{
    gObject[object].exists = 1;
    Token *token = [[Token alloc] init];
    gLive++;
    CharonMIDIOwnBlock(object, (__bridge_retained void *)token);
}

// The reference given to a new object: it answers, with a UniqueID of its own and no stamp.
static void reuse(MIDIObjectRef object, SInt32 uniqueID)
{
    memset(&gObject[object], 0, sizeof(gObject[object]));
    gObject[object].exists = 1;
    gObject[object].hasUniqueID = 1;
    gObject[object].uniqueID = uniqueID;
}

int main(void)
{
    @autoreleasepool {
        own(1, 11);
        own(2, 22);
        expect(gLive == 2, "two live objects own two tokens");
        // The creator sets the UniqueID of its own object: the documented use of the property.
        charon_test_MIDIObjectSetIntegerProperty(1, CFSTR("uniqueID"), 99);
        own(3, 33);
        expect(gLive == 3, "an object whose creator set its UniqueID is the same object: its row is kept");
        gObject[2].exists = 0;
        own(4, 44);
        expect(gLive == 3, "an object that answers paramErr is released at the next row");
        // The release gives the reference of a disposed object to a new object, which has no stamp.
        reuse(3, 77);
        own(5, 55);
        expect(gLive == 3, "a reference given to a new object (no stamp) is released, and the live ones are kept");
        // The new object is another library instance's, with a stamp of its own.
        gObject[5].stamp ^= 0x5A5A5A5A;
        own(6, 66);
        expect(gLive == 3, "a reference that answers another stamp is released");
        // A read that fails with another status is no evidence either way.
        gObject[1].refused = -10842;
        own(7, 77);
        expect(gLive == 4, "an object whose read fails with another status is kept");
        gObject[1].refused = noErr;
        // A client or a port has no UniqueID: its identity is the stamp alone.
        own_without_uniqueid(8);
        own(9, 99);
        expect(gLive == 6, "an object with no UniqueID is kept while it answers its stamp");
        gObject[8].exists = 0;
        own(10, 100);
        expect(gLive == 6, "and released when it is gone");
        // The stamp could not be written: the row is kept while the object is known and released when it is gone.
        gObject[11].setStatus = -10844;
        own(11, 111);
        own(12, 112);
        int before = gLive;
        gObject[11].exists = 0;
        own(13, 113);
        expect(gLive == before, "an object whose stamp was refused is released when it is gone");
    }
    printf("staleness: %d failures\n", gFailures);
    return gFailures ? 1 : 0;
}
