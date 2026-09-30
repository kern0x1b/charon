// The cases CGImageMetadata has to answer, compiled twice: once against the HOST's own ImageIO and once
// against the port's object, so the two sets of answers are compared by run.sh line by line.
//
// Records are one per line, `name <TAB> answer`, in the same order in both builds, so a diff of the two
// outputs is the differential. A record whose name starts with PORTONLY is the port's own guard (an object
// that is not this library's, and which the host's own function has no defined answer for); run.sh drops
// them from both sides before it compares and asserts that the port printed them and the host did not.
//
// Values are printed by charon_show(), never by CFCopyDescription: a description carries the object's
// address, so it would differ between the two builds on every line and the comparison would read as noise.

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <dlfcn.h>

static void record(NSString *name, NSString *answer)
{
    printf("%s\t%s\n", name.UTF8String, answer.UTF8String);
}

// a tag prints as its own accessors in both builds, so the two sides are compared on namespace, prefix,
// name, type and value and not on which library's container holds them: the host's tag is a private CF
// object and the port's is a dictionary, and printing either as "obj(...)" would read as a difference
// where there is none. The test for the port's tag is its marker; the test for the host's is the type id
// the host hands out, which is not a dictionary's.
static BOOL isTag(id value)
{
    if (!value)
        return NO;
    CFTypeRef ref = (__bridge CFTypeRef)value;
    if ([value isKindOfClass:[NSDictionary class]] && [(NSDictionary *)value objectForKey:@"charon.tag"])
        return YES;
    return CFGetTypeID(ref) == CGImageMetadataTagGetTypeID() && CFGetTypeID(ref) != CFDictionaryGetTypeID();
}

static NSString *show(id value)
{
    if (!value)
        return @"(nil)";
    if (isTag(value)) {
        CGImageMetadataTagRef tag = (__bridge CGImageMetadataTagRef)value;
        NSString *ns = (__bridge_transfer NSString *)CGImageMetadataTagCopyNamespace(tag);
        NSString *prefix = (__bridge_transfer NSString *)CGImageMetadataTagCopyPrefix(tag);
        NSString *name = (__bridge_transfer NSString *)CGImageMetadataTagCopyName(tag);
        id inner = (__bridge_transfer id)CGImageMetadataTagCopyValue(tag);
        return [NSString stringWithFormat:@"tag{ns=%@ prefix=%@ name=%@ type=%ld value=%@}", ns, prefix, name,
                                          (long)CGImageMetadataTagGetType(tag), show(inner)];
    }
    if ([value isKindOfClass:[NSString class]])
        return [NSString stringWithFormat:@"str(%@)", value];
    if ([value isKindOfClass:[NSNumber class]])
        return [NSString stringWithFormat:@"num(%g)", [(NSNumber *)value doubleValue]];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableString *out = [NSMutableString stringWithString:@"arr["];
        for (id element in (NSArray *)value)
            [out appendFormat:@"%@,", show(element)];
        [out appendString:@"]"];
        return out;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[(NSDictionary *)value allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableString *out = [NSMutableString stringWithString:@"dict{"];
        for (id key in keys)
            [out appendFormat:@"%@=%@,", key, show([(NSDictionary *)value objectForKey:key])];
        [out appendString:@"}"];
        return out;
    }
    return [NSString stringWithFormat:@"obj(%@)", [value class]];
}

static NSString *tagline(CGImageMetadataTagRef tag)
{
    if (!tag)
        return @"(nil)";
    NSString *ns = (__bridge_transfer NSString *)CGImageMetadataTagCopyNamespace(tag);
    NSString *prefix = (__bridge_transfer NSString *)CGImageMetadataTagCopyPrefix(tag);
    NSString *name = (__bridge_transfer NSString *)CGImageMetadataTagCopyName(tag);
    id value = (__bridge_transfer id)CGImageMetadataTagCopyValue(tag);
    NSInteger type = (NSInteger)CGImageMetadataTagGetType(tag);
    CFArrayRef qualifiers = CGImageMetadataTagCopyQualifiers(tag);
    NSInteger count = qualifiers ? (NSInteger)CFArrayGetCount(qualifiers) : -1;
    if (qualifiers)
        CFRelease(qualifiers);
    return [NSString stringWithFormat:@"ns=%@ prefix=%@ name=%@ type=%ld value=%@ qualifiers=%ld", ns, prefix, name,
                                      (long)type, show(value), (long)count];
}

static void report(NSString *label, CGImageMetadataTagRef tag)
{
    record([NSString stringWithFormat:@"tag %@", label], tagline(tag));
}

static void reportValue(NSString *label, CGImageMetadataTagRef tag)
{
    id value = tag ? (__bridge_transfer id)CGImageMetadataTagCopyValue(tag) : nil;
    record([NSString stringWithFormat:@"value %@", label], show(value));
}

static void dumpAll(const char *label, CGImageMetadataRef m)
        {
            CFArrayRef tags = CGImageMetadataCopyTags(m);
            NSMutableString *out = [NSMutableString stringWithString:[NSString stringWithFormat:@"%@", @(label)]];
            for (CFIndex i = 0; tags && i < CFArrayGetCount(tags); i++) {
                CGImageMetadataTagRef tag = (CGImageMetadataTagRef)CFArrayGetValueAtIndex(tags, i);
                [out appendFormat:@"|%@", show((__bridge id)tag)];
            }
            record(@"tags", out);
            if (tags)
                CFRelease(tags);
        }

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);

        // A tag the host's own type identity: an ObjC object of a class of ours is never a CF dictionary,
        // and this harness needs the port binary to be provably running the port's code, not ImageIO's.
#ifdef CHARON_PORT
        {
            struct { const char *name; const void *address; } rows[] = {
                { "CGImageMetadataTagCreate", (const void *)&CGImageMetadataTagCreate },
                { "CGImageMetadataTagCopyName", (const void *)&CGImageMetadataTagCopyName },
                { "CGImageMetadataCreateMutable", (const void *)&CGImageMetadataCreateMutable },
                { "CGImageMetadataCopyTags", (const void *)&CGImageMetadataCopyTags },
            };
            NSMutableString *held = [NSMutableString string];
            for (size_t i = 0; i < sizeof rows / sizeof rows[0]; i++) {
                Dl_info info;
                if (dladdr(rows[i].address, &info) && info.dli_fname &&
                    strstr(info.dli_fname, "ImageIO") == NULL)
                    [held appendFormat:@"%s=port,", rows[i].name];
                else
                    [held appendFormat:@"%s=imageio,", rows[i].name];
            }
            record(@"PORTONLY binding", held);
        }
        // an object that is not this library's must be refused, never read
        {
            NSDictionary *foreign = [NSDictionary dictionary];
            record(@"PORTONLY foreign-tag", tagline(CGImageMetadataTagCopyName((__bridge CGImageMetadataTagRef)foreign)));
            record(@"PORTONLY foreign-metadata",
                   CGImageMetadataCopyTags((__bridge CGImageMetadataRef)foreign) ? @"answered" : @"(nil)");
            record(@"PORTONLY foreign-copy",
                   CGImageMetadataCreateMutableCopy((__bridge CGImageMetadataRef)foreign) ? @"answered" : @"(nil)");
            record(@"PORTONLY foreign-copy-string",
                   CGImageMetadataCreateMutableCopy((CGImageMetadataRef)CFSTR("x")) ? @"answered" : @"(nil)");
            // a nonnull the header declares _Nonnull: the host traps on these (measured, SIGTRAP), so
            // there is no host answer to compare and the port's refusal is recorded on its own
            record(@"PORTONLY precondition null-name",
                   CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, NULL, kCGImageMetadataTypeString, CFSTR("v"))
                       ? @"answered"
                       : @"(nil)");
            record(@"PORTONLY precondition null-namespace",
                   CGImageMetadataTagCreate(NULL, CFSTR("mine"), CFSTR("Name"), kCGImageMetadataTypeString, CFSTR("v"))
                       ? @"answered"
                       : @"(nil)");
            record(@"PORTONLY precondition null-value",
                   CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"), kCGImageMetadataTypeString, NULL)
                       ? @"answered"
                       : @"(nil)");
        }
