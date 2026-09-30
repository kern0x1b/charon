// CGImageMetadata and CGImageMetadataTag: the tag container of iOS 7, over the release's own
// CoreFoundation, for a release whose ImageIO has no metadata tree of its own.
//
// MEASURED, tools/cache-index/first-rung.py over the 50 held rungs (2026-09-30, .agent-work/runs/io-rungs.txt):
// every CGImageMetadata* symbol this file defines first appears on the 7.0 rung and on no rung below it,
// so one object holds the whole 7.0 surface and needs no split. The names iOS 6 does export
// (kCGImageMetadataNamespaceExif and its seven siblings, CGImageSourceCopyMetadataAtIndex) are the
// release's own and are read here, never defined: registry/ImageIO/exported.json.
//
// A metadata or a tag handed in is checked by CFGetTypeID against the container this file builds,
// because the release exports an object of its own class for CGImageSourceCopyMetadataAtIndex: reading
// that one as a tree would walk memory this library did not lay out, so it is refused (NULL) instead.

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

// MARK: - the two opaque types

static NSString *const charonMetadataMarker = @"charon.metadata";
static NSString *const charonTagMarker = @"charon.tag";

static BOOL charon_is_metadata(CFTypeRef object)
{
    if (!object || CFGetTypeID(object) != CFDictionaryGetTypeID())
        return NO;
    return [(__bridge NSDictionary *)object objectForKey:charonMetadataMarker] != nil;
}

static BOOL charon_is_tag(CFTypeRef object)
{
    if (!object || CFGetTypeID(object) != CFDictionaryGetTypeID())
        return NO;
    return [(__bridge NSDictionary *)object objectForKey:charonTagMarker] != nil;
}

static NSDictionary *charon_metadata(CFTypeRef object)
{
    return charon_is_metadata(object) ? (__bridge NSDictionary *)object : nil;
}

static NSDictionary *charon_tag(CFTypeRef object)
{
    return charon_is_tag(object) ? (__bridge NSDictionary *)object : nil;
}

// MARK: - the default prefix of a namespace
//
// The header says "For the public namespaces defined above, no prefix is required - ImageIO will use
// appropriate defaults", and the host answers a NULL prefix with the public prefix of the same namespace
// (measured: facts/ImageIO/Metadata.md, "TagCreate with a NULL prefix"). The table is built by asking
// which public namespace constant the caller passed, so no namespace URI is written here: the release
// exports most of those constants itself, and the port carries the prefixes (Graphics/ImageIONames70.m).

static CFStringRef charon_default_prefix(CFStringRef xmlns)
{
    struct {
        CFStringRef xmlns;
        CFStringRef prefix;
    } table[] = {
        { kCGImageMetadataNamespaceExif, kCGImageMetadataPrefixExif },
        { kCGImageMetadataNamespaceExifAux, kCGImageMetadataPrefixExifAux },
        { kCGImageMetadataNamespaceExifEX, kCGImageMetadataPrefixExifEX },
        { kCGImageMetadataNamespaceDublinCore, kCGImageMetadataPrefixDublinCore },
        { kCGImageMetadataNamespaceIPTCCore, kCGImageMetadataPrefixIPTCCore },
        { kCGImageMetadataNamespaceIPTCExtension, kCGImageMetadataPrefixIPTCExtension },
        { kCGImageMetadataNamespacePhotoshop, kCGImageMetadataPrefixPhotoshop },
        { kCGImageMetadataNamespaceTIFF, kCGImageMetadataPrefixTIFF },
        { kCGImageMetadataNamespaceXMPBasic, kCGImageMetadataPrefixXMPBasic },
        { kCGImageMetadataNamespaceXMPRights, kCGImageMetadataPrefixXMPRights },
    };
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++)
        if (xmlns == table[i].xmlns)
            return table[i].prefix;
    return NULL;
}

// MARK: - tag values
//
// "The elements of a CFArray must be either a CFStringRef or CGImageMetadataTagRef. The keys of a
// CFDictionary must be CFStringRefs with valid XMP names. The values of a CFDictionary must be either
// CFStringRefs or CGImageMetadataTagRefs." A bare string inside one of them is turned into a tag of the
// enclosing tag's namespace and prefix, which is what the host's own value holds (measured: the value of
// an ArrayUnordered tag created from @[@"a", @@"b"] describes as two CGImageMetadataTags, not two
// CFStrings - facts/ImageIO/Metadata.md, "an array value holds tags").

static CGImageMetadataType charon_type_of_value(id value)
{
    if ([value isKindOfClass:[NSString class]])
        return kCGImageMetadataTypeString;
    if ([value isKindOfClass:[NSNumber class]])
        return kCGImageMetadataTypeString;
    if ([value isKindOfClass:[NSArray class]])
        return kCGImageMetadataTypeArrayOrdered;
    if ([value isKindOfClass:[NSDictionary class]])
        return kCGImageMetadataTypeStructure;
    return kCGImageMetadataTypeInvalid;
}

static id charon_wrap(id value, NSString *ns, NSString *prefix)
{
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *wrapped = [NSMutableArray arrayWithCapacity:[value count]];
        NSUInteger index = 0;
        for (id element in (NSArray *)value) {
            // an element of an array is named by its position, "[0]", "[1]": that is what the host's own
            // value carries (measured: an ArrayUnordered tag built from @[@"a", @"b"] describes its
            // elements as [0] and [1] - facts/ImageIO/Metadata.md, "an array value holds tags")
            NSString *name = [NSString stringWithFormat:@"[%lu]", (unsigned long)index++];
            CGImageMetadataTagRef tag = CGImageMetadataTagCreate((__bridge CFStringRef)ns, (__bridge CFStringRef)prefix,
                                                                 (__bridge CFStringRef)name, charon_type_of_value(element),
                                                                 (__bridge CFTypeRef)element);
            if (!tag)
                return nil;
            [wrapped addObject:(__bridge id)tag];
            CFRelease(tag);
        }
        return wrapped;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *wrapped = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        for (id key in (NSDictionary *)value) {
            id element = [(NSDictionary *)value objectForKey:key];
            CGImageMetadataTagRef tag = CGImageMetadataTagCreate((__bridge CFStringRef)ns, (__bridge CFStringRef)prefix,
                                                                 (__bridge CFStringRef)key, charon_type_of_value(element),
                                                                 (__bridge CFTypeRef)element);
            if (!tag)
                return nil;
            [wrapped setObject:(__bridge id)tag forKey:key];
            CFRelease(tag);
        }
        return wrapped;
    }
    return value;
}

// MARK: - CGImageMetadataTag, the iOS 7 surface

CGImageMetadataTagRef CGImageMetadataTagCreate(CFStringRef xmlns, CFStringRef prefix, CFStringRef name,
                                              CGImageMetadataType type, CFTypeRef value)
{
    if (!xmlns || !name || !value)
        return NULL;
    NSString *given = prefix ? (__bridge NSString *)prefix : nil;
    if (!given) {
        CFStringRef known = charon_default_prefix(xmlns);
        if (!known)
            return NULL; // the header: a custom namespace needs a custom prefix
        given = (__bridge NSString *)known;
    }
    id object = (__bridge id)value;
    CGImageMetadataType resolved = type == kCGImageMetadataTypeDefault ? charon_type_of_value(object) : type;
    if (resolved == kCGImageMetadataTypeInvalid)
        return NULL;
    if (resolved != kCGImageMetadataTypeString && resolved != kCGImageMetadataTypeArrayUnordered &&
        resolved != kCGImageMetadataTypeArrayOrdered && resolved != kCGImageMetadataTypeAlternateArray &&
        resolved != kCGImageMetadataTypeAlternateText && resolved != kCGImageMetadataTypeStructure)
        return NULL;
    id wrapped = charon_wrap(object, (__bridge NSString *)xmlns, given);
    if (!wrapped)
        return NULL;
    NSMutableDictionary *tag = [NSMutableDictionary dictionaryWithCapacity:6];
        [tag setObject:@YES forKey:charonTagMarker];
        [tag setObject:(__bridge id)xmlns forKey:@"namespace"];
        [tag setObject:given forKey:@"prefix"];
        [tag setObject:(__bridge id)name forKey:@"name"];
        [tag setObject:@(resolved) forKey:@"type"];
        [tag setObject:wrapped forKey:@"value"];
    return (__bridge_retained CGImageMetadataTagRef)tag;
}

CFStringRef CGImageMetadataTagCopyNamespace(CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_tag(tag);
    if (!held)
        return NULL;
    return CFRetain((__bridge CFStringRef)[held objectForKey:@"namespace"]);
}

CFStringRef CGImageMetadataTagCopyPrefix(CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_tag(tag);
    if (!held)
        return NULL;
    return CFRetain((__bridge CFStringRef)[held objectForKey:@"prefix"]);
}

CFStringRef CGImageMetadataTagCopyName(CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_tag(tag);
    if (!held)
        return NULL;
    return CFRetain((__bridge CFStringRef)[held objectForKey:@"name"]);
}

CFTypeRef CGImageMetadataTagCopyValue(CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_tag(tag);
    if (!held)
        return NULL;
    return CFRetain((__bridge CFTypeRef)[held objectForKey:@"value"]);
}

CGImageMetadataType CGImageMetadataTagGetType(CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_tag(tag);
    if (!held)
        return kCGImageMetadataTypeInvalid;
    return (CGImageMetadataType)[[held objectForKey:@"type"] intValue];
}

CFArrayRef CGImageMetadataTagCopyQualifiers(CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_tag(tag);
    if (!held)
        return NULL;
    id qualifiers = [held objectForKey:@"qualifiers"];
    if (![qualifiers isKindOfClass:[NSArray class]] || [qualifiers count] == 0)
        return NULL;
    return CFRetain((__bridge CFArrayRef)qualifiers);
}

CFTypeID CGImageMetadataTagGetTypeID(void)
{
    // the marker is what makes a tag identifiable; the type id is the identity of a dictionary carrying it
    return CFDictionaryGetTypeID();
}

// MARK: - CGImageMetadata, the container

CGMutableImageMetadataRef CGImageMetadataCreateMutable(void)
{
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithCapacity:3];
        [metadata setObject:@YES forKey:charonMetadataMarker];
        [metadata setObject:[NSMutableArray array] forKey:@"tags"];
        [metadata setObject:[NSMutableDictionary dictionary] forKey:@"prefixes"];
    return (__bridge_retained CGMutableImageMetadataRef)metadata;
}

CGMutableImageMetadataRef CGImageMetadataCreateMutableCopy(CGImageMetadataRef metadata)
{
    NSDictionary *held = charon_metadata(metadata);
    if (!held)
        return NULL;
    NSArray *tags = [held objectForKey:@"tags"];
    NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:3];
        [copy setObject:@YES forKey:charonMetadataMarker];
    // "a deep mutable copy": the tags are copied, the values they hold are shared, as a copy of a tag is
    NSMutableArray *copiedTags = [NSMutableArray arrayWithCapacity:[tags count]];
    for (id tag in tags) {
        NSDictionary *source = (NSDictionary *)tag;
        NSMutableDictionary *one = [source mutableCopy];
        [copiedTags addObject:one];
    }
        [copy setObject:copiedTags forKey:@"tags"];
    NSDictionary *registered = [[held objectForKey:@"prefixes"] mutableCopy];
    [copy setObject:registered ? registered : [NSMutableDictionary dictionary] forKey:@"prefixes"];
    return (__bridge_retained CGMutableImageMetadataRef)copy;
}

CFArrayRef CGImageMetadataCopyTags(CGImageMetadataRef metadata)
{
    NSDictionary *held = charon_metadata(metadata);
    if (!held)
        return NULL;
    return CFRetain((__bridge CFArrayRef)[held objectForKey:@"tags"]);
}