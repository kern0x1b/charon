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

// True of a value that is one of this library's tags. A structure's value is a dictionary and a tag is a
// dictionary too, so the marker decides and the type id cannot.
static BOOL isTag(id value)
{
    if (!value || ![value isKindOfClass:[NSDictionary class]])
        return NO;
    return [(NSDictionary *)value objectForKey:charonTagMarker] != nil;
}

// MARK: - the default prefix of a namespace
//
// The header says "For the public namespaces defined above, no prefix is required - ImageIO will use
// appropriate defaults", and the host answers a NULL prefix with the public prefix of the same namespace
// (measured: facts/ImageIO/Metadata.md, "TagCreate with a NULL prefix"). The table is built by asking
// which public namespace constant the caller passed, so no namespace URI is written here: the release
// exports most of those constants itself, and the port carries the prefixes (Graphics/ImageIONames70.m).

// The ten public namespaces and their prefixes, one table read in both directions: the prefix a NULL
// prefix resolves to, and the namespace a path's prefix names.
typedef struct {
    CFStringRef xmlns;
    CFStringRef prefix;
} charon_public;

// The table is filled into the caller's own array rather than kept in a file-scope one: the constants are
// not compile-time constants for a static initializer (CFSTR is a builtin call), and a table written once
// and read from every thread would need a lock this library has no reason to carry.
#define CHARON_PUBLIC_NAMESPACES 10
static size_t charon_public_namespaces(charon_public *table)
{
    table[0].xmlns = kCGImageMetadataNamespaceExif;
    table[0].prefix = kCGImageMetadataPrefixExif;
    table[1].xmlns = kCGImageMetadataNamespaceExifAux;
    table[1].prefix = kCGImageMetadataPrefixExifAux;
    table[2].xmlns = kCGImageMetadataNamespaceExifEX;
    table[2].prefix = kCGImageMetadataPrefixExifEX;
    table[3].xmlns = kCGImageMetadataNamespaceDublinCore;
    table[3].prefix = kCGImageMetadataPrefixDublinCore;
    table[4].xmlns = kCGImageMetadataNamespaceIPTCCore;
    table[4].prefix = kCGImageMetadataPrefixIPTCCore;
    table[5].xmlns = kCGImageMetadataNamespaceIPTCExtension;
    table[5].prefix = kCGImageMetadataPrefixIPTCExtension;
    table[6].xmlns = kCGImageMetadataNamespacePhotoshop;
    table[6].prefix = kCGImageMetadataPrefixPhotoshop;
    table[7].xmlns = kCGImageMetadataNamespaceTIFF;
    table[7].prefix = kCGImageMetadataPrefixTIFF;
    table[8].xmlns = kCGImageMetadataNamespaceXMPBasic;
    table[8].prefix = kCGImageMetadataPrefixXMPBasic;
    table[9].xmlns = kCGImageMetadataNamespaceXMPRights;
    table[9].prefix = kCGImageMetadataPrefixXMPRights;
    return CHARON_PUBLIC_NAMESPACES;
}


static CFStringRef charon_default_prefix(CFStringRef xmlns)
{
    charon_public table[CHARON_PUBLIC_NAMESPACES];
    size_t count = charon_public_namespaces(table);
    for (size_t i = 0; i < count; i++)
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

// Forward: the copy a container hands out, defined with the paths below because that is where a tag's
// value is walked.
static NSDictionary *charon_tag_copy(NSDictionary *tag);

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
    NSArray *tags = [held objectForKey:@"tags"];
    NSMutableArray *copies = [NSMutableArray arrayWithCapacity:tags.count];
    for (id tag in tags)
        [copies addObject:charon_tag_copy((NSDictionary *)tag)];
    // and in the order the host hands them over: by name, then by prefix (measured: a tag named "Made"
    // added to a container holding Flash, Orientation and subject answers second, not last)
    [copies sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSComparisonResult byName = [[a objectForKey:@"name"] compare:[b objectForKey:@"name"]];
        if (byName != NSOrderedSame)
            return byName;
        return [[a objectForKey:@"prefix"] compare:[b objectForKey:@"prefix"]];
    }];
    return CFRetain((__bridge CFArrayRef)copies);
}
// MARK: - paths
//
// CGImageMetadata.h, on CGImageMetadataCopyTagWithPath's path argument:
//
//   'path' = CFSTR("xmp:CreateDate")
//   'path' = CFSTR("exif:Flash.Fired")              a field of a structure, '.'
//   'path' = CFSTR("dc:subject[2]")                 an element of an array, '[]'
//   'path' = CFSTR("dc:description[x-default]")     an alternate-text element, named by its language
//   'path' = CFSTR("foo:product?bar:manufacturer")  a qualifier, '?'
//
//   Prefixes after the first are optional and inherited from the nearest parent tag that has one. With a
//   NULL parent a prefix is required on the first step. "Creating tags will fail if a prefix is
//   encountered that has not been registered."
//
// A step is a dictionary of its own rather than a C struct: a struct of ARC-managed fields travelling
// through a function and an NSValue made clang emit its own copy, default-copy and destructor helpers
// with external linkage, and a symbol this library does not own in a dyld cache is what tools/release-split.lua
// reads as an API symbol (measured: three such helpers in the object's nm -gU, which its exclusion list
// does not cover because it lists the ___copy_helper_block_* family, not these).