#endif

        record(@"metadata create", CGImageMetadataCreateMutable() ? @"yes" : @"no");
        CGMutableImageMetadataRef empty = CGImageMetadataCreateMutable();
        CFArrayRef noTags = CGImageMetadataCopyTags(empty);
        record(@"metadata empty count", [NSString stringWithFormat:@"%ld", noTags ? (long)CFArrayGetCount(noTags) : -1L]);
        if (noTags)
            CFRelease(noTags);

        record(@"typeid tag nonzero", CGImageMetadataTagGetTypeID() != 0 ? @"yes" : @"no");

        // the default prefix of every public namespace, asked of the host and answered the same way
        struct { const char *label; CFStringRef ns; } namespaces[] = {
            { "exif", kCGImageMetadataNamespaceExif },
            { "exifAux", kCGImageMetadataNamespaceExifAux },
            { "exifEX", kCGImageMetadataNamespaceExifEX },
            { "dc", kCGImageMetadataNamespaceDublinCore },
            { "iptcCore", kCGImageMetadataNamespaceIPTCCore },
            { "iptcExt", kCGImageMetadataNamespaceIPTCExtension },
            { "photoshop", kCGImageMetadataNamespacePhotoshop },
            { "tiff", kCGImageMetadataNamespaceTIFF },
            { "xmp", kCGImageMetadataNamespaceXMPBasic },
            { "xmpRights", kCGImageMetadataNamespaceXMPRights },
        };
        for (size_t i = 0; i < sizeof namespaces / sizeof namespaces[0]; i++) {
            NSString *label = [NSString stringWithFormat:@"default-prefix %@", @(namespaces[i].label)];
            CGImageMetadataTagRef tag = CGImageMetadataTagCreate(namespaces[i].ns, NULL, CFSTR("Name"),
                                                                 kCGImageMetadataTypeDefault, CFSTR("v"));
            NSString *prefix = tag ? (__bridge_transfer NSString *)CGImageMetadataTagCopyPrefix(tag) : nil;
            if (tag)
                CFRelease(tag);
            record(label, prefix ?: @"(nil)");
        }

        report(@"given-prefix", CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, CFSTR("mine"), CFSTR("Name"),
                                                        kCGImageMetadataTypeString, CFSTR("v")));
        report(@"unknown-ns-no-prefix",
               CGImageMetadataTagCreate(CFSTR("not a namespace"), NULL, CFSTR("Name"), kCGImageMetadataTypeString, CFSTR("v")));
        report(@"unknown-ns-prefix",
               CGImageMetadataTagCreate(CFSTR("not a namespace"), CFSTR("mine"), CFSTR("Name"), kCGImageMetadataTypeString,
                                        CFSTR("v")));
        report(@"invalid-type",
               CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"), (CGImageMetadataType)99, CFSTR("v")));

        // kCGImageMetadataTypeDefault reads the type off the CFType of the value
        CGImageMetadataTagRef fromString = CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"),
                                                                    kCGImageMetadataTypeDefault, CFSTR("v"));
        CGImageMetadataTagRef fromNumber = CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"),
                                                                    kCGImageMetadataTypeDefault, (__bridge CFTypeRef)@2);
        CGImageMetadataTagRef fromArray = CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"),
                                                                   kCGImageMetadataTypeDefault,
                                                                   (__bridge CFTypeRef)[NSArray arrayWithObjects:@"a", @"b", nil]);
        CGImageMetadataTagRef fromDictionary =
            CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"), kCGImageMetadataTypeDefault,
                                     (__bridge CFTypeRef)[NSDictionary dictionaryWithObject:@"v" forKey:@"F"]);
        record(@"default string", [NSString stringWithFormat:@"%ld", (long)CGImageMetadataTagGetType(fromString)]);
        record(@"default number", [NSString stringWithFormat:@"%ld", (long)CGImageMetadataTagGetType(fromNumber)]);
        record(@"default array", [NSString stringWithFormat:@"%ld", (long)CGImageMetadataTagGetType(fromArray)]);
        record(@"default dictionary", [NSString stringWithFormat:@"%ld", (long)CGImageMetadataTagGetType(fromDictionary)]);
        reportValue(@"default array elements", fromArray);
        reportValue(@"default dictionary elements", fromDictionary);

        // every declared type, asked of the type getter and answered as a number
        for (int type = 0; type <= 6; type++) {
            CGImageMetadataTagRef tag = CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Name"),
                                                                 (CGImageMetadataType)type, CFSTR("v"));
            record([NSString stringWithFormat:@"declared type %d", type],
                   [NSString stringWithFormat:@"%ld", (long)CGImageMetadataTagGetType(tag)]);
        }

        // a mutable copy is a different container. Its tags are compared in full once the path API
        // (the next commit of this slice) can put tags into one; until then the empty container is what
        // the copy case says, and it says so in its own name rather than by a comment.
        CGMutableImageMetadataRef source = CGImageMetadataCreateMutable();
        CGMutableImageMetadataRef copy = CGImageMetadataCreateMutableCopy(source);
        record(@"copy of empty", copy ? @"yes" : @"no");
        CFArrayRef sourceTags = CGImageMetadataCopyTags(source);
        CFArrayRef copyTags = CGImageMetadataCopyTags(copy);
        record(@"copy count of empty", [NSString stringWithFormat:@"%ld/%ld", sourceTags ? (long)CFArrayGetCount(sourceTags) : -1L,
                                                                     copyTags ? (long)CFArrayGetCount(copyTags) : -1L]);
        record(@"copy is another container", source == copy ? @"same" : @"different");
        // MARK: paths
        // Every path function is asked of the same paths and the container is printed after each step, so a
        // difference in what a path DID shows up as a difference in what the container then holds, not only
        // in a boolean the caller never checks.
        CGMutableImageMetadataRef pathed = CGImageMetadataCreateMutable();
        struct { const char *label; const char *path; int value; } sets[] = {
            { "string", "exif:Flash", 0 },
            { "number", "tiff:Orientation", 1 },
            { "field", "exif:Flash.Fired", 1 },
            { "array", "dc:subject", 2 },
            { "element", "dc:subject[1]", 3 },
            { "unregistered", "ex:Thing", 0 },
            { "unknown-ns", "nope:Thing", 0 },
            { "no-prefix", "Thing", 0 },
        };
        for (size_t i = 0; i < sizeof sets / sizeof sets[0]; i++) {
            CFStringRef path = CFRetain((__bridge CFStringRef)[NSString stringWithUTF8String:sets[i].path]);
            CFTypeRef value = sets[i].value == 1 ? (__bridge CFTypeRef)@"1"
                             : sets[i].value == 2 ? (__bridge CFTypeRef)[NSArray arrayWithObjects:@"one", @"two", nil]
                                                  : (CFTypeRef)CFSTR("v");
            BOOL ok = CGImageMetadataSetValueWithPath(pathed, NULL, path, value);
            record([NSString stringWithFormat:@"set %@", @(sets[i].label)],
                   [NSString stringWithFormat:@"%d %@", (int)ok, show((__bridge id)value)]);
            dumpAll("after set", pathed);
            CFRelease(path);
        }
        for (size_t i = 0; i < sizeof sets / sizeof sets[0]; i++) {
            CFStringRef path = CFRetain((__bridge CFStringRef)[NSString stringWithUTF8String:sets[i].path]);
            CFStringRef text = CGImageMetadataCopyStringValueWithPath(pathed, NULL, path);
            NSString *answer = text ? (__bridge_transfer NSString *)text : @"(nil)";
            if (text)
                CFRelease(text);
            record([NSString stringWithFormat:@"string %@", @(sets[i].label)], answer);
            CGImageMetadataTagRef tag = CGImageMetadataCopyTagWithPath(pathed, NULL, path);
            record([NSString stringWithFormat:@"tag-at %@", @(sets[i].label)], tagline(tag));
            if (tag)
                CFRelease(tag);
            CFRelease(path);
        }
        // a tag set through the path API, then replaced by SetTagWithPath
        CGImageMetadataTagRef made = CGImageMetadataTagCreate(kCGImageMetadataNamespaceExif, NULL, CFSTR("Made"),
                                                             kCGImageMetadataTypeString, CFSTR("by tag"));
        record(@"set-tag made", CGImageMetadataSetTagWithPath(pathed, NULL, CFSTR("exif:Made"), made) ? @"yes" : @"no");
        dumpAll("after set-tag", pathed);
        record(@"set-tag missing path",
               CGImageMetadataSetTagWithPath(pathed, NULL, CFSTR("nope:Made"), made) ? @"yes" : @"no");
        record(@"set-tag foreign tag",
               CGImageMetadataSetTagWithPath(pathed, NULL, CFSTR("exif:Foreign"), (CGImageMetadataTagRef)(const void *)CFSTR("x"))
                   ? @"yes"
                   : @"no");
        // a parent tag: the header says the children of the parent are modified and have to be committed
        CGImageMetadataTagRef parentTag = CGImageMetadataCopyTagWithPath(pathed, NULL, CFSTR("exif:Flash"));
        record(@"parent found", parentTag ? @"yes" : @"no");
        record(@"set in parent", CGImageMetadataSetValueWithPath(pathed, parentTag, CFSTR("RedEyeMode"), CFSTR("on"))
                                       ? @"yes"
                                       : @"no");
        dumpAll("after set in parent", pathed);
        {
            CFStringRef text = CGImageMetadataCopyStringValueWithPath(pathed, parentTag, CFSTR("RedEyeMode"));
            record(@"parent value", text ? (__bridge_transfer NSString *)text : @"(nil)");
            if (text)
                CFRelease(text);
        }

        record(@"remove present", CGImageMetadataRemoveTagWithPath(pathed, NULL, CFSTR("exif:Made")) ? @"yes" : @"no");
        record(@"remove again", CGImageMetadataRemoveTagWithPath(pathed, NULL, CFSTR("exif:Made")) ? @"yes" : @"no");
        record(@"remove missing ns", CGImageMetadataRemoveTagWithPath(pathed, NULL, CFSTR("nope:Made")) ? @"yes" : @"no");
        dumpAll("after removes", pathed);

        CGMutableImageMetadataRef registered = CGImageMetadataCreateMutable();
        CFErrorRef conflict = NULL;
        record(@"register new", CGImageMetadataRegisterNamespaceForPrefix(registered, CFSTR("http://example.com/ns/"),
                                                                        CFSTR("ex"), NULL)
                                      ? @"yes"
                                      : @"no");
        record(@"register same again",
               CGImageMetadataRegisterNamespaceForPrefix(registered, CFSTR("http://example.com/ns/"), CFSTR("ex"), NULL)
                   ? @"yes"
                   : @"no");
        record(@"register conflict",
               CGImageMetadataRegisterNamespaceForPrefix(registered, CFSTR("http://other.example/"), CFSTR("ex"),
                                                         &conflict)
                   ? @"yes"
                   : @"no");
        record(@"register conflict error", conflict ? @"yes" : @"no");
        if (conflict)
            CFRelease(conflict);
        record(@"set with registered prefix",
               CGImageMetadataSetValueWithPath(registered, NULL, CFSTR("ex:Thing"), CFSTR("v")) ? @"yes" : @"no");
        {
            CFStringRef text = CGImageMetadataCopyStringValueWithPath(registered, NULL, CFSTR("ex:Thing"));
            NSString *answer = text ? (__bridge_transfer NSString *)text : @"(nil)";
            if (text)
                CFRelease(text);
            record(@"string with registered prefix", answer);
        }
        dumpAll("registered", registered);

        // enumeration: the paths the block is given, with and without the recursive option
        NSMutableString *flat = [NSMutableString string];
        CGImageMetadataEnumerateTagsUsingBlock(pathed, NULL, NULL, ^(CFStringRef path, CGImageMetadataTagRef tag) {
            [flat appendFormat:@"%@;", (__bridge NSString *)path];
            return YES;
        });
        record(@"enumerate", flat);
        NSMutableString *deep = [NSMutableString string];
        CGImageMetadataEnumerateTagsUsingBlock(
            pathed, NULL, (__bridge CFDictionaryRef)@{ (__bridge id)kCGImageMetadataEnumerateRecursively : @YES },
            ^(CFStringRef path, CGImageMetadataTagRef tag) {
                [flat class]; // keep the block's captures honest for the compiler
                [deep appendFormat:@"%@;", (__bridge NSString *)path];
                return YES;
            });
        record(@"enumerate recursive", deep);
        NSMutableString *stopped = [NSMutableString string];
        CGImageMetadataEnumerateTagsUsingBlock(pathed, NULL, NULL, ^(CFStringRef path, CGImageMetadataTagRef tag) {
            [stopped appendFormat:@"%@;", (__bridge NSString *)path];
            return NO; // "return false to stop"
        });
        record(@"enumerate stopped", stopped);
        NSMutableString *rooted = [NSMutableString string];
        CGImageMetadataEnumerateTagsUsingBlock(pathed, CFSTR("exif:Flash"), NULL, ^(CFStringRef path, CGImageMetadataTagRef tag) {
            [rooted appendFormat:@"%@;", (__bridge NSString *)path];
            return YES;
        });
        record(@"enumerate rooted", rooted);
        NSMutableString *none = [NSMutableString string];
        CGImageMetadataEnumerateTagsUsingBlock(pathed, CFSTR("nope:Flash"), NULL, ^(CFStringRef path, CGImageMetadataTagRef tag) {
            [none appendString:@"called"];
            return YES;
        });
        record(@"enumerate missing root", none);

        if (sourceTags)
            CFRelease(sourceTags);
        if (copyTags)
            CFRelease(copyTags);
        return 0;
    }
}