// What this Mac's own MediaPlayer answers for the MPMediaItem properties the registry declares absent.
//
// The iOS SDK header is the authority for what exists and what a property is called: five of these are
// declared with a `getter=` attribute, so the property name is not a selector on any platform and a probe
// that asks for it learns nothing. The header is therefore parsed here, and the getter name written in it
// is the name asked for - the property name only when there is no getter=, which is what clang then
// synthesises. The macOS framework is the oracle for the behaviour of what it also has, and for nothing
// else: what it lacks is not what iOS declares.
//
// A value needs a media library and this process has none, so what is asked is the two questions a value
// cannot answer: does the class declare the getter, and what does the getter answer when there is no
// value. Two controls travel with every run - a getter the host is known to have, and a name no framework
// has - so a run that found nothing could be read as a run that found nothing.
//
//     xcrun clang -fobjc-arc -framework Foundation -framework MediaPlayer -o /tmp/mpitem-probe probe.m
//     /tmp/mpitem-probe /path/to/iPhoneOS26.2.sdk/.../MediaPlayer.framework/Headers/MPMediaItem.h
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

// The 22 the registry lists absent, and the properties the header also declares that are not among them,
// used as the positive control.
static NSArray *const wanted = @[
    @"albumTrackNumber", @"discNumber", @"albumArtistPersistentID", @"albumPersistentID", @"albumTrackCount",
    @"artistPersistentID", @"assetURL", @"beatsPerMinute", @"cloudItem", @"comments", @"compilation",
    @"composerPersistentID", @"discCount", @"genrePersistentID", @"lyrics", @"podcastPersistentID",
    @"userGrouping", @"protectedAsset", @"dateAdded", @"explicitItem", @"playbackStoreID", @"preorder",
];
static NSString *const positiveControl = @"albumTitle";
static NSString *const negativeControl = @"aGetterNoFrameworkHas";

// One @property line of the header, as the name, the getter and the declared type. Read by tokens and
// not by a pattern: the line is a compiler's output, and a regex over it is a guess about whitespace.
static NSDictionary *parse_property(NSString *line) {
    if ([line rangeOfString:@"@property"].location == NSNotFound) {
        return nil;
    }
    NSArray *tokens = [[line componentsSeparatedByString:@" "] filteredArrayUsingPredicate:
                       [NSPredicate predicateWithBlock:^BOOL(NSString *t, id _) { return t.length > 0; }]];
    // The availability attribute is one token, MP_API(ios(8.0)), so it is found by its prefix and not
    // by equality - which is why the first version of this asked the host about nothing at all.
    NSUInteger at = [tokens indexOfObjectPassingTest:^BOOL(NSString *t, NSUInteger i, BOOL *stop) {
        return [t hasPrefix:@"MP_API"];
    }];
    if (at == NSNotFound || at == 0) {
        return nil;
    }
    NSString *name = tokens[at - 1];
    NSString *getter = name;
    NSUInteger g = [tokens indexOfObject:@"getter"];
    if (g != NSNotFound && g + 2 < tokens.count) {
        getter = [tokens[g + 2] stringByReplacingOccurrencesOfString:@"," withString:@""];
        if (getter.length == 0) {
            getter = [tokens[g + 2] componentsSeparatedByString:@"="].lastObject;
        }
    }
    // The declared type: every token between @property and the name, with the attributes dropped.
    NSMutableArray *type = [NSMutableArray array];
    for (NSUInteger i = 1; i + 1 < at; ++i) {
        NSString *token = [tokens[i] stringByReplacingOccurrencesOfString:@"," withString:@""];
        if ([token isEqualToString:@"nonatomic"] || [token isEqualToString:@"readonly"]
            || [token isEqualToString:@"readwrite"] || [token isEqualToString:@"getter"]
            || [token isEqualToString:@"="] || token.length == 0) {
            continue;
        }
        [type addObject:token];
    }
    return @{@"property": name, @"getter": getter, @"type": [type componentsJoinedByString:@" "]};
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) {
        fprintf(stderr, "usage: probe MPMediaItem.h\n");
        return 2;
    }
    NSString *header = [NSString stringWithUTF8String:argv[1]];
    NSString *text = [NSString stringWithContentsOfFile:header encoding:NSUTF8StringEncoding error:NULL];
    if (!text) {
        fprintf(stderr, "cannot read %s\n", header.UTF8String);
        return 2;
    }
    Class item = objc_getClass("MPMediaItem");
    printf("MPMediaItem on this host: %s\n", item ? "present" : "absent");
    printf("header: %s\n", header.lastPathComponent.UTF8String);
    printf("\n%-28s %-22s %-28s %s\n", "property", "getter", "type", "host answers");
    printf("%s\n", [@"" stringByPaddingToLength:96 withString:@"-" startingAtIndex:0].UTF8String);
    unsigned found = 0, asked = 0;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSDictionary *property = parse_property(line);
        if (!property || ![wanted containsObject:property[@"property"]]) {
            continue;
        }
        NSString *name = (NSString *)property[@"property"];
        NSString *getter = (NSString *)property[@"getter"];
        NSString *type = (NSString *)property[@"type"];
        BOOL answers = item != nil && class_getInstanceMethod(item, NSSelectorFromString(getter)) != NULL;
        asked++;
        found += answers ? 1 : 0;
        printf("%-28s %-22s %-28s %s\n", name.UTF8String, getter.UTF8String,
               type.UTF8String, answers ? "declares the getter" : "NO SUCH GETTER");
    }
    printf("\nasked %u, the host declares %u\n", asked, found);
    printf("control, positive %-24s %s\n", positiveControl.UTF8String,
           item && class_getInstanceMethod(item, NSSelectorFromString(positiveControl)) ? "declared" : "MISSING");
    printf("control, negative %-24s %s\n", negativeControl.UTF8String,
           item && class_getInstanceMethod(item, NSSelectorFromString(negativeControl)) ? "FOUND, which cannot be" : "absent, as it must be");
    return 0;
}