static NSDictionary *charon_step_parse(NSString *text)
{
    NSMutableDictionary *step = [NSMutableDictionary dictionaryWithCapacity:6];
    NSMutableString *rest = [NSMutableString stringWithString:text];
    NSRange question = [rest rangeOfString:@"?"];
    if (question.location != NSNotFound) {
        NSString *qualifier = [rest substringFromIndex:question.location + 1];
        [rest deleteCharactersInRange:NSMakeRange(question.location, rest.length - question.location)];
        NSRange colon = [qualifier rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            [step setObject:qualifier forKey:@"qualifierName"];
        } else {
            [step setObject:[qualifier substringToIndex:colon.location] forKey:@"qualifierPrefix"];
            [step setObject:[qualifier substringFromIndex:colon.location + 1] forKey:@"qualifierName"];
        }
    }
    NSRange colon = [rest rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        [step setObject:[rest substringToIndex:colon.location] forKey:@"prefix"];
        [rest deleteCharactersInRange:NSMakeRange(0, colon.location + 1)];
    }
    NSRange bracket = [rest rangeOfString:@"["];
    NSString *name = rest;
    if (bracket.location != NSNotFound) {
        name = [rest substringToIndex:bracket.location];
        NSRange close = [rest rangeOfString:@"]" options:NSBackwardsSearch];
        NSString *key = [rest substringWithRange:NSMakeRange(bracket.location + 1, close.location - bracket.location - 1)];
        NSInteger index = 0;
        NSScanner *scanner = [NSScanner scannerWithString:key];
        [step setObject:([scanner scanInteger:&index] && [scanner isAtEnd] ? (id)@(index) : (id)key) forKey:@"key"];
        [rest deleteCharactersInRange:NSMakeRange(bracket.location, rest.length - bracket.location)];
    }
    NSRange dot = [rest rangeOfString:@"."];
    if (dot.location != NSNotFound) {
        name = [rest substringToIndex:dot.location];
        [step setObject:[[rest substringFromIndex:dot.location + 1] componentsSeparatedByString:@"."] forKey:@"fields"];
    }
    if ([name length])
        [step setObject:name forKey:@"name"];
    return step;
}

static NSArray *charon_steps(NSString *path)
{
    NSMutableArray *steps = [NSMutableArray array];
    for (NSString *part in [path componentsSeparatedByString:@"/"])
        if ([part length])
            [steps addObject:charon_step_parse(part)];
    return steps;
}

// The namespace a prefix names: the public one, or one CGImageMetadataRegisterNamespaceForPrefix added to
// this container. NULL means the prefix is not registered here, and every path function fails on it.
static NSString *charon_namespace_for_prefix(NSDictionary *metadata, NSString *prefix)
{
    NSString *registered = [[metadata objectForKey:@"prefixes"] objectForKey:prefix];
    if (registered)
        return registered;
    charon_public table[CHARON_PUBLIC_NAMESPACES];
    size_t count = charon_public_namespaces(table);
    // by text, not by pointer: the prefix of a path is spelled out in the path and is a string this
    // library made, while the public prefixes are constants (the release's own, or Graphics/ImageIONames70.m's).
    for (size_t i = 0; i < count; i++)
        if ([prefix isEqualToString:(__bridge NSString *)table[i].prefix])
            return (__bridge NSString *)table[i].xmlns;
    return nil;
}


// The tag of a container carrying this prefix and name, or nil. A step that names no prefix of its own
// inherits, so a nil prefix matches on the name alone.
static NSMutableDictionary *charon_find_tag(NSArray *tags, NSString *prefix, NSString *name)
{
    for (id held in tags) {
        NSMutableDictionary *tag = (NSMutableDictionary *)held;
        if (![tag[@"name"] isEqualToString:name])
            continue;
        if (prefix && ![tag[@"prefix"] isEqualToString:prefix])
            continue;
        return tag;
    }
    return nil;
}

// A tag made to hold a value the path has not resolved to yet. "Tags will be created with default types
// (ordered arrays)", so a step that indexes into a tag's value gets an ordered array and a step that names
// a field of it gets a structure.
static NSMutableDictionary *charon_intermediate(NSString *ns, NSString *prefix, NSString *name, BOOL asArray)
{
    NSMutableDictionary *tag = [NSMutableDictionary dictionaryWithCapacity:6];
    [tag setObject:@YES forKey:charonTagMarker];
    [tag setObject:ns forKey:@"namespace"];
    [tag setObject:prefix forKey:@"prefix"];
    [tag setObject:name forKey:@"name"];
    [tag setObject:@(asArray ? kCGImageMetadataTypeArrayOrdered : kCGImageMetadataTypeStructure) forKey:@"type"];
    [tag setObject:(asArray ? (id)[NSMutableArray array] : (id)[NSMutableDictionary dictionary]) forKey:@"value"];
    return tag;
}

// A tag out of a container is a COPY, value included, which is what the header says the caller has to
// assume: "Since tags are normally obtained as a copy, it is typically necessary to use
// CGImageMetadataSetTagWithPath to commit the changed parent object back to the metadata container."
// Without the copy of the value, changing a tag a path returned would change the container behind the
// caller's back and that warning would be a lie for this library.
static NSDictionary *charon_tag_copy(NSDictionary *tag)
{
    NSMutableDictionary *copy = [tag mutableCopy];
    id value = [tag objectForKey:@"value"];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *elements = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id element in (NSArray *)value)
            [elements addObject:isTag(element) ? charon_tag_copy((NSDictionary *)element) : element];
        [copy setObject:elements forKey:@"value"];
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        for (id key in (NSDictionary *)value) {
            id element = [(NSDictionary *)value objectForKey:key];
            [fields setObject:isTag(element) ? charon_tag_copy((NSDictionary *)element) : element forKey:key];
        }
        [copy setObject:fields forKey:@"value"];
    }
    return copy;
}

// The container a '[key]' or '.field' step addresses and the key it addresses inside it: an array with an
// index, or a structure with a name. Missing containers are made when `create` is set. It is the write
// side's view of the walk charon_step_into reads through, and it answers a container and a key rather than
// the element itself, because the caller is going to put something AT the key, not read what is there.
static BOOL charon_slot_for(id value, NSDictionary *step, BOOL create, id *outContainer, id *outKey)
{
    NSArray *fields = step[@"fields"];
    for (NSUInteger i = 0; fields && i < fields.count; i++) {
        if (![value isKindOfClass:[NSDictionary class]])
            return NO;
        NSMutableDictionary *structure = [(NSDictionary *)value mutableCopy];
        id field = [structure objectForKey:fields[i]];
        if (!field) {
            if (!create)
                return NO;
            field = charon_intermediate(@"", @"", fields[i], NO);
            [structure setObject:field forKey:fields[i]];
        }
        if (i + 1 == fields.count && !step[@"key"]) {
            *outContainer = structure;
            *outKey = fields[i];
            return YES;
        }
        value = field;
    }
    id key = step[@"key"];
    if (!key) {
        *outContainer = value;
        *outKey = nil;
        return YES;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [(NSArray *)value mutableCopy];
        if (![key isKindOfClass:[NSNumber class]])
            return NO;
        NSInteger index = [key integerValue];
        if (index < 0)
            return NO;
        while ((NSInteger)array.count <= index) {
            if (!create)
                return NO;
            [array addObject:charon_intermediate(@"", @"", [NSString stringWithFormat:@"[%lu]", (unsigned long)array.count],
                                                    YES)];
        }
        *outContainer = array;
        *outKey = key;
        return YES;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *structure = [(NSDictionary *)value mutableCopy];
        if (![structure objectForKey:key]) {
            if (!create)
                return NO;
            [structure setObject:charon_intermediate(@"", @"", key, YES) forKey:key];
        }
        *outContainer = structure;
        *outKey = key;
        return YES;
    }
    return NO;
}



// A value walked through the '[key]' and '.field' steps that follow a tag's name. With `create` the missing
// containers are made - a structure for a field, an ordered array for an index - and the value is returned
// for the caller to write the change into the tag that holds it.
static id charon_step_into(id value, NSDictionary *step, BOOL create)
{
    NSArray *fields = step[@"fields"];
    for (NSUInteger i = 0; fields && i < fields.count; i++) {
        if (![value isKindOfClass:[NSDictionary class]])
            return nil;
        NSMutableDictionary *structure = [(NSDictionary *)value mutableCopy];
        id field = [structure objectForKey:fields[i]];
        if (!field) {
            if (!create)
                return nil;
            field = charon_intermediate(@"", @"", fields[i], NO);
        }
        [structure setObject:field forKey:fields[i]];
        value = structure;
    }
    id key = step[@"key"];
    if (key) {
        if ([value isKindOfClass:[NSArray class]]) {
            NSMutableArray *array = [(NSArray *)value mutableCopy];
            NSInteger index = [key isKindOfClass:[NSNumber class]] ? [key integerValue] : -1;
            if (index < 0 || index >= (NSInteger)array.count) {
                if (!create || ![key isKindOfClass:[NSNumber class]])
                    return nil;
                [array addObject:charon_intermediate(@"", @"", [NSString stringWithFormat:@"[%ld]", (long)index], YES)];
                return [array objectAtIndex:(NSUInteger)index];
            }
            return [array objectAtIndex:(NSUInteger)index];
        }
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *structure = [(NSDictionary *)value mutableCopy];
            id field = [structure objectForKey:key];
            if (!field) {
                if (!create)
                    return nil;
                field = charon_intermediate(@"", @"", key, YES);
                [structure setObject:field forKey:key];
            }
            return field;
        }
        return nil;
    }
    return value;
}



// The tag a path names, read only. Nothing is created and a path that cannot be reached is not found.
static NSDictionary *charon_resolve(NSDictionary *metadata, NSDictionary *parent, NSArray *steps)
{
    id container = parent ? [parent objectForKey:@"value"] : [metadata objectForKey:@"tags"];
    NSString *inherited = parent ? parent[@"prefix"] : nil;
    for (NSUInteger i = 0; i < steps.count; i++) {
        NSDictionary *step = steps[i];
        NSString *prefix = step[@"prefix"] ? step[@"prefix"] : inherited;
        if (!prefix || !charon_namespace_for_prefix(metadata, prefix))
            return nil;
        if (!step[@"name"]) {
            container = charon_step_into(container, step, NO);
            if (!container)
                return nil;
            continue;
        }
        NSMutableDictionary *tag = nil;
        if ([container isKindOfClass:[NSArray class]]) {
            tag = charon_find_tag((NSArray *)container, prefix, step[@"name"]);
        } else if ([container isKindOfClass:[NSDictionary class]]) {
            // a structure's fields are keyed by name and carry a prefix of their own
            id field = [container objectForKey:step[@"name"]];
            tag = isTag(field) ? (NSMutableDictionary *)field : nil;
        } else {
            return nil;
        }
        if (!tag)
            return nil;
        inherited = tag[@"prefix"];
        if (i + 1 == steps.count && !step[@"fields"] && !step[@"key"]) {
            container = tag; // a path that only names a tag answers the tag, not the tag's value
            break;
        }
        container = charon_step_into([tag objectForKey:@"value"], step, NO);
        if (!container)
            return nil;
    }
    return isTag(container) ? container : nil;
}

// Where a path writes when a parent tag was given. The parent's value is the container its children live
// in; when the parent holds a scalar the call is what turns it into a structure, and since a parent is
// always a copy here (CGImageMetadataCopyTagWithPath and CGImageMetadataCopyTags both copy), the container
// behind it is untouched - which is what CGImageMetadata.h says happens.
static id charon_children_of(NSDictionary *parentTag)
{
    id value = [parentTag objectForKey:@"value"];
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]])
        return value;
    NSMutableDictionary *structure = [NSMutableDictionary dictionary];
    if (parentTag)
        [(NSMutableDictionary *)parentTag setObject:structure forKey:@"value"];
    return structure;
}

// The value at a path, with the rest of the path applied to it: `leaf` is the tag the caller wants there
// and `remove` asks for it to go. A step lands either in a tag's list (an NSMutableArray, the top level and
// an array's elements) or in a structure's fields (an NSMutableDictionary, which is what a parent tag's
// scalar value becomes), and both shapes are handled here rather than by asking the caller to know which
// one it has. Whatever the walk builds is written back into the tag that holds it.
static BOOL charon_apply(NSDictionary *metadata, id container, NSArray *steps, NSUInteger i, NSString *inherited,
                         NSDictionary *leaf, BOOL remove)
{
    NSDictionary *step = steps[i];
    NSString *prefix = step[@"prefix"] ? step[@"prefix"] : inherited;
    if (!prefix || !charon_namespace_for_prefix(metadata, prefix))
        return NO;
    BOOL fields = [container isKindOfClass:[NSDictionary class]];
    NSMutableArray *list = fields ? nil : (NSMutableArray *)container;
    if (!fields && ![container isKindOfClass:[NSArray class]])
        return NO;
    NSString *name = step[@"name"];
    NSMutableDictionary *found = nil;
    if (name) {
        found = fields ? (isTag([container objectForKey:name]) ? (NSMutableDictionary *)[container objectForKey:name] : nil)
                       : charon_find_tag(list, prefix, name);
    } else if (!fields) {
        return NO; // a bare [n] step names a value inside a tag, not a tag of this container
    }
    if (i + 1 == steps.count) {
        if (remove) {
            if (!found)
                return NO;
            if (fields)
                [(NSMutableDictionary *)container removeObjectForKey:name];
            else
                [list removeObjectAtIndex:(NSUInteger)[list indexOfObject:found]];
            return YES;
        }
        if (!name)
            return NO;
        if (!step[@"fields"] && !step[@"key"]) {
            NSMutableDictionary *written = [leaf mutableCopy];
            if (fields)
                [(NSMutableDictionary *)container setObject:written forKey:name];
            else if (found)
                [list replaceObjectAtIndex:(NSUInteger)[list indexOfObject:found] withObject:written];
            else
                [list addObject:written];
            return YES;
        }
        // the step addresses something inside a value: the tag that holds that value is found or made, the
        // slot inside it is found or made, and the caller's tag goes there. Writing into the tag the caller
        // handed over would throw away the array or structure already standing at the path.
        NSMutableDictionary *holder = found;
        if (!holder) {
            holder = charon_intermediate(charon_namespace_for_prefix(metadata, prefix), prefix, name,
                                         [step[@"key"] isKindOfClass:[NSString class]]);
            if (fields)
                [(NSMutableDictionary *)container setObject:holder forKey:name];
            else
                [list addObject:holder];
        }
        id inner = nil, key = nil;
        if (!charon_slot_for([holder objectForKey:@"value"], step, YES, &inner, &key))
            return NO;
        NSMutableDictionary *written = [leaf mutableCopy];
        if ([inner isKindOfClass:[NSArray class]]) {
            NSUInteger index = [key unsignedIntegerValue];
            // an element of an array is named by its position, "[0]", "[1]", wherever it came from: the
            // host's own array holds elements named that way after a path has written into one
            [written setObject:[NSString stringWithFormat:@"[%lu]", (unsigned long)index] forKey:@"name"];
            if (index < [(NSArray *)inner count])
                [(NSMutableArray *)inner replaceObjectAtIndex:index withObject:written];
            else
                [(NSMutableArray *)inner addObject:written];
        } else {
            [(NSMutableDictionary *)inner setObject:written forKey:key];
        }
        [holder setObject:inner forKey:@"value"];
        return YES;
    }
    if (!found) {
        if (!name)
            return NO;
        found = charon_intermediate(charon_namespace_for_prefix(metadata, prefix), prefix, name, NO);
        if (fields)
            [(NSMutableDictionary *)container setObject:found forKey:name];
        else
            [list addObject:found];
    }
    id value = nil, key = nil;
    if (!charon_slot_for([found objectForKey:@"value"], step, YES, &value, &key))
    if (!value || !charon_apply(metadata, value, steps, i + 1, found[@"prefix"], leaf, remove))
        return NO;
    return YES;
}

CGImageMetadataTagRef CGImageMetadataCopyTagWithPath(CGImageMetadataRef metadata, CGImageMetadataTagRef parent,
                                                     CFStringRef path)
{
    NSDictionary *held = charon_metadata(metadata);
    NSDictionary *parentTag = parent ? charon_tag(parent) : nil;
    if (!held || (parent && !parentTag) || !path)
        return NULL;
    NSDictionary *found = charon_resolve(held, parentTag, charon_steps((__bridge NSString *)path));
    if (!found)
        return NULL;
    return (__bridge_retained CGImageMetadataTagRef)charon_tag_copy(found);
}

CFStringRef CGImageMetadataCopyStringValueWithPath(CGImageMetadataRef metadata, CGImageMetadataTagRef parent,
                                                   CFStringRef path)
{
    CGImageMetadataTagRef tag = CGImageMetadataCopyTagWithPath(metadata, parent, path);
    if (!tag)
        return NULL;
    id value = (__bridge_transfer id)CGImageMetadataTagCopyValue(tag);
    CFRelease(tag);
    if (![value isKindOfClass:[NSString class]])
        return NULL; // the value at this path, when the tag there holds a string
    return CFRetain((__bridge CFStringRef)value);
}

bool CGImageMetadataRegisterNamespaceForPrefix(CGMutableImageMetadataRef metadata, CFStringRef xmlns, CFStringRef prefix,
                                               CFErrorRef *err)
{
    NSMutableDictionary *held = charon_is_metadata(metadata) ? (NSMutableDictionary *)charon_metadata(metadata) : nil;
    if (!held || !xmlns || !prefix)
        return false;
    NSMutableDictionary *registered = [held objectForKey:@"prefixes"];
    // registering a prefix that already names another namespace is a re-registration, not a refusal: the
    // host answers true and hands back no error (measured 2026-09-30, "register conflict"), and the caller
    // asked for this prefix to name this namespace.
    if (err)
        *err = NULL;
    [registered setObject:(__bridge id)xmlns forKey:(__bridge id)prefix];
    return true;
}

bool CGImageMetadataSetTagWithPath(CGMutableImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path,
                                   CGImageMetadataTagRef tag)
{
    NSDictionary *held = charon_is_metadata(metadata) ? charon_metadata(metadata) : nil;
    NSDictionary *parentTag = parent ? charon_tag(parent) : nil;
    NSDictionary *heldTag = tag ? charon_tag(tag) : nil;
    if (!held || !path || !heldTag || (parent && !parentTag))
        return false;
    id container = parentTag ? charon_children_of(parentTag) : [held objectForKey:@"tags"];
    return charon_apply(held, container, charon_steps((__bridge NSString *)path), 0,
                        parentTag ? parentTag[@"prefix"] : nil, heldTag, NO);
}

bool CGImageMetadataSetValueWithPath(CGMutableImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path,
                                     CFTypeRef value)
{
    NSDictionary *held = charon_is_metadata(metadata) ? charon_metadata(metadata) : nil;
    NSDictionary *parentTag = parent ? charon_tag(parent) : nil;
    if (!held || (parent && !parentTag) || !path || !value)
        return false;
    // "The same value restrictions apply as in CGImageMetadataTagCreate", and a path carries a value and not
    // a type, so the type is read off the CFType of the value as kCGImageMetadataTypeDefault does.
    NSArray *steps = charon_steps((__bridge NSString *)path);
    NSDictionary *last = steps.lastObject;
    NSDictionary *first = steps.firstObject;
    if (!last[@"name"])
        return false;
    NSString *prefix = last[@"prefix"] ? last[@"prefix"] : first[@"prefix"];
    if (!prefix && steps.count == 1)
        prefix = parentTag ? parentTag[@"prefix"] : nil; // "inherited from the nearest parent tag"
    NSString *ns = prefix ? charon_namespace_for_prefix(held, prefix) : nil;
    if (!ns)
        return false;
    CGImageMetadataTagRef made = CGImageMetadataTagCreate((__bridge CFStringRef)ns, (__bridge CFStringRef)prefix,
                                                          (__bridge CFStringRef)last[@"name"], kCGImageMetadataTypeDefault,
                                                          value);
    if (!made)
        return false;
    id container = parentTag ? charon_children_of(parentTag) : [held objectForKey:@"tags"];
    BOOL ok = charon_apply(held, container, steps, 0, parentTag ? parentTag[@"prefix"] : nil, charon_tag(made), NO);
    CFRelease(made);
    return ok;
}

bool CGImageMetadataRemoveTagWithPath(CGMutableImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path)
{
    NSDictionary *held = charon_is_metadata(metadata) ? charon_metadata(metadata) : nil;
    NSDictionary *parentTag = parent ? charon_tag(parent) : nil;
    if (!held || (parent && !parentTag) || !path)
        return false;
    id container = parentTag ? charon_children_of(parentTag) : [held objectForKey:@"tags"];
    return charon_apply(held, container, charon_steps((__bridge NSString *)path), 0,
                        parentTag ? parentTag[@"prefix"] : nil, nil, YES);
}

void CGImageMetadataEnumerateTagsUsingBlock(CGImageMetadataRef metadata, CFStringRef rootPath, CFDictionaryRef options,
                                            CGImageMetadataTagBlock block)
{
    NSDictionary *held = charon_metadata(metadata);
    if (!held || !block)
        return;
    NSArray *steps = rootPath ? charon_steps((__bridge NSString *)rootPath) : nil;
    NSArray *tags = (NSArray *)[held objectForKey:@"tags"];
    if (steps.count) {
        NSDictionary *root = charon_resolve(held, nil, steps);
        if (!root)
            return;
        tags = [root objectForKey:@"value"];
    }
    if (![tags isKindOfClass:[NSArray class]])
        return;
    // "Currently the only supported option is kCGImageMetadataEnumerateRecursively, which should be set to a
    // CFBoolean. The default is non-recursive."
    BOOL recursive = options
        ? [[(__bridge NSDictionary *)options objectForKey:(__bridge id)kCGImageMetadataEnumerateRecursively] boolValue]
        : NO;
    for (id heldTag in tags) {
        if (!isTag(heldTag))
            continue;
        NSDictionary *tag = (NSDictionary *)heldTag;
        NSString *path = [NSString stringWithFormat:@"%@:%@", tag[@"prefix"], tag[@"name"]];
        if (!block((__bridge CFStringRef)path, (__bridge CGImageMetadataTagRef)charon_tag_copy(tag)))
            return;
        if (!recursive)
            continue;
        id value = [tag objectForKey:@"value"];
        NSArray *children = nil;
        if ([value isKindOfClass:[NSArray class]]) {
            children = (NSArray *)value;
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            NSMutableArray *fields = [NSMutableArray array];
            for (id key in [[(NSDictionary *)value allKeys] sortedArrayUsingSelector:@selector(compare:)])
                [fields addObject:[(NSDictionary *)value objectForKey:key]];
            children = fields;
        }
        for (id child in children) {
            if (!isTag(child))
                continue;
            NSDictionary *element = (NSDictionary *)child;
            BOOL isStructure = [value isKindOfClass:[NSDictionary class]];
            NSString *childPath =
                isStructure ? [NSString stringWithFormat:@"%@:%@.%@", tag[@"prefix"], tag[@"name"], element[@"name"]]
                            : [NSString stringWithFormat:@"%@:%@%@", tag[@"prefix"], tag[@"name"], element[@"name"]];
            if (!block((__bridge CFStringRef)childPath, (__bridge CGImageMetadataTagRef)charon_tag_copy(element)))
                return;
        }
    }
}
