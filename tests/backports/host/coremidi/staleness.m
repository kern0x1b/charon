// The rows of CharonMIDIPorts.m go stale when the object is gone (a UniqueID read answers paramErr) and when the release has
// given the reference to a new object (the read answers another UniqueID): each row's retained block is released at the next
// CharonMIDIOwnBlock, and a row of a live object keeps its block. The host release cannot be made to reuse a reference, so this
// test stands in for the one release call the rows read, MIDIObjectGetIntegerProperty (run.sh renames the call in
// CharonMIDIPorts.m and here to charon_test_MIDIObjectGetIntegerProperty); nothing is linked from the release for it.
// What a reused reference answers is the UniqueID of the new object, which the release gives every object it makes.
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

#define OBJECTS 8
static OSStatus gStatus[OBJECTS];
static SInt32 gUniqueID[OBJECTS];

OSStatus charon_test_MIDIObjectGetIntegerProperty(MIDIObjectRef object, CFStringRef propertyID, SInt32 *outValue)
{
    if (object >= OBJECTS)
        return charon_paramErr;
    if (gStatus[object] == noErr)
        *outValue = gUniqueID[object];
    return gStatus[object];
}

static void expect(int passed, const char *name)
{
    printf("%s %s\n", passed ? "ok" : "FAIL", name);
    if (!passed)
        gFailures++;
}

// Makes an object the stand-in answers for, and owns a token for it.
static void own(MIDIObjectRef object, SInt32 uniqueID)
{
    gStatus[object] = noErr;
    gUniqueID[object] = uniqueID;
    Token *token = [[Token alloc] init];
    gLive++;
    CharonMIDIOwnBlock(object, (__bridge_retained void *)token);
}

int main(void)
{
    @autoreleasepool {
        own(1, 11);
        own(2, 22);
        expect(gLive == 2, "two live objects own two tokens");
        gUniqueID[1] = 99;
        own(3, 33);
        expect(gLive == 2, "the reference that answers another UniqueID is released at the next row, and the live one is kept");
        gStatus[2] = charon_paramErr;
        own(4, 44);
        expect(gLive == 2, "the object that answers paramErr is released at the next row");
        own(5, 55);
        expect(gLive == 3, "a row of a live object is kept when the next one is made");
        gStatus[3] = -10835;
        own(6, 66);
        expect(gLive == 3, "a UniqueID read that fails with another status is stale for a row that had one");
        // an object that had no UniqueID when it was owned (-10835) stays live while it answers -10835
        gStatus[7] = -10835;
        Token *none = [[Token alloc] init];
        gLive++;
        CharonMIDIOwnBlock(7, (__bridge_retained void *)none);
        int before = gLive;
        own(1, 12);
        expect(gLive == before + 1, "a row that never had a UniqueID is kept while the read answers -10835");
    }
    printf("staleness: %d failures\n", gFailures);
    return gFailures ? 1 : 0;
}
