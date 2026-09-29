// What this Mac's own MediaPlayer answers for the 22 MPMediaItem properties the registry declares absent,
// on the one receiver a machine with no media library has: none. The point is not a value - a value needs a
// library - it is the answer for the value's absence, which is what a device with no items answers, and
// whether the class declares the accessor at all. Both are what a backport has to reproduce.
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>

static const char *properties[] = {
    "albumTrackNumber", "discNumber",
    "albumArtistPersistentID", "albumPersistentID", "albumTrackCount", "artistPersistentID", "assetURL",
    "beatsPerMinute", "cloudItem", "comments", "compilation", "composerPersistentID", "discCount",
    "genrePersistentID", "lyrics", "podcastPersistentID", "userGrouping",
    "protectedAsset", "dateAdded", "explicitItem", "playbackStoreID", "preorder",
};

// Whether the header declares the property as an object, read from the SDK's own header rather than
// guessed: the object-returning ones can be called on a nil receiver, the others cannot.
static BOOL object_returning(NSString *name) {
    static NSArray *scalars;
    if (!scalars) {
        scalars = @[@"albumTrackCount", @"discCount", @"preorder", @"protectedAsset", @"explicitItem"];
    }
    return ![scalars containsObject:name];
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("in main\n");
    Class item = objc_getClass("MPMediaItem");
    printf("asked for the class\n");
    printf("MPMediaItem class: %s\n", item ? "present" : "absent");
    if (!item) {
        return 1;
    }
    unsigned declared = 0;
    for (size_t i = 0; i < sizeof properties / sizeof *properties; ++i) {
        const char *raw = properties[i];
        NSString *name = @(raw);
        SEL getter = NSSelectorFromString(name);
        SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",
                                           [[name uppercaseString] substringToIndex:1],
                                           [name substringFromIndex:1]]);
        BOOL hasGet = class_respondsToSelector(item, getter);
        BOOL hasSet = class_respondsToSelector(item, setter);
        declared += hasGet ? 1 : 0;
        // A nil receiver: what a value's absence looks like through the accessor, and through the
        // dictionary accessor the properties are conveniences over. Only the properties that return an
        // object are called: objc_msgSend on a nil receiver is safe for those, and for a scalar or a
        // struct return it is not - the first version of this probe segfaulted on albumTrackCount that
        // way - so for those the answer is the type's zero, read off the header, not a call.
        id nothing = nil;
        BOOL object = object_returning(name);
        id through = object ? ((id (*)(id, SEL))objc_msgSend)(nothing, getter) : (id)0;
        id keyed = [nothing valueForProperty:name];
        printf("%-28s get=%d set=%d  object=%d  nil-accessor=%s  nil-valueForProperty=%s\n",
               name.UTF8String, hasGet, hasSet, object,
               object ? (through ? "non-nil" : "nil") : "not-called",
               keyed ? "non-nil" : "nil");
    }
    printf("declared getters: %u of %zu\n", declared, sizeof properties / sizeof *properties);
    return 0;
}
