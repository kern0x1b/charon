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

// MARK: - the image-property bridge
//
// CGImageMetadata.h:520-580 says what these two functions are, and the sentence that matters is
// "Metadata Working Group guidance is factored into the mapping of CGImageProperties to XMP compatible
// CGImageMetadataTags. For example, kCGImagePropertyExifDateTimeOriginal will get the value of the
// corresponding XMP tag, which is photoshop:DateCreated", and then "Not all dictionaries and properties are
// supported at this time."
//
// So neither function is a search over the names in the tree: both are ONE LOOKUP in the table below, from
// the (dictionary, property) pair to the (namespace, prefix, name) of the XMP tag, and then this file's own
// path machinery. The lookup matches a tag by its namespace and its name, and only in the top level of the
// tree; both of those are measured, and the harness prints the cases that measure them next to the
// answers (tests/backports/host/imageio-metadata/run.sh, cases "namespace", "nested", "own-name").
//
// THE TABLE IS MEASURED, NOT TRANSCRIBED. tools/corpus/gen-imageio-property-map.py asks the host's own
// CGImageMetadataSetValueMatchingImageProperty to write a value for each of the 518 (dictionary, property)
// pairs the SDK's own CGImageProperties.h declares, one process per pair, and reads the tag it wrote back
// out of the tree: the row IS what the host answered. 357 pairs map and 161 do not, which is the header's
// own sentence about a partial table (every JFIF, GIF, HEICS, WebP, TGA and DNG property is among the 161,
// and so are 25 of IPTC's). No rule of thumb produced these: 12 of them are dc:* and 7 are xmp:* out of the
// same TIFF and IPTC dictionaries, kCGImagePropertyExifDateTimeOriginal is photoshop:DateCreated while
// kCGImagePropertyExifDateTimeDigitized is exif:DateTimeDigitized, and kCGImagePropertyExifLensSerialNumber
// is exifEX:LensSerialNumber while kCGImagePropertyExifAuxLensSerialNumber is aux:LensSerialNumber - the
// same name in two namespaces, which is why the namespace is part of the match and not only the name.
//
// The five strings of a row are the ones the measurement printed, not constants this file spells: the
// caller passes a dictionary name and a property name it got from somewhere else, and every one of the
// five is compared as text. The longest of them is 43 characters (a namespace URI), so the buffers below
// hold any of the table's own strings and a tag whose namespace or name does not fit in one cannot be a
// row of this table - which is why failing to convert is not a match and not a crash.

// 357 rows, in the header's order: the pairs as they are declared, with the pairs the host does not map
// left out. Regenerate the block with the command in tools/corpus/gen-imageio-property-map.py's docstring;
// the harness below compares all 518 answers, so a row that drifts shows there and not only here.
#define CHARON_PROPERTY_ROWS 357
static const char *const charon_property_rows[CHARON_PROPERTY_ROWS][5] = {
    { "{TIFF}", "Compression",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "Compression" },  // kCGImagePropertyTIFFCompression
    { "{TIFF}", "PhotometricInterpretation",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "PhotometricInterpretation" },  // kCGImagePropertyTIFFPhotometricInterpretation
    { "{TIFF}", "DocumentName",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "DocumentName" },  // kCGImagePropertyTIFFDocumentName
    { "{TIFF}", "ImageDescription",
      "http://purl.org/dc/elements/1.1/", "dc", "description" },  // kCGImagePropertyTIFFImageDescription
    { "{TIFF}", "Make",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "Make" },  // kCGImagePropertyTIFFMake
    { "{TIFF}", "Model",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "Model" },  // kCGImagePropertyTIFFModel
    { "{TIFF}", "Orientation",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "Orientation" },  // kCGImagePropertyTIFFOrientation
    { "{TIFF}", "XResolution",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "XResolution" },  // kCGImagePropertyTIFFXResolution
    { "{TIFF}", "YResolution",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "YResolution" },  // kCGImagePropertyTIFFYResolution
    { "{TIFF}", "ResolutionUnit",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "ResolutionUnit" },  // kCGImagePropertyTIFFResolutionUnit
    { "{TIFF}", "Software",
      "http://ns.adobe.com/xap/1.0/", "xmp", "CreatorTool" },  // kCGImagePropertyTIFFSoftware
    { "{TIFF}", "TransferFunction",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "TransferFunction" },  // kCGImagePropertyTIFFTransferFunction
    { "{TIFF}", "DateTime",
      "http://ns.adobe.com/xap/1.0/", "xmp", "ModifyDate" },  // kCGImagePropertyTIFFDateTime
    { "{TIFF}", "Artist",
      "http://purl.org/dc/elements/1.1/", "dc", "creator" },  // kCGImagePropertyTIFFArtist
    { "{TIFF}", "HostComputer",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "HostComputer" },  // kCGImagePropertyTIFFHostComputer
    { "{TIFF}", "Copyright",
      "http://purl.org/dc/elements/1.1/", "dc", "rights" },  // kCGImagePropertyTIFFCopyright
    { "{TIFF}", "WhitePoint",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "WhitePoint" },  // kCGImagePropertyTIFFWhitePoint
    { "{TIFF}", "PrimaryChromaticities",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "PrimaryChromaticities" },  // kCGImagePropertyTIFFPrimaryChromaticities
    { "{TIFF}", "TileWidth",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "TileWidth" },  // kCGImagePropertyTIFFTileWidth
    { "{TIFF}", "TileLength",
      "http://ns.adobe.com/tiff/1.0/", "tiff", "TileLength" },  // kCGImagePropertyTIFFTileLength
    { "{Exif}", "ExposureTime",
      "http://ns.adobe.com/exif/1.0/", "exif", "ExposureTime" },  // kCGImagePropertyExifExposureTime
    { "{Exif}", "FNumber",
      "http://ns.adobe.com/exif/1.0/", "exif", "FNumber" },  // kCGImagePropertyExifFNumber
    { "{Exif}", "ExposureProgram",
      "http://ns.adobe.com/exif/1.0/", "exif", "ExposureProgram" },  // kCGImagePropertyExifExposureProgram
    { "{Exif}", "SpectralSensitivity",
      "http://ns.adobe.com/exif/1.0/", "exif", "SpectralSensitivity" },  // kCGImagePropertyExifSpectralSensitivity
    { "{Exif}", "ISOSpeedRatings",
      "http://ns.adobe.com/exif/1.0/", "exif", "ISOSpeedRatings" },  // kCGImagePropertyExifISOSpeedRatings
    { "{Exif}", "OECF",
      "http://ns.adobe.com/exif/1.0/", "exif", "OECF" },  // kCGImagePropertyExifOECF
    { "{Exif}", "SensitivityType",
      "http://cipa.jp/exif/1.0/", "exifEX", "SensitivityType" },  // kCGImagePropertyExifSensitivityType
    { "{Exif}", "StandardOutputSensitivity",
      "http://cipa.jp/exif/1.0/", "exifEX", "StandardOutputSensitivity" },  // kCGImagePropertyExifStandardOutputSensitivity
    { "{Exif}", "RecommendedExposureIndex",
      "http://cipa.jp/exif/1.0/", "exifEX", "RecommendedExposureIndex" },  // kCGImagePropertyExifRecommendedExposureIndex
    { "{Exif}", "ISOSpeed",
      "http://cipa.jp/exif/1.0/", "exifEX", "ISOSpeed" },  // kCGImagePropertyExifISOSpeed
    { "{Exif}", "ISOSpeedLatitudeyyy",
      "http://cipa.jp/exif/1.0/", "exifEX", "ISOSpeedLatitudeyyy" },  // kCGImagePropertyExifISOSpeedLatitudeyyy
    { "{Exif}", "ISOSpeedLatitudezzz",
      "http://cipa.jp/exif/1.0/", "exifEX", "ISOSpeedLatitudezzz" },  // kCGImagePropertyExifISOSpeedLatitudezzz
    { "{Exif}", "ExifVersion",
      "http://ns.adobe.com/exif/1.0/", "exif", "ExifVersion" },  // kCGImagePropertyExifVersion
    { "{Exif}", "DateTimeOriginal",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "DateCreated" },  // kCGImagePropertyExifDateTimeOriginal
    { "{Exif}", "DateTimeDigitized",
      "http://ns.adobe.com/xap/1.0/", "xmp", "CreateDate" },  // kCGImagePropertyExifDateTimeDigitized
    { "{Exif}", "OffsetTime",
      "http://ns.adobe.com/exif/1.0/", "exif", "OffsetTime" },  // kCGImagePropertyExifOffsetTime
    { "{Exif}", "OffsetTimeOriginal",
      "http://ns.adobe.com/exif/1.0/", "exif", "OffsetTimeOriginal" },  // kCGImagePropertyExifOffsetTimeOriginal
    { "{Exif}", "OffsetTimeDigitized",
      "http://ns.adobe.com/exif/1.0/", "exif", "OffsetTimeDigitized" },  // kCGImagePropertyExifOffsetTimeDigitized
    { "{Exif}", "ComponentsConfiguration",
      "http://ns.adobe.com/exif/1.0/", "exif", "ComponentsConfiguration" },  // kCGImagePropertyExifComponentsConfiguration
    { "{Exif}", "CompressedBitsPerPixel",
      "http://ns.adobe.com/exif/1.0/", "exif", "CompressedBitsPerPixel" },  // kCGImagePropertyExifCompressedBitsPerPixel
    { "{Exif}", "ShutterSpeedValue",
      "http://ns.adobe.com/exif/1.0/", "exif", "ShutterSpeedValue" },  // kCGImagePropertyExifShutterSpeedValue
    { "{Exif}", "ApertureValue",
      "http://ns.adobe.com/exif/1.0/", "exif", "ApertureValue" },  // kCGImagePropertyExifApertureValue
    { "{Exif}", "BrightnessValue",
      "http://ns.adobe.com/exif/1.0/", "exif", "BrightnessValue" },  // kCGImagePropertyExifBrightnessValue
    { "{Exif}", "ExposureBiasValue",
      "http://ns.adobe.com/exif/1.0/", "exif", "ExposureBiasValue" },  // kCGImagePropertyExifExposureBiasValue
    { "{Exif}", "MaxApertureValue",
      "http://ns.adobe.com/exif/1.0/", "exif", "MaxApertureValue" },  // kCGImagePropertyExifMaxApertureValue
    { "{Exif}", "SubjectDistance",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubjectDistance" },  // kCGImagePropertyExifSubjectDistance
    { "{Exif}", "MeteringMode",
      "http://ns.adobe.com/exif/1.0/", "exif", "MeteringMode" },  // kCGImagePropertyExifMeteringMode
    { "{Exif}", "LightSource",
      "http://ns.adobe.com/exif/1.0/", "exif", "LightSource" },  // kCGImagePropertyExifLightSource
    { "{Exif}", "Flash",
      "http://ns.adobe.com/exif/1.0/", "exif", "Flash" },  // kCGImagePropertyExifFlash
    { "{Exif}", "FocalLength",
      "http://ns.adobe.com/exif/1.0/", "exif", "FocalLength" },  // kCGImagePropertyExifFocalLength
    { "{Exif}", "SubjectArea",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubjectArea" },  // kCGImagePropertyExifSubjectArea
    { "{Exif}", "MakerNote",
      "http://ns.adobe.com/exif/1.0/", "exif", "MakerNote" },  // kCGImagePropertyExifMakerNote
    { "{Exif}", "UserComment",
      "http://ns.adobe.com/exif/1.0/", "exif", "UserComment" },  // kCGImagePropertyExifUserComment
    { "{Exif}", "SubsecTime",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubsecTime" },  // kCGImagePropertyExifSubsecTime
    { "{Exif}", "SubsecTimeOriginal",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubsecTimeOriginal" },  // kCGImagePropertyExifSubsecTimeOriginal
    { "{Exif}", "SubsecTimeDigitized",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubsecTimeDigitized" },  // kCGImagePropertyExifSubsecTimeDigitized
    { "{Exif}", "FlashPixVersion",
      "http://ns.adobe.com/exif/1.0/", "exif", "FlashPixVersion" },  // kCGImagePropertyExifFlashPixVersion
    { "{Exif}", "ColorSpace",
      "http://ns.adobe.com/exif/1.0/", "exif", "ColorSpace" },  // kCGImagePropertyExifColorSpace
    { "{Exif}", "PixelXDimension",
      "http://ns.adobe.com/exif/1.0/", "exif", "PixelXDimension" },  // kCGImagePropertyExifPixelXDimension
    { "{Exif}", "PixelYDimension",
      "http://ns.adobe.com/exif/1.0/", "exif", "PixelYDimension" },  // kCGImagePropertyExifPixelYDimension
    { "{Exif}", "RelatedSoundFile",
      "http://ns.adobe.com/exif/1.0/", "exif", "RelatedSoundFile" },  // kCGImagePropertyExifRelatedSoundFile
    { "{Exif}", "FlashEnergy",
      "http://ns.adobe.com/exif/1.0/", "exif", "FlashEnergy" },  // kCGImagePropertyExifFlashEnergy
    { "{Exif}", "SpatialFrequencyResponse",
      "http://ns.adobe.com/exif/1.0/", "exif", "SpatialFrequencyResponse" },  // kCGImagePropertyExifSpatialFrequencyResponse
    { "{Exif}", "FocalPlaneXResolution",
      "http://ns.adobe.com/exif/1.0/", "exif", "FocalPlaneXResolution" },  // kCGImagePropertyExifFocalPlaneXResolution
    { "{Exif}", "FocalPlaneYResolution",
      "http://ns.adobe.com/exif/1.0/", "exif", "FocalPlaneYResolution" },  // kCGImagePropertyExifFocalPlaneYResolution
    { "{Exif}", "FocalPlaneResolutionUnit",
      "http://ns.adobe.com/exif/1.0/", "exif", "FocalPlaneResolutionUnit" },  // kCGImagePropertyExifFocalPlaneResolutionUnit
    { "{Exif}", "SubjectLocation",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubjectLocation" },  // kCGImagePropertyExifSubjectLocation
    { "{Exif}", "ExposureIndex",
      "http://ns.adobe.com/exif/1.0/", "exif", "ExposureIndex" },  // kCGImagePropertyExifExposureIndex
    { "{Exif}", "SensingMethod",
      "http://ns.adobe.com/exif/1.0/", "exif", "SensingMethod" },  // kCGImagePropertyExifSensingMethod
    { "{Exif}", "FileSource",
      "http://ns.adobe.com/exif/1.0/", "exif", "FileSource" },  // kCGImagePropertyExifFileSource
    { "{Exif}", "SceneType",
      "http://ns.adobe.com/exif/1.0/", "exif", "SceneType" },  // kCGImagePropertyExifSceneType
    { "{Exif}", "CFAPattern",
      "http://ns.adobe.com/exif/1.0/", "exif", "CFAPattern" },  // kCGImagePropertyExifCFAPattern
    { "{Exif}", "CustomRendered",
      "http://ns.adobe.com/exif/1.0/", "exif", "CustomRendered" },  // kCGImagePropertyExifCustomRendered
    { "{Exif}", "ExposureMode",
      "http://ns.adobe.com/exif/1.0/", "exif", "ExposureMode" },  // kCGImagePropertyExifExposureMode
    { "{Exif}", "WhiteBalance",
      "http://ns.adobe.com/exif/1.0/", "exif", "WhiteBalance" },  // kCGImagePropertyExifWhiteBalance
    { "{Exif}", "DigitalZoomRatio",
      "http://ns.adobe.com/exif/1.0/", "exif", "DigitalZoomRatio" },  // kCGImagePropertyExifDigitalZoomRatio
    { "{Exif}", "FocalLenIn35mmFilm",
      "http://ns.adobe.com/exif/1.0/", "exif", "FocalLenIn35mmFilm" },  // kCGImagePropertyExifFocalLenIn35mmFilm
    { "{Exif}", "SceneCaptureType",
      "http://ns.adobe.com/exif/1.0/", "exif", "SceneCaptureType" },  // kCGImagePropertyExifSceneCaptureType
    { "{Exif}", "GainControl",
      "http://ns.adobe.com/exif/1.0/", "exif", "GainControl" },  // kCGImagePropertyExifGainControl
    { "{Exif}", "Contrast",
      "http://ns.adobe.com/exif/1.0/", "exif", "Contrast" },  // kCGImagePropertyExifContrast
    { "{Exif}", "Saturation",
      "http://ns.adobe.com/exif/1.0/", "exif", "Saturation" },  // kCGImagePropertyExifSaturation
    { "{Exif}", "Sharpness",
      "http://ns.adobe.com/exif/1.0/", "exif", "Sharpness" },  // kCGImagePropertyExifSharpness
    { "{Exif}", "DeviceSettingDescription",
      "http://ns.adobe.com/exif/1.0/", "exif", "DeviceSettingDescription" },  // kCGImagePropertyExifDeviceSettingDescription
    { "{Exif}", "SubjectDistRange",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubjectDistRange" },  // kCGImagePropertyExifSubjectDistRange
    { "{Exif}", "ImageUniqueID",
      "http://ns.adobe.com/exif/1.0/", "exif", "ImageUniqueID" },  // kCGImagePropertyExifImageUniqueID
    { "{Exif}", "CameraOwnerName",
      "http://cipa.jp/exif/1.0/", "exifEX", "CameraOwnerName" },  // kCGImagePropertyExifCameraOwnerName
    { "{Exif}", "BodySerialNumber",
      "http://cipa.jp/exif/1.0/", "exifEX", "BodySerialNumber" },  // kCGImagePropertyExifBodySerialNumber
    { "{Exif}", "LensSpecification",
      "http://cipa.jp/exif/1.0/", "exifEX", "LensSpecification" },  // kCGImagePropertyExifLensSpecification
    { "{Exif}", "LensMake",
      "http://cipa.jp/exif/1.0/", "exifEX", "LensMake" },  // kCGImagePropertyExifLensMake
    { "{Exif}", "LensModel",
      "http://cipa.jp/exif/1.0/", "exifEX", "LensModel" },  // kCGImagePropertyExifLensModel
    { "{Exif}", "LensSerialNumber",
      "http://cipa.jp/exif/1.0/", "exifEX", "LensSerialNumber" },  // kCGImagePropertyExifLensSerialNumber
    { "{Exif}", "Gamma",
      "http://cipa.jp/exif/1.0/", "exifEX", "Gamma" },  // kCGImagePropertyExifGamma
    { "{Exif}", "CompositeImage",
      "http://ns.adobe.com/exif/1.0/", "exif", "CompositeImage" },  // kCGImagePropertyExifCompositeImage
    { "{Exif}", "SourceImageNumberOfCompositeImage",
      "http://ns.adobe.com/exif/1.0/", "exif", "SourceImageNumberOfCompositeImage" },  // kCGImagePropertyExifSourceImageNumberOfCompositeImage
    { "{Exif}", "SourceExposureTimesOfCompositeImage",
      "http://ns.adobe.com/exif/1.0/", "exif", "SourceExposureTimesOfCompositeImage" },  // kCGImagePropertyExifSourceExposureTimesOfCompositeImage
    { "{Exif}", "SubsecTimeOriginal",
      "http://ns.adobe.com/exif/1.0/", "exif", "SubsecTimeOriginal" },  // kCGImagePropertyExifSubsecTimeOrginal
    { "{ExifAux}", "LensInfo",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "LensInfo" },  // kCGImagePropertyExifAuxLensInfo
    { "{ExifAux}", "LensModel",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "Lens" },  // kCGImagePropertyExifAuxLensModel
    { "{ExifAux}", "SerialNumber",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "SerialNumber" },  // kCGImagePropertyExifAuxSerialNumber
    { "{ExifAux}", "LensID",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "LensID" },  // kCGImagePropertyExifAuxLensID
    { "{ExifAux}", "LensSerialNumber",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "LensSerialNumber" },  // kCGImagePropertyExifAuxLensSerialNumber
    { "{ExifAux}", "ImageNumber",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "ImageNumber" },  // kCGImagePropertyExifAuxImageNumber
    { "{ExifAux}", "FlashCompensation",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "FlashCompensation" },  // kCGImagePropertyExifAuxFlashCompensation
    { "{ExifAux}", "OwnerName",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "OwnerName" },  // kCGImagePropertyExifAuxOwnerName
    { "{ExifAux}", "Firmware",
      "http://ns.adobe.com/exif/1.0/aux/", "aux", "Firmware" },  // kCGImagePropertyExifAuxFirmware
    { "{PNG}", "Author",
      "http://purl.org/dc/elements/1.1/", "dc", "creator" },  // kCGImagePropertyPNGAuthor
    { "{PNG}", "Comment",
      "http://ns.adobe.com/exif/1.0/", "exif", "UserComment" },  // kCGImagePropertyPNGComment
    { "{PNG}", "Copyright",
      "http://purl.org/dc/elements/1.1/", "dc", "rights" },  // kCGImagePropertyPNGCopyright
    { "{PNG}", "Description",
      "http://purl.org/dc/elements/1.1/", "dc", "description" },  // kCGImagePropertyPNGDescription
    { "{PNG}", "Software",
      "http://ns.adobe.com/xap/1.0/", "xmp", "CreatorTool" },  // kCGImagePropertyPNGSoftware
    { "{PNG}", "Title",
      "http://purl.org/dc/elements/1.1/", "dc", "title" },  // kCGImagePropertyPNGTitle
    { "{GPS}", "GPSVersion",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSVersionID" },  // kCGImagePropertyGPSVersion
    { "{GPS}", "LatitudeRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSLatitudeRef" },  // kCGImagePropertyGPSLatitudeRef
    { "{GPS}", "Latitude",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSLatitude" },  // kCGImagePropertyGPSLatitude
    { "{GPS}", "LongitudeRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSLongitudeRef" },  // kCGImagePropertyGPSLongitudeRef
    { "{GPS}", "Longitude",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSLongitude" },  // kCGImagePropertyGPSLongitude
    { "{GPS}", "AltitudeRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSAltitudeRef" },  // kCGImagePropertyGPSAltitudeRef
    { "{GPS}", "Altitude",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSAltitude" },  // kCGImagePropertyGPSAltitude
    { "{GPS}", "TimeStamp",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSTimeStamp" },  // kCGImagePropertyGPSTimeStamp
    { "{GPS}", "Satellites",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSSatellites" },  // kCGImagePropertyGPSSatellites
    { "{GPS}", "Status",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSStatus" },  // kCGImagePropertyGPSStatus
    { "{GPS}", "MeasureMode",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSMeasureMode" },  // kCGImagePropertyGPSMeasureMode
    { "{GPS}", "DOP",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDOP" },  // kCGImagePropertyGPSDOP
    { "{GPS}", "SpeedRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSSpeedRef" },  // kCGImagePropertyGPSSpeedRef
    { "{GPS}", "Speed",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSSpeed" },  // kCGImagePropertyGPSSpeed
    { "{GPS}", "TrackRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSTrackRef" },  // kCGImagePropertyGPSTrackRef
    { "{GPS}", "Track",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSTrack" },  // kCGImagePropertyGPSTrack
    { "{GPS}", "ImgDirectionRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSImgDirectionRef" },  // kCGImagePropertyGPSImgDirectionRef
    { "{GPS}", "ImgDirection",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSImgDirection" },  // kCGImagePropertyGPSImgDirection
    { "{GPS}", "MapDatum",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSMapDatum" },  // kCGImagePropertyGPSMapDatum
    { "{GPS}", "DestLatitudeRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestLatitudeRef" },  // kCGImagePropertyGPSDestLatitudeRef
    { "{GPS}", "DestLatitude",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestLatitude" },  // kCGImagePropertyGPSDestLatitude
    { "{GPS}", "DestLongitudeRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestLongitudeRef" },  // kCGImagePropertyGPSDestLongitudeRef
    { "{GPS}", "DestLongitude",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestLongitude" },  // kCGImagePropertyGPSDestLongitude
    { "{GPS}", "DestBearingRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestBearingRef" },  // kCGImagePropertyGPSDestBearingRef
    { "{GPS}", "DestBearing",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestBearing" },  // kCGImagePropertyGPSDestBearing
    { "{GPS}", "DestDistanceRef",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestDistanceRef" },  // kCGImagePropertyGPSDestDistanceRef
    { "{GPS}", "DestDistance",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDestDistance" },  // kCGImagePropertyGPSDestDistance
    { "{GPS}", "ProcessingMethod",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSProcessingMethod" },  // kCGImagePropertyGPSProcessingMethod
    { "{GPS}", "AreaInformation",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSAreaInformation" },  // kCGImagePropertyGPSAreaInformation
    { "{GPS}", "DateStamp",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSTimeStamp" },  // kCGImagePropertyGPSDateStamp
    { "{GPS}", "Differential",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSDifferential" },  // kCGImagePropertyGPSDifferental
    { "{GPS}", "HPositioningError",
      "http://ns.adobe.com/exif/1.0/", "exif", "GPSHPositioningError" },  // kCGImagePropertyGPSHPositioningError
    { "{IPTC}", "ObjectTypeReference",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-003" },  // kCGImagePropertyIPTCObjectTypeReference
    { "{IPTC}", "ObjectAttributeReference",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IntellectualGenre" },  // kCGImagePropertyIPTCObjectAttributeReference
    { "{IPTC}", "ObjectName",
      "http://purl.org/dc/elements/1.1/", "dc", "title" },  // kCGImagePropertyIPTCObjectName
    { "{IPTC}", "EditStatus",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-007" },  // kCGImagePropertyIPTCEditStatus
    { "{IPTC}", "Urgency",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Urgency" },  // kCGImagePropertyIPTCUrgency
    { "{IPTC}", "SubjectReference",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "SubjectCode" },  // kCGImagePropertyIPTCSubjectReference
    { "{IPTC}", "Category",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Category" },  // kCGImagePropertyIPTCCategory
    { "{IPTC}", "SupplementalCategory",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "SupplementalCategories" },  // kCGImagePropertyIPTCSupplementalCategory
    { "{IPTC}", "FixtureIdentifier",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-022" },  // kCGImagePropertyIPTCFixtureIdentifier
    { "{IPTC}", "Keywords",
      "http://purl.org/dc/elements/1.1/", "dc", "subject" },  // kCGImagePropertyIPTCKeywords
    { "{IPTC}", "ContentLocationCode",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-026" },  // kCGImagePropertyIPTCContentLocationCode
    { "{IPTC}", "ContentLocationName",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-027" },  // kCGImagePropertyIPTCContentLocationName
    { "{IPTC}", "SpecialInstructions",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Instructions" },  // kCGImagePropertyIPTCSpecialInstructions
    { "{IPTC}", "ActionAdvised",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-042" },  // kCGImagePropertyIPTCActionAdvised
    { "{IPTC}", "ReferenceService",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-045" },  // kCGImagePropertyIPTCReferenceService
    { "{IPTC}", "ReferenceDate",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-047" },  // kCGImagePropertyIPTCReferenceDate
    { "{IPTC}", "ReferenceNumber",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-050" },  // kCGImagePropertyIPTCReferenceNumber
    { "{IPTC}", "DateCreated",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "DateCreated" },  // kCGImagePropertyIPTCDateCreated
    { "{IPTC}", "TimeCreated",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "DateCreated" },  // kCGImagePropertyIPTCTimeCreated
    { "{IPTC}", "DigitalCreationDate",
      "http://ns.adobe.com/xap/1.0/", "xmp", "CreateDate" },  // kCGImagePropertyIPTCDigitalCreationDate
    { "{IPTC}", "DigitalCreationTime",
      "http://ns.adobe.com/xap/1.0/", "xmp", "CreateDate" },  // kCGImagePropertyIPTCDigitalCreationTime
    { "{IPTC}", "OriginatingProgram",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-065" },  // kCGImagePropertyIPTCOriginatingProgram
    { "{IPTC}", "ProgramVersion",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-070" },  // kCGImagePropertyIPTCProgramVersion
    { "{IPTC}", "Byline",
      "http://purl.org/dc/elements/1.1/", "dc", "creator" },  // kCGImagePropertyIPTCByline
    { "{IPTC}", "BylineTitle",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "AuthorsPosition" },  // kCGImagePropertyIPTCBylineTitle
    { "{IPTC}", "City",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "City" },  // kCGImagePropertyIPTCCity
    { "{IPTC}", "SubLocation",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "Location" },  // kCGImagePropertyIPTCSubLocation
    { "{IPTC}", "Province/State",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "State" },  // kCGImagePropertyIPTCProvinceState
    { "{IPTC}", "Country/PrimaryLocationCode",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "CountryCode" },  // kCGImagePropertyIPTCCountryPrimaryLocationCode
    { "{IPTC}", "Country/PrimaryLocationName",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Country" },  // kCGImagePropertyIPTCCountryPrimaryLocationName
    { "{IPTC}", "OriginalTransmissionReference",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "TransmissionReference" },  // kCGImagePropertyIPTCOriginalTransmissionReference
    { "{IPTC}", "Headline",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Headline" },  // kCGImagePropertyIPTCHeadline
    { "{IPTC}", "Credit",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Credit" },  // kCGImagePropertyIPTCCredit
    { "{IPTC}", "Source",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Source" },  // kCGImagePropertyIPTCSource
    { "{IPTC}", "CopyrightNotice",
      "http://purl.org/dc/elements/1.1/", "dc", "rights" },  // kCGImagePropertyIPTCCopyrightNotice
    { "{IPTC}", "Contact",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "Contact" },  // kCGImagePropertyIPTCContact
    { "{IPTC}", "Caption/Abstract",
      "http://purl.org/dc/elements/1.1/", "dc", "description" },  // kCGImagePropertyIPTCCaptionAbstract
    { "{IPTC}", "Writer/Editor",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "CaptionWriter" },  // kCGImagePropertyIPTCWriterEditor
    { "{IPTC}", "ImageType",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-130" },  // kCGImagePropertyIPTCImageType
    { "{IPTC}", "ImageOrientation",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-131" },  // kCGImagePropertyIPTCImageOrientation
    { "{IPTC}", "LanguageIdentifier",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "IIM2-135" },  // kCGImagePropertyIPTCLanguageIdentifier
    { "{IPTC}", "StarRating",
      "http://ns.adobe.com/xap/1.0/", "xmp", "Rating" },  // kCGImagePropertyIPTCStarRating
    { "{IPTC}", "CreatorContactInfo",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "CreatorContactInfo" },  // kCGImagePropertyIPTCCreatorContactInfo
    { "{IPTC}", "UsageTerms",
      "http://ns.adobe.com/xap/1.0/rights/", "xmpRights", "UsageTerms" },  // kCGImagePropertyIPTCRightsUsageTerms
    { "{IPTC}", "Scene",
      "http://iptc.org/std/Iptc4xmpCore/1.0/xmlns/", "Iptc4xmpCore", "Scene" },  // kCGImagePropertyIPTCScene
    { "{IPTC}", "AboutCvTerm",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "AboutCvTerm" },  // kCGImagePropertyIPTCExtAboutCvTerm
    { "{IPTC}", "AboutCvTermCvId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvId" },  // kCGImagePropertyIPTCExtAboutCvTermCvId
    { "{IPTC}", "AboutCvTermId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermId" },  // kCGImagePropertyIPTCExtAboutCvTermId
    { "{IPTC}", "AboutCvTermName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermName" },  // kCGImagePropertyIPTCExtAboutCvTermName
    { "{IPTC}", "AboutCvTermRefinedAbout",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermRefinedAbout" },  // kCGImagePropertyIPTCExtAboutCvTermRefinedAbout
    { "{IPTC}", "AddlModelInfo",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "AddlModelInfo" },  // kCGImagePropertyIPTCExtAddlModelInfo
    { "{IPTC}", "ArtworkOrObject",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkOrObject" },  // kCGImagePropertyIPTCExtArtworkOrObject
    { "{IPTC}", "ArtworkCircaDateCreated",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkCircaDateCreated" },  // kCGImagePropertyIPTCExtArtworkCircaDateCreated
    { "{IPTC}", "ArtworkContentDescription",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkContentDescription" },  // kCGImagePropertyIPTCExtArtworkContentDescription
    { "{IPTC}", "ArtworkContributionDescription",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkContributionDescription" },  // kCGImagePropertyIPTCExtArtworkContributionDescription
    { "{IPTC}", "ArtworkCopyrightNotice",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkCopyrightNotice" },  // kCGImagePropertyIPTCExtArtworkCopyrightNotice
    { "{IPTC}", "ArtworkCreator",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkCreator" },  // kCGImagePropertyIPTCExtArtworkCreator
    { "{IPTC}", "ArtworkCreatorID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkCreatorID" },  // kCGImagePropertyIPTCExtArtworkCreatorID
    { "{IPTC}", "ArtworkCopyrightOwnerID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkCopyrightOwnerID" },  // kCGImagePropertyIPTCExtArtworkCopyrightOwnerID
    { "{IPTC}", "ArtworkCopyrightOwnerName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkCopyrightOwnerName" },  // kCGImagePropertyIPTCExtArtworkCopyrightOwnerName
    { "{IPTC}", "ArtworkLicensorID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkLicensorID" },  // kCGImagePropertyIPTCExtArtworkLicensorID
    { "{IPTC}", "ArtworkLicensorName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkLicensorName" },  // kCGImagePropertyIPTCExtArtworkLicensorName
    { "{IPTC}", "ArtworkDateCreated",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkDateCreated" },  // kCGImagePropertyIPTCExtArtworkDateCreated
    { "{IPTC}", "ArtworkPhysicalDescription",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkPhysicalDescription" },  // kCGImagePropertyIPTCExtArtworkPhysicalDescription
    { "{IPTC}", "ArtworkSource",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkSource" },  // kCGImagePropertyIPTCExtArtworkSource
    { "{IPTC}", "ArtworkSourceInventoryNo",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkSourceInventoryNo" },  // kCGImagePropertyIPTCExtArtworkSourceInventoryNo
    { "{IPTC}", "ArtworkSourceInvURL",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkSourceInvURL" },  // kCGImagePropertyIPTCExtArtworkSourceInvURL
    { "{IPTC}", "ArtworkStylePeriod",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkStylePeriod" },  // kCGImagePropertyIPTCExtArtworkStylePeriod
    { "{IPTC}", "ArtworkTitle",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ArtworkTitle" },  // kCGImagePropertyIPTCExtArtworkTitle
    { "{IPTC}", "AudioBitrate",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "AudioBitrate" },  // kCGImagePropertyIPTCExtAudioBitrate
    { "{IPTC}", "AudioBitrateMode",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "AudioBitrateMode" },  // kCGImagePropertyIPTCExtAudioBitrateMode
    { "{IPTC}", "AudioChannelCount",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "AudioChannelCount" },  // kCGImagePropertyIPTCExtAudioChannelCount
    { "{IPTC}", "CircaDateCreated",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CircaDateCreated" },  // kCGImagePropertyIPTCExtCircaDateCreated
    { "{IPTC}", "ContainerFormat",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ContainerFormat" },  // kCGImagePropertyIPTCExtContainerFormat
    { "{IPTC}", "ContainerFormatIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ContainerFormatIdentifier" },  // kCGImagePropertyIPTCExtContainerFormatIdentifier
    { "{IPTC}", "ContainerFormatName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ContainerFormatName" },  // kCGImagePropertyIPTCExtContainerFormatName
    { "{IPTC}", "Contributor",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Contributor" },  // kCGImagePropertyIPTCExtContributor
    { "{IPTC}", "ContributorIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ContributorIdentifier" },  // kCGImagePropertyIPTCExtContributorIdentifier
    { "{IPTC}", "ContributorName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ContributorName" },  // kCGImagePropertyIPTCExtContributorName
    { "{IPTC}", "ContributorRole",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ContributorRole" },  // kCGImagePropertyIPTCExtContributorRole
    { "{IPTC}", "CopyrightYear",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CopyrightYear" },  // kCGImagePropertyIPTCExtCopyrightYear
    { "{IPTC}", "Creator",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Creator" },  // kCGImagePropertyIPTCExtCreator
    { "{IPTC}", "CreatorIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CreatorIdentifier" },  // kCGImagePropertyIPTCExtCreatorIdentifier
    { "{IPTC}", "CreatorName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CreatorName" },  // kCGImagePropertyIPTCExtCreatorName
    { "{IPTC}", "CreatorRole",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CreatorRole" },  // kCGImagePropertyIPTCExtCreatorRole
    { "{IPTC}", "ControlledVocabularyTerm",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ControlledVocabularyTerm" },  // kCGImagePropertyIPTCExtControlledVocabularyTerm
    { "{IPTC}", "DataOnScreen",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreen" },  // kCGImagePropertyIPTCExtDataOnScreen
    { "{IPTC}", "DataOnScreenRegion",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegion" },  // kCGImagePropertyIPTCExtDataOnScreenRegion
    { "{IPTC}", "DataOnScreenRegionD",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionD" },  // kCGImagePropertyIPTCExtDataOnScreenRegionD
    { "{IPTC}", "DataOnScreenRegionH",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionH" },  // kCGImagePropertyIPTCExtDataOnScreenRegionH
    { "{IPTC}", "DataOnScreenRegionText",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionText" },  // kCGImagePropertyIPTCExtDataOnScreenRegionText
    { "{IPTC}", "DataOnScreenRegionUnit",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionUnit" },  // kCGImagePropertyIPTCExtDataOnScreenRegionUnit
    { "{IPTC}", "DataOnScreenRegionW",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionW" },  // kCGImagePropertyIPTCExtDataOnScreenRegionW
    { "{IPTC}", "DataOnScreenRegionX",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionX" },  // kCGImagePropertyIPTCExtDataOnScreenRegionX
    { "{IPTC}", "DataOnScreenRegionY",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DataOnScreenRegionY" },  // kCGImagePropertyIPTCExtDataOnScreenRegionY
    { "{IPTC}", "DigitalImageGUID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DigImageGUID" },  // kCGImagePropertyIPTCExtDigitalImageGUID
    { "{IPTC}", "DigitalSourceFileType",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DigitalSourceFileType" },  // kCGImagePropertyIPTCExtDigitalSourceFileType
    { "{IPTC}", "DigitalSourceType",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DigitalSourceType" },  // kCGImagePropertyIPTCExtDigitalSourceType
    { "{IPTC}", "Dopesheet",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Dopesheet" },  // kCGImagePropertyIPTCExtDopesheet
    { "{IPTC}", "DopesheetLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DopesheetLink" },  // kCGImagePropertyIPTCExtDopesheetLink
    { "{IPTC}", "DopesheetLinkLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DopesheetLinkLink" },  // kCGImagePropertyIPTCExtDopesheetLinkLink
    { "{IPTC}", "DopesheetLinkLinkQualifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "DopesheetLinkLinkQualifier" },  // kCGImagePropertyIPTCExtDopesheetLinkLinkQualifier
    { "{IPTC}", "EmbdEncRightsExpr",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "EmbdEncRightsExpr" },  // kCGImagePropertyIPTCExtEmbdEncRightsExpr
    { "{IPTC}", "EmbeddedEncodedRightsExpr",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "EncRightsExpr" },  // kCGImagePropertyIPTCExtEmbeddedEncodedRightsExpr
    { "{IPTC}", "EmbeddedEncodedRightsExprType",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RightsExprEncType" },  // kCGImagePropertyIPTCExtEmbeddedEncodedRightsExprType
    { "{IPTC}", "EmbeddedEncodedRightsExprLangID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RightsExprLangId" },  // kCGImagePropertyIPTCExtEmbeddedEncodedRightsExprLangID
    { "{IPTC}", "Episode",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Episode" },  // kCGImagePropertyIPTCExtEpisode
    { "{IPTC}", "EpisodeIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "EpisodeIdentifier" },  // kCGImagePropertyIPTCExtEpisodeIdentifier
    { "{IPTC}", "EpisodeName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "EpisodeName" },  // kCGImagePropertyIPTCExtEpisodeName
    { "{IPTC}", "EpisodeNumber",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "EpisodeNumber" },  // kCGImagePropertyIPTCExtEpisodeNumber
    { "{IPTC}", "Event",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Event" },  // kCGImagePropertyIPTCExtEvent
    { "{IPTC}", "ShownEvent",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Event" },  // kCGImagePropertyIPTCExtShownEvent
    { "{IPTC}", "ShownEventIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ShownEventIdentifier" },  // kCGImagePropertyIPTCExtShownEventIdentifier
    { "{IPTC}", "ShownEventName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ShownEventName" },  // kCGImagePropertyIPTCExtShownEventName
    { "{IPTC}", "ExternalMetadataLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ExternalMetadataLink" },  // kCGImagePropertyIPTCExtExternalMetadataLink
    { "{IPTC}", "FeedIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "FeedIdentifier" },  // kCGImagePropertyIPTCExtFeedIdentifier
    { "{IPTC}", "Genre",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Genre" },  // kCGImagePropertyIPTCExtGenre
    { "{IPTC}", "GenreCvId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvId" },  // kCGImagePropertyIPTCExtGenreCvId
    { "{IPTC}", "GenreCvTermId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermId" },  // kCGImagePropertyIPTCExtGenreCvTermId
    { "{IPTC}", "GenreCvTermName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermName" },  // kCGImagePropertyIPTCExtGenreCvTermName
    { "{IPTC}", "GenreCvTermRefinedAbout",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermRefinedAbout" },  // kCGImagePropertyIPTCExtGenreCvTermRefinedAbout
    { "{IPTC}", "Headline",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "Headline" },  // kCGImagePropertyIPTCExtHeadline
    { "{IPTC}", "IPTCLastEdited",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "IPTCLastEdited" },  // kCGImagePropertyIPTCExtIPTCLastEdited
    { "{IPTC}", "LinkedEncRightsExpr",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "LinkedEncRightsExpr" },  // kCGImagePropertyIPTCExtLinkedEncRightsExpr
    { "{IPTC}", "LinkedEncodedRightsExpr",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "LinkedRightsExpr" },  // kCGImagePropertyIPTCExtLinkedEncodedRightsExpr
    { "{IPTC}", "LinkedEncodedRightsExprType",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RightsExprEncType" },  // kCGImagePropertyIPTCExtLinkedEncodedRightsExprType
    { "{IPTC}", "LinkedEncodedRightsExprLangID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RightsExprLangId" },  // kCGImagePropertyIPTCExtLinkedEncodedRightsExprLangID
    { "{IPTC}", "LocationCreated",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "LocationCreated" },  // kCGImagePropertyIPTCExtLocationCreated
    { "{IPTC}", "City",
      "http://ns.adobe.com/photoshop/1.0/", "photoshop", "City" },  // kCGImagePropertyIPTCExtLocationCity
    { "{IPTC}", "LocationShown",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "LocationShown" },  // kCGImagePropertyIPTCExtLocationShown
    { "{IPTC}", "MaxAvailHeight",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "MaxAvailHeight" },  // kCGImagePropertyIPTCExtMaxAvailHeight
    { "{IPTC}", "MaxAvailWidth",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "MaxAvailWidth" },  // kCGImagePropertyIPTCExtMaxAvailWidth
    { "{IPTC}", "ModelAge",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ModelAge" },  // kCGImagePropertyIPTCExtModelAge
    { "{IPTC}", "OrganisationInImageCode",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "OrganisationInImageCode" },  // kCGImagePropertyIPTCExtOrganisationInImageCode
    { "{IPTC}", "OrganisationInImageName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "OrganisationInImageName" },  // kCGImagePropertyIPTCExtOrganisationInImageName
    { "{IPTC}", "PersonHeard",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonHeard" },  // kCGImagePropertyIPTCExtPersonHeard
    { "{IPTC}", "PersonHeardIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonHeardIdentifier" },  // kCGImagePropertyIPTCExtPersonHeardIdentifier
    { "{IPTC}", "PersonHeardName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonHeardName" },  // kCGImagePropertyIPTCExtPersonHeardName
    { "{IPTC}", "PersonInImage",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonInImage" },  // kCGImagePropertyIPTCExtPersonInImage
    { "{IPTC}", "PersonInImageWDetails",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonInImageWDetails" },  // kCGImagePropertyIPTCExtPersonInImageWDetails
    { "{IPTC}", "PersonInImageCharacteristic",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonCharacteristic" },  // kCGImagePropertyIPTCExtPersonInImageCharacteristic
    { "{IPTC}", "PersonInImageCvTermCvId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvId" },  // kCGImagePropertyIPTCExtPersonInImageCvTermCvId
    { "{IPTC}", "PersonInImageCvTermId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermId" },  // kCGImagePropertyIPTCExtPersonInImageCvTermId
    { "{IPTC}", "PersonInImageCvTermName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermName" },  // kCGImagePropertyIPTCExtPersonInImageCvTermName
    { "{IPTC}", "PersonInImageCvTermRefinedAbout",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "CvTermRefinedAbout" },  // kCGImagePropertyIPTCExtPersonInImageCvTermRefinedAbout
    { "{IPTC}", "PersonInImageDescription",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonDescription" },  // kCGImagePropertyIPTCExtPersonInImageDescription
    { "{IPTC}", "PersonInImageId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonId" },  // kCGImagePropertyIPTCExtPersonInImageId
    { "{IPTC}", "PersonInImageName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PersonName" },  // kCGImagePropertyIPTCExtPersonInImageName
    { "{IPTC}", "ProductInImage",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ProductInImage" },  // kCGImagePropertyIPTCExtProductInImage
    { "{IPTC}", "ProductInImageDescription",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ProductDescription" },  // kCGImagePropertyIPTCExtProductInImageDescription
    { "{IPTC}", "ProductInImageGTIN",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ProductGTIN" },  // kCGImagePropertyIPTCExtProductInImageGTIN
    { "{IPTC}", "ProductInImageName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ProductName" },  // kCGImagePropertyIPTCExtProductInImageName
    { "{IPTC}", "PublicationEvent",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PublicationEvent" },  // kCGImagePropertyIPTCExtPublicationEvent
    { "{IPTC}", "PublicationEventDate",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PublicationEventDate" },  // kCGImagePropertyIPTCExtPublicationEventDate
    { "{IPTC}", "PublicationEventIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PublicationEventIdentifier" },  // kCGImagePropertyIPTCExtPublicationEventIdentifier
    { "{IPTC}", "PublicationEventName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "PublicationEventName" },  // kCGImagePropertyIPTCExtPublicationEventName
    { "{IPTC}", "Rating",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Rating" },  // kCGImagePropertyIPTCExtRating
    { "{IPTC}", "RatingRatingRegion",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRatingRegion" },  // kCGImagePropertyIPTCExtRatingRatingRegion
    { "{IPTC}", "RatingRegionCity",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionCity" },  // kCGImagePropertyIPTCExtRatingRegionCity
    { "{IPTC}", "RatingRegionCountryCode",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionCountryCode" },  // kCGImagePropertyIPTCExtRatingRegionCountryCode
    { "{IPTC}", "RatingRegionCountryName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionCountryName" },  // kCGImagePropertyIPTCExtRatingRegionCountryName
    { "{IPTC}", "RatingRegionGPSAltitude",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionGPSAltitude" },  // kCGImagePropertyIPTCExtRatingRegionGPSAltitude
    { "{IPTC}", "RatingRegionGPSLatitude",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionGPSLatitude" },  // kCGImagePropertyIPTCExtRatingRegionGPSLatitude
    { "{IPTC}", "RatingRegionGPSLongitude",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionGPSLongitude" },  // kCGImagePropertyIPTCExtRatingRegionGPSLongitude
    { "{IPTC}", "RatingRegionIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionIdentifier" },  // kCGImagePropertyIPTCExtRatingRegionIdentifier
    { "{IPTC}", "RatingRegionLocationId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionLocationId" },  // kCGImagePropertyIPTCExtRatingRegionLocationId
    { "{IPTC}", "RatingRegionLocationName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionLocationName" },  // kCGImagePropertyIPTCExtRatingRegionLocationName
    { "{IPTC}", "RatingRegionProvinceState",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionProvinceState" },  // kCGImagePropertyIPTCExtRatingRegionProvinceState
    { "{IPTC}", "RatingRegionSublocation",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionSublocation" },  // kCGImagePropertyIPTCExtRatingRegionSublocation
    { "{IPTC}", "RatingRegionWorldRegion",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingRegionWorldRegion" },  // kCGImagePropertyIPTCExtRatingRegionWorldRegion
    { "{IPTC}", "RatingScaleMaxValue",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingScaleMaxValue" },  // kCGImagePropertyIPTCExtRatingScaleMaxValue
    { "{IPTC}", "RatingScaleMinValue",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingScaleMinValue" },  // kCGImagePropertyIPTCExtRatingScaleMinValue
    { "{IPTC}", "RatingSourceLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingSourceLink" },  // kCGImagePropertyIPTCExtRatingSourceLink
    { "{IPTC}", "RatingValue",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingValue" },  // kCGImagePropertyIPTCExtRatingValue
    { "{IPTC}", "RatingValueLogoLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RatingValueLogoLink" },  // kCGImagePropertyIPTCExtRatingValueLogoLink
    { "{IPTC}", "RegistryID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RegistryId" },  // kCGImagePropertyIPTCExtRegistryID
    { "{IPTC}", "RegistryEntryRole",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RegEntryRole" },  // kCGImagePropertyIPTCExtRegistryEntryRole
    { "{IPTC}", "RegistryItemID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RegItemId" },  // kCGImagePropertyIPTCExtRegistryItemID
    { "{IPTC}", "RegistryOrganisationID",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "RegOrgId" },  // kCGImagePropertyIPTCExtRegistryOrganisationID
    { "{IPTC}", "ReleaseReady",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "ReleaseReady" },  // kCGImagePropertyIPTCExtReleaseReady
    { "{IPTC}", "Season",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Season" },  // kCGImagePropertyIPTCExtSeason
    { "{IPTC}", "SeasonIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SeasonIdentifier" },  // kCGImagePropertyIPTCExtSeasonIdentifier
    { "{IPTC}", "SeasonName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SeasonName" },  // kCGImagePropertyIPTCExtSeasonName
    { "{IPTC}", "SeasonNumber",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SeasonNumber" },  // kCGImagePropertyIPTCExtSeasonNumber
    { "{IPTC}", "Series",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Series" },  // kCGImagePropertyIPTCExtSeries
    { "{IPTC}", "SeriesIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SeriesIdentifier" },  // kCGImagePropertyIPTCExtSeriesIdentifier
    { "{IPTC}", "SeriesName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SeriesName" },  // kCGImagePropertyIPTCExtSeriesName
    { "{IPTC}", "StorylineIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "StorylineIdentifier" },  // kCGImagePropertyIPTCExtStorylineIdentifier
    { "{IPTC}", "StreamReady",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "StreamReady" },  // kCGImagePropertyIPTCExtStreamReady
    { "{IPTC}", "StylePeriod",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "StylePeriod" },  // kCGImagePropertyIPTCExtStylePeriod
    { "{IPTC}", "SupplyChainSource",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "StorylineIdentifier" },  // kCGImagePropertyIPTCExtSupplyChainSource
    { "{IPTC}", "SupplyChainSourceIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "StreamReady" },  // kCGImagePropertyIPTCExtSupplyChainSourceIdentifier
    { "{IPTC}", "SupplyChainSourceName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "StylePeriod" },  // kCGImagePropertyIPTCExtSupplyChainSourceName
    { "{IPTC}", "TemporalCoverage",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SupplyChainSource" },  // kCGImagePropertyIPTCExtTemporalCoverage
    { "{IPTC}", "TemporalCoverageFrom",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SupplyChainSourceIdentifier" },  // kCGImagePropertyIPTCExtTemporalCoverageFrom
    { "{IPTC}", "TemporalCoverageTo",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "SupplyChainSourceName" },  // kCGImagePropertyIPTCExtTemporalCoverageTo
    { "{IPTC}", "Transcript",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "Transcript" },  // kCGImagePropertyIPTCExtTranscript
    { "{IPTC}", "TranscriptLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "TranscriptLink" },  // kCGImagePropertyIPTCExtTranscriptLink
    { "{IPTC}", "TranscriptLinkLink",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "TranscriptLinkLink" },  // kCGImagePropertyIPTCExtTranscriptLinkLink
    { "{IPTC}", "TranscriptLinkLinkQualifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "TranscriptLinkLinkQualifier" },  // kCGImagePropertyIPTCExtTranscriptLinkLinkQualifier
    { "{IPTC}", "VideoBitrate",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoBitrate" },  // kCGImagePropertyIPTCExtVideoBitrate
    { "{IPTC}", "VideoBitrateMode",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoBitrateMode" },  // kCGImagePropertyIPTCExtVideoBitrateMode
    { "{IPTC}", "VideoDisplayAspectRatio",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoDisplayAspectRatio" },  // kCGImagePropertyIPTCExtVideoDisplayAspectRatio
    { "{IPTC}", "VideoEncodingProfile",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoEncodingProfile" },  // kCGImagePropertyIPTCExtVideoEncodingProfile
    { "{IPTC}", "VideoShotType",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoShotType" },  // kCGImagePropertyIPTCExtVideoShotType
    { "{IPTC}", "VideoShotTypeIdentifier",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoShotTypeIdentifier" },  // kCGImagePropertyIPTCExtVideoShotTypeIdentifier
    { "{IPTC}", "VideoShotTypeName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoShotTypeName" },  // kCGImagePropertyIPTCExtVideoShotTypeName
    { "{IPTC}", "VideoStreamsCount",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VideoStreamsCount" },  // kCGImagePropertyIPTCExtVideoStreamsCount
    { "{IPTC}", "VisualColor",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "VisualColor" },  // kCGImagePropertyIPTCExtVisualColor
    { "{IPTC}", "WorkflowTag",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "WorkflowTag" },  // kCGImagePropertyIPTCExtWorkflowTag
    { "{IPTC}", "WorkflowTagCvId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "WorkflowTagCvId" },  // kCGImagePropertyIPTCExtWorkflowTagCvId
    { "{IPTC}", "WorkflowTagCvTermId",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "WorkflowTagCvTermId" },  // kCGImagePropertyIPTCExtWorkflowTagCvTermId
    { "{IPTC}", "WorkflowTagCvTermName",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "WorkflowTagCvTermName" },  // kCGImagePropertyIPTCExtWorkflowTagCvTermName
    { "{IPTC}", "WorkflowTagCvTermRefinedAbout",
      "http://iptc.org/std/Iptc4xmpExt/2008-02-29/", "Iptc4xmpExt", "WorkflowTagCvTermRefinedAbout" },  // kCGImagePropertyIPTCExtWorkflowTagCvTermRefinedAbout
};

// The row for a (dictionary, property) pair, or NULL. Both callers need the same answer to the same
// question, and NULL is the header's own: a property the table does not carry is one "not supported at
// this time", so the lookup answers NULL and the set answers false and writes nothing (measured, and
// both are in the harness: a dictionary and a property no header declares behave the same way).
static const char *const *charon_property_row(const char *dictionary, const char *property)
{
    for (size_t i = 0; i < CHARON_PROPERTY_ROWS; i++) {
        const char *const *row = charon_property_rows[i];
        if (strcmp(row[0], dictionary) == 0 && strcmp(row[1], property) == 0)
            return row;
    }
    return NULL;
}

// A CFString as a C string in the caller's buffer. CFStringGetCStringPtr would answer NULL for a string
// it cannot hand back in place, which is most of ImageIO's own (measured: 89 of the 357 names in the
// table), so the copy is made instead and a string that does not fit is reported as no string at all.
static BOOL charon_string(CFStringRef string, char *buffer, size_t size)
{
    return string && CFStringGetCString(string, buffer, (CFIndex)size, kCFStringEncodingUTF8);
}

CGImageMetadataTagRef CGImageMetadataCopyTagMatchingImageProperty(CGImageMetadataRef metadata, CFStringRef dictionaryName,
                                                                 CFStringRef propertyName)
{
    NSDictionary *held = charon_metadata(metadata);
    if (!held || !dictionaryName || !propertyName)
        return NULL;
    char dictionary[64], property[64];
    if (!charon_string(dictionaryName, dictionary, sizeof dictionary) ||
        !charon_string(propertyName, property, sizeof property))
        return NULL;
    const char *const *row = charon_property_row(dictionary, property);
    if (!row)
        return NULL;
    char xmlns[64], name[64];
    // the top level of the tree, and not into a structure's fields or an array's elements: measured, a
    // tree holding exif:Sub{exif:DateTimeOriginal} answers NULL for (Exif, DateTimeOriginal)
    for (id heldTag in (NSArray *)[held objectForKey:@"tags"]) {
        NSDictionary *tag = (NSDictionary *)heldTag;
        if (!charon_string((__bridge CFStringRef)[tag objectForKey:@"namespace"], xmlns, sizeof xmlns) ||
            !charon_string((__bridge CFStringRef)[tag objectForKey:@"name"], name, sizeof name))
            continue;
        // the prefix is not part of the match: measured, a tag whose prefix is one a caller registered
        // for the same namespace is answered, and the harness prints that case too
        if (strcmp(xmlns, row[2]) == 0 && strcmp(name, row[4]) == 0)
            return (__bridge_retained CGImageMetadataTagRef)charon_tag_copy(tag);
    }
    return NULL;
}

// A number the caller passes is written as the string XMP spells it and not as a CFNumber, because that is
// what the host writes and what its own XMP packet carries: measured on 2026-10-03, the tag's value comes
// back a CFString for every one of these - 3 writes "3", 3.0 writes "3.000000", 1.5 writes "1.500000" and
// 0.1 writes "0.100000", -2 writes "-2", a 64-bit integer writes its digits, and a CFBoolean writes
// "True" or "False". The spelling follows the number's own CFNumber type (CFBooleanGetTypeID, then
// CFNumberIsFloatType, then an integer), which is XMP's own three scalar types and not a format this
// library chooses: that is the only thing CFNumberIsFloatType says, so a float writes %f and an integer
// writes %lld. Nothing else is touched - an array and a dictionary go to the path writer as the caller
// passed them, which is what "The same value restrictions apply as in CGImageMetadataTagCreate" asks for,
// and the type of the tag is read off that value as before.
//
// The text is autoreleased and the caller holds it in `owned` for exactly as long as the write needs it,
// which is the length of this function's own call into the path writer.
static CFTypeRef charon_property_number(CFTypeRef value, NSString **owned)
{
    CFTypeID type = CFGetTypeID(value);
    if (type == CFBooleanGetTypeID()) {
        *owned = CFBooleanGetValue((CFBooleanRef)value) ? @"True" : @"False";
    } else if (type == CFNumberGetTypeID()) {
        if (CFNumberIsFloatType((CFNumberRef)value)) {
            double real = 0;
            CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &real);
            *owned = [NSString stringWithFormat:@"%f", real];
        } else {
            long long integer = 0;
            CFNumberGetValue((CFNumberRef)value, kCFNumberLongLongType, &integer);
            *owned = [NSString stringWithFormat:@"%lld", integer];
        }
    } else {
        return value;
    }
    return (__bridge CFTypeRef)*owned;
}

bool CGImageMetadataSetValueMatchingImageProperty(CGMutableImageMetadataRef metadata, CFStringRef dictionaryName,
                                                 CFStringRef propertyName, CFTypeRef value)
{
    NSDictionary *held = charon_is_metadata(metadata) ? charon_metadata(metadata) : nil;
    if (!held || !dictionaryName || !propertyName || !value)
        return false;
    char dictionary[64], property[64];
    if (!charon_string(dictionaryName, dictionary, sizeof dictionary) ||
        !charon_string(propertyName, property, sizeof property))
        return false;
    const char *const *row = charon_property_row(dictionary, property);
    if (!row)
        return false; // measured: false, and no tag is written
    // the write is this file's own path write, so the tag's type is read off the CFType of the value the
    // way CGImageMetadataSetValueWithPath reads it: measured, a string and a number both write a String
    // tag and an array an ArrayOrdered one, and a second set for the same pair keeps one tag and its
    // second value
    NSString *path = [NSString stringWithFormat:@"%@:%@", [NSString stringWithUTF8String:row[3]],
                                                [NSString stringWithUTF8String:row[4]]];
    NSString *number = nil;
    CFTypeRef written = charon_property_number(value, &number);
    BOOL ok = CGImageMetadataSetValueWithPath(metadata, NULL, (__bridge CFStringRef)path, written);
    return ok;
}

