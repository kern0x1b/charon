#import "CharonCMTag26.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

// The CMTagCollection of iOS 17. A CMTag is three machine words with no lifetime of its own, so a
// collection is a sorted array of them and everything here is a search, an insert or a run over it; the
// class is the port's own behind 26.2's bridged CMTagCollectionRef. facts/CoreMedia/TagCollection.md

static void charon_insert_all(CharonCMTagCollection *into, CharonCMTagCollection *from);

static BOOL charon_tag_less(CMTag left, CMTag right)
{
    if (left.category != right.category)
        return left.category < right.category;
    if (left.dataType != right.dataType)
        return left.dataType < right.dataType;
    return left.value < right.value;
}

static BOOL charon_tag_equal(CMTag left, CMTag right)
{
    return left.category == right.category && left.dataType == right.dataType && left.value == right.value;
}

@implementation CharonCMTagCollection {
    CMTag *_tags;
    NSUInteger _count;
    NSUInteger _capacity;
}

@synthesize charon_count = _count;

- (instancetype)charon_initWithTags:(const CMTag *)tags count:(NSUInteger)count __attribute__((objc_method_family(init)))
{
    self = [super init];
    if (!self)
        return nil;
    if (count) {
        _tags = malloc(count * sizeof *_tags);
        if (!_tags)
            return nil;
        _capacity = count;
        for (NSUInteger index = 0; index < count; index++)
            [self charon_insert:tags[index]];
    }
    return self;
}

- (void)dealloc
{
    free(_tags);
    _tags = NULL;
    _count = 0;
    _capacity = 0;
}

- (const CMTag *)charon_tags
{
    return _tags;
}

// The index of the first tag not less than the one asked for, and whether that is the tag itself.
- (NSUInteger)charon_indexOfTag:(CMTag)tag
{
    NSUInteger low = 0, high = _count;
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if (charon_tag_less(_tags[middle], tag))
            low = middle + 1;
        else
            high = middle;
    }
    return low;
}

- (BOOL)charon_contains:(CMTag)tag
{
    if (!CMTagIsValid(tag))
        return NO;
    NSUInteger at = [self charon_indexOfTag:tag];
    return at < _count && charon_tag_equal(_tags[at], tag);
}

- (BOOL)charon_insert:(CMTag)tag
{
    if ([self charon_contains:tag])
        return YES;
    if (_count == _capacity) {
        NSUInteger capacity = _capacity ? _capacity * 2 : 8;
        CMTag *tags = realloc(_tags, capacity * sizeof *tags);
        if (!tags)
            return NO;
        _tags = tags;
        _capacity = capacity;
    }
    NSUInteger at = [self charon_indexOfTag:tag];
    memmove(_tags + at + 1, _tags + at, (_count - at) * sizeof *_tags);
    _tags[at] = tag;
    _count++;
    return YES;
}

- (BOOL)charon_remove:(CMTag)tag
{
    NSUInteger at = [self charon_indexOfTag:tag];
    if (at >= _count || !charon_tag_equal(_tags[at], tag))
        return NO;
    memmove(_tags + at, _tags + at + 1, (_count - at - 1) * sizeof *_tags);
    _count--;
    return YES;
}

- (NSUInteger)charon_removeCategory:(CMTagCategory)category
{
    CMTag probe = {category, kCMTagDataType_Invalid, 0};
    NSUInteger at = [self charon_indexOfTag:probe], end = at;
    while (end < _count && _tags[end].category == category)
        end++;
    if (end > at) {
        memmove(_tags + at, _tags + end, (_count - end) * sizeof *_tags);
        _count -= end - at;
    }
    return end - at;
}

- (void)charon_removeAll
{
    _count = 0;
}

- (NSUInteger)charon_countOfCategory:(CMTagCategory)category
{
    CMTag probe = {category, kCMTagDataType_Invalid, 0};
    NSUInteger at = [self charon_indexOfTag:probe], count = 0;
    while (at < _count && _tags[at].category == category) {
        count++;
        at++;
    }
    return count;
}

@end

const CMTag kCMTagInvalid = {kCMTagCategory_Undefined, kCMTagDataType_Invalid, 0};

// CharonCMTag26.h declares the three keys extern, so a definition that repeated it would be the
// -Wextern-initializer warning: the header says extern, this says what.
const CFStringRef kCMTagCategoryKey = CFSTR("category");
const CFStringRef kCMTagValueKey = CFSTR("value");
const CFStringRef kCMTagDataTypeKey = CFSTR("flags");

CFTypeID CMTagCollectionGetTypeID(void)
{
    return (CFTypeID)objc_getClass("CharonCMTagCollection");
}

// A plain __bridge cast hands the reference to the caller without transferring ownership, so ARC
// releases the collection at the end of the statement and every later use is a use-after-free. The
// reference types are CF_RETURNS_RETAINED, so the +1 belongs to the caller and CFRelease balances it.
static CMTagCollectionRef charon_from(CharonCMTagCollection *collection)
{
    return (__bridge_retained CMTagCollectionRef)collection;
}

static CMMutableTagCollectionRef charon_mutable_from(CharonCMTagCollection *collection)
{
    return (CMMutableTagCollectionRef)(__bridge_retained CMTagCollectionRef)collection;
}

static CharonCMTagCollection *charon_to(CMTagCollectionRef collection)
{
    return (__bridge CharonCMTagCollection *)collection;
}

OSStatus CMTagCollectionCreate(CFAllocatorRef allocator, const CMTag *tags, CMItemCount tagCount, CMTagCollectionRef *newCollectionOut)
{
    (void)allocator;
    if (!newCollectionOut || (!tags && tagCount))
        return kCMTagCollectionError_ParamErr;
    *newCollectionOut = NULL;
    CharonCMTagCollection *collection = [[CharonCMTagCollection alloc] charon_initWithTags:tags count:(NSUInteger)tagCount];
    if (!collection)
        return kCMTagCollectionError_AllocationFailed;
    *newCollectionOut = charon_from(collection);
    return noErr;
}

OSStatus CMTagCollectionCreateMutable(CFAllocatorRef allocator, CFIndex capacity, CMMutableTagCollectionRef *newMutableCollectionOut)
{
    (void)allocator;
    (void)capacity;
    if (!newMutableCollectionOut)
        return kCMTagCollectionError_ParamErr;
    *newMutableCollectionOut = charon_mutable_from([[CharonCMTagCollection alloc] charon_initWithTags:NULL count:0]);
    return *newMutableCollectionOut ? noErr : kCMTagCollectionError_AllocationFailed;
}

OSStatus CMTagCollectionCreateCopy(CMTagCollectionRef tagCollection, CFAllocatorRef allocator, CMTagCollectionRef *newCollectionCopyOut)
{
    CharonCMTagCollection *source = charon_to(tagCollection);
    return CMTagCollectionCreate(allocator, source ? source.charon_tags : NULL, (CMItemCount)(source ? source.charon_count : 0), newCollectionCopyOut);
}

OSStatus CMTagCollectionCreateMutableCopy(CMTagCollectionRef tagCollection, CFAllocatorRef allocator, CMMutableTagCollectionRef *newMutableCollectionCopyOut)
{
    CharonCMTagCollection *source = charon_to(tagCollection);
    if (!newMutableCollectionCopyOut)
        return kCMTagCollectionError_ParamErr;
    CMMutableTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutable(allocator, (CFIndex)(source ? source.charon_count : 0), &out);
    if (status)
        return status;
    // A copy carries the tags: this one made an empty collection, which is what made a union built on
    // it lose the first collection entirely.
    charon_insert_all(charon_to((CMTagCollectionRef)out), source);
    *newMutableCollectionCopyOut = out;
    return noErr;
}

static NSString *charon_category_name(CMTagCategory category)
{
    return [NSString stringWithFormat:@"%c%c%c%c", (char)(category >> 24), (char)(category >> 16), (char)(category >> 8), (char)category];
}

static NSString *charon_tag_value(CMTag tag)
{
    switch (tag.dataType) {
    case kCMTagDataType_OSType:
        return [NSString stringWithFormat:@"'%@'", charon_category_name((CMTagCategory)(uint32_t)tag.value)];
    case kCMTagDataType_Flags:
        return [NSString stringWithFormat:@"0x%llx", (unsigned long long)tag.value];
    case kCMTagDataType_Float64: {
        double number;
        memcpy(&number, &tag.value, sizeof number);
        return [NSString stringWithFormat:@"%.2f", number];
    }
    default:
        return [NSString stringWithFormat:@"%lld", (long long)tag.value];
    }
}

static NSString *charon_tag_type(CMTagDataType type)
{
    switch (type) {
    case kCMTagDataType_OSType: return @"OSType";
    case kCMTagDataType_Flags: return @"flags";
    case kCMTagDataType_Float64: return @"Flt64";
    default: return @"int64";
    }
}

CFStringRef CMTagCollectionCopyDescription(CFAllocatorRef allocator, CMTagCollectionRef tagCollection)
{
    (void)allocator;
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection)
        return NULL;
    const CMTag *tags = [collection charon_tags];
    NSMutableString *built = [NSMutableString stringWithString:@"CMTagCollection{\n"];
    for (NSUInteger index = 0; index < collection.charon_count; index++)
        [built appendFormat:@"{category:'%@' value:%@ <%@>}\n", charon_category_name(tags[index].category),
                              charon_tag_value(tags[index]), charon_tag_type(tags[index].dataType)];
    [built appendString:@"}"];
    return (__bridge_retained CFStringRef)built;
}

CMItemCount CMTagCollectionGetCount(CMTagCollectionRef tagCollection)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    return (CMItemCount)(collection ? collection.charon_count : 0);
}

Boolean CMTagCollectionIsEmpty(CMTagCollectionRef tagCollection)
{
    return CMTagCollectionGetCount(tagCollection) == 0;
}

Boolean CMTagCollectionContainsTag(CMTagCollectionRef tagCollection, CMTag tag)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    return collection ? [collection charon_contains:tag] : false;
}

CMItemCount CMTagCollectionGetCountOfCategory(CMTagCollectionRef tagCollection, CMTagCategory category)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    return (CMItemCount)(collection ? [collection charon_countOfCategory:category] : 0);
}

Boolean CMTagCollectionContainsCategory(CMTagCollectionRef tagCollection, CMTagCategory category)
{
    // Measured on the host over empty and non-empty collections: the Undefined category is always
    // contained, even by an empty collection, and every other category only when it has tags of it.
    if (category == kCMTagCategory_Undefined)
        return true;
    return CMTagCollectionGetCountOfCategory(tagCollection, category) != 0;
}

Boolean CMTagCollectionContainsTagsOfCollection(CMTagCollectionRef tagCollection, CMTagCollectionRef inputCollection)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection), *input = charon_to(inputCollection);
    if (!collection || !input)
        return false;
    const CMTag *tags = input.charon_tags;
    for (NSUInteger index = 0; index < input.charon_count; index++)
        if (![collection charon_contains:tags[index]])
            return false;
    return true;
}

Boolean CMTagCollectionContainsSpecifiedTags(CMTagCollectionRef tagCollection, const CMTag *containedTags, CMItemCount containedTagCount)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || (!containedTags && containedTagCount))
        return false;
    for (CMItemCount index = 0; index < containedTagCount; index++)
        if (![collection charon_contains:containedTags[index]])
            return false;
    return true;
}

OSStatus CMTagCollectionGetTags(CMTagCollectionRef tagCollection, CMTag *tagBuffer, CMItemCount tagBufferCount,
                                CMItemCount *numberOfTagsCopied)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || (!tagBuffer && tagBufferCount))
        return kCMTagCollectionError_ParamErr;
    const CMTag *tags = [collection charon_tags];
    CMItemCount written = 0;
    for (NSUInteger index = 0; index < collection.charon_count && written < tagBufferCount; index++)
        tagBuffer[written++] = tags[index];
    if (numberOfTagsCopied)
        *numberOfTagsCopied = written;
    return written == collection.charon_count ? noErr : kCMTagCollectionError_ExhaustedBufferSize;
}

OSStatus CMTagCollectionGetTagsWithCategory(CMTagCollectionRef tagCollection, CMTagCategory category, CMTag *tagBuffer,
                                           CMItemCount tagBufferCount, CMItemCount *numberOfTagsCopied)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || (!tagBuffer && tagBufferCount))
        return kCMTagCollectionError_ParamErr;
    const CMTag *tags = [collection charon_tags];
    CMItemCount written = 0;
    CMItemCount matched = 0;
    for (NSUInteger index = 0; index < collection.charon_count; index++)
        if (tags[index].category == category)
            matched++;
    for (NSUInteger index = 0; index < collection.charon_count && written < tagBufferCount; index++)
        if (tags[index].category == category)
            tagBuffer[written++] = tags[index];
    if (numberOfTagsCopied)
        *numberOfTagsCopied = written;
    return written == matched ? noErr : kCMTagCollectionError_ExhaustedBufferSize;
}

CMItemCount CMTagCollectionCountTagsWithFilterFunction(CMTagCollectionRef tagCollection,
                                                       CMTagCollectionTagFilterFunction filterApplier, void *context)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || !filterApplier)
        return 0;
    const CMTag *tags = [collection charon_tags];
    CMItemCount count = 0;
    for (NSUInteger index = 0; index < collection.charon_count; index++)
        if (filterApplier(tags[index], context))
            count++;
    return count;
}

OSStatus CMTagCollectionGetTagsWithFilterFunction(CMTagCollectionRef tagCollection, CMTag *tagBuffer, CMItemCount tagBufferCount,
                                                 CMItemCount *numberOfTagsCopied, CMTagCollectionTagFilterFunction filter, void *context)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || !filter || (!tagBuffer && tagBufferCount))
        return kCMTagCollectionError_ParamErr;
    const CMTag *tags = [collection charon_tags];
    CMItemCount written = 0;
    CMItemCount matched = 0;
    for (NSUInteger index = 0; index < collection.charon_count; index++)
        if (filter(tags[index], context))
            matched++;
    for (NSUInteger index = 0; index < collection.charon_count && written < tagBufferCount; index++)
        if (filter(tags[index], context))
            tagBuffer[written++] = tags[index];
    if (numberOfTagsCopied)
        *numberOfTagsCopied = written;
    return written == matched ? noErr : kCMTagCollectionError_ExhaustedBufferSize;
}

OSStatus CMTagCollectionAddTag(CMMutableTagCollectionRef tagCollection, CMTag tag)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection);
    if (!collection)
        return kCMTagCollectionError_ParamErr;
    // Measured: the host answers noErr for kCMTagInvalid and stores it - the count goes up, and the tag
    // sorts first because its category is 0. It is an ordinary tag with no data type, not a refusal.
    return [collection charon_insert:tag] ? noErr : kCMTagCollectionError_AllocationFailed;
}

OSStatus CMTagCollectionRemoveTag(CMMutableTagCollectionRef tagCollection, CMTag tag)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection);
    if (!collection)
        return kCMTagCollectionError_ParamErr;
    return [collection charon_remove:tag] ? noErr : kCMTagCollectionError_TagNotFound;
}

OSStatus CMTagCollectionRemoveAllTagsOfCategory(CMMutableTagCollectionRef tagCollection, CMTagCategory category)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection);
    if (!collection)
        return kCMTagCollectionError_ParamErr;
    [collection charon_removeCategory:category];
    return noErr;
}

OSStatus CMTagCollectionRemoveAllTags(CMMutableTagCollectionRef tagCollection)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection);
    if (!collection)
        return kCMTagCollectionError_ParamErr;
    [collection charon_removeAll];
    return noErr;
}

OSStatus CMTagCollectionAddTagsFromCollection(CMMutableTagCollectionRef tagCollection, CMTagCollectionRef inputCollection)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection), *input = charon_to(inputCollection);
    if (!collection || !input)
        return kCMTagCollectionError_ParamErr;
    const CMTag *tags = input.charon_tags;
    for (NSUInteger index = 0; index < input.charon_count; index++)
        if (![collection charon_insert:tags[index]])
            return kCMTagCollectionError_AllocationFailed;
    return noErr;
}

OSStatus CMTagCollectionAddTagsFromArray(CMMutableTagCollectionRef tagCollection, CMTag *tags, CMItemCount tagCount)
{
    CharonCMTagCollection *collection = charon_to((CMTagCollectionRef)tagCollection);
    if (!collection || (!tags && tagCount))
        return kCMTagCollectionError_ParamErr;
    for (CMItemCount index = 0; index < tagCount; index++)
        if (![collection charon_insert:tags[index]])
            return kCMTagCollectionError_AllocationFailed;
    return noErr;
}

// Shared by CreateMutableCopy and the union: copy every tag of one collection into another.
static void charon_insert_all(CharonCMTagCollection *into, CharonCMTagCollection *from)
{
    if (!into || !from)
        return;
    const CMTag *tags = [from charon_tags];
    for (NSUInteger index = 0; index < from.charon_count; index++)
        [into charon_insert:tags[index]];
}

// The host's answers, on a one-tag collection against a two-tag one that shares a tag with it:
// Difference answers nothing, which is the first minus the second, and ExclusiveOr answers one tag,
// which is the symmetric difference - a tag in one and not the other, counted once. Stacking the two
// differences answers two there, which is what the port did before this was measured.
OSStatus CMTagCollectionCreateDifference(CMTagCollectionRef tagCollectionMinuend, CMTagCollectionRef tagCollectionSubtrahend, CMTagCollectionRef *tagCollectionOut)
{
    CharonCMTagCollection *minuend = charon_to(tagCollectionMinuend), *subtrahend = charon_to(tagCollectionSubtrahend);
    if (!tagCollectionOut)
        return kCMTagCollectionError_ParamErr;
    CMTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, (CMMutableTagCollectionRef *)&out);
    if (status)
        return status;
    CharonCMTagCollection *result = charon_to(out);
    const CMTag *tags = minuend ? [minuend charon_tags] : NULL;
    for (NSUInteger index = 0; minuend && index < minuend.charon_count; index++)
        if (!subtrahend || ![subtrahend charon_contains:tags[index]])
            [result charon_insert:tags[index]];
    *tagCollectionOut = out;
    return noErr;
}

OSStatus CMTagCollectionCreateExclusiveOr(CMTagCollectionRef tagCollection1, CMTagCollectionRef tagCollection2, CMTagCollectionRef *tagCollectionOut)
{
    CharonCMTagCollection *first = charon_to(tagCollection1), *second = charon_to(tagCollection2);
    if (!tagCollectionOut)
        return kCMTagCollectionError_ParamErr;
    CMTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, (CMMutableTagCollectionRef *)&out);
    if (status)
        return status;
    CharonCMTagCollection *result = charon_to(out);
    const CMTag *left = first ? [first charon_tags] : NULL;
    for (NSUInteger index = 0; first && index < first.charon_count; index++)
        if (!second || ![second charon_contains:left[index]])
            [result charon_insert:left[index]];
    const CMTag *right = second ? [second charon_tags] : NULL;
    for (NSUInteger index = 0; second && index < second.charon_count; index++)
        if (!first || ![first charon_contains:right[index]])
            [result charon_insert:right[index]];
    *tagCollectionOut = out;
    return noErr;
}

// The set algebra, the category filter, the two appliers and the dictionary form. Measured on the
// host's own CoreMedia (facts/CoreMedia/TagCollection.md); the binary …AsData form is Apple's own
// layout and is not written here.


OSStatus CMTagCollectionCreateUnion(CMTagCollectionRef tagCollection1, CMTagCollectionRef tagCollection2, CMTagCollectionRef *tagCollectionOut)
{
    CMTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutableCopy(tagCollection1, NULL, (CMMutableTagCollectionRef *)&out);
    if (status)
        return status;
    // A union is both, not the first one: the host's answers carry the second collection's tags too.
    charon_insert_all(charon_to(out), charon_to(tagCollection2));
    *tagCollectionOut = out;
    return noErr;
}

OSStatus CMTagCollectionCreateIntersection(CMTagCollectionRef tagCollection1, CMTagCollectionRef tagCollection2, CMTagCollectionRef *tagCollectionOut)
{
    CharonCMTagCollection *first = charon_to(tagCollection1), *second = charon_to(tagCollection2);
    if (!tagCollectionOut)
        return kCMTagCollectionError_ParamErr;
    CMTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, (CMMutableTagCollectionRef *)&out);
    if (status)
        return status;
    CharonCMTagCollection *result = charon_to(out);
    const CMTag *tags = first ? [first charon_tags] : NULL;
    for (NSUInteger index = 0; first && index < first.charon_count; index++)
        if (second && [second charon_contains:tags[index]])
            [result charon_insert:tags[index]];
    *tagCollectionOut = out;
    return noErr;
}

OSStatus CMTagCollectionCopyTagsOfCategories(CFAllocatorRef allocator, CMTagCollectionRef tagCollection, const CMTagCategory *categories,
                                             CMItemCount categoriesCount, CMTagCollectionRef *newCollectionOut)
{
    (void)allocator;
    CharonCMTagCollection *collection = charon_to(tagCollection);
    // Measured: a category count of zero is kCMTagCollectionError_ParamErr on the host, not an empty
    // collection.
    if (!collection || !categories || !newCollectionOut || !categoriesCount)
        return kCMTagCollectionError_ParamErr;
    CMTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, (CMMutableTagCollectionRef *)&out);
    if (status)
        return status;
    const CMTag *tags = [collection charon_tags];
    for (CMItemCount index = 0; index < categoriesCount; index++)
        for (NSUInteger one = 0; one < collection.charon_count; one++)
            if (tags[one].category == categories[index])
                [charon_to(out) charon_insert:tags[one]];
    *newCollectionOut = out;
    return noErr;
}

void CMTagCollectionApply(CMTagCollectionRef tagCollection, CMTagCollectionApplierFunction applier, void *context)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || !applier)
        return;
    const CMTag *tags = [collection charon_tags];
    for (NSUInteger index = 0; index < collection.charon_count; index++)
        applier(tags[index], context);
}

CMTag CMTagCollectionApplyUntil(CMTagCollectionRef tagCollection, CMTagCollectionTagFilterFunction filter, void *context)
{
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection || !filter)
        return kCMTagInvalid;
    const CMTag *tags = [collection charon_tags];
    for (NSUInteger index = 0; index < collection.charon_count; index++)
        if (filter(tags[index], context))
            return tags[index];
    return kCMTagInvalid;
}

CFDictionaryRef CMTagCollectionCopyAsDictionary(CMTagCollectionRef tagCollection, CFAllocatorRef allocator)
{
    (void)allocator;
    CharonCMTagCollection *collection = charon_to(tagCollection);
    if (!collection)
        return NULL;
    const CMTag *tags = [collection charon_tags];
    CFMutableArrayRef list = CFArrayCreateMutable(allocator, collection.charon_count, &kCFTypeArrayCallBacks);
    for (NSUInteger index = 0; index < collection.charon_count; index++) {
        // CFNumber, not an int: CFDictionaryCreate retains what it is given, and an int on the stack is
        // retained as a CF object, which is the SEGV ASan named in objc_retain from this line.
        CFNumberRef category = CFNumberCreate(allocator, kCFNumberSInt32Type, &(int){(int)tags[index].category});
        CFNumberRef value = CFNumberCreate(allocator, kCFNumberSInt32Type, &(int){(int)tags[index].value});
        CFNumberRef flags = CFNumberCreate(allocator, kCFNumberSInt32Type, &(int){(int)tags[index].dataType});
        const void *keys[] = {kCMTagCategoryKey, kCMTagValueKey, kCMTagDataTypeKey};
        const void *values[] = {category, value, flags};
        CFDictionaryRef entry = CFDictionaryCreate(allocator, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFArrayAppendValue(list, entry);
        CFRelease(entry);
        CFRelease(category);
        CFRelease(value);
        CFRelease(flags);
    }
    const void *keys[] = {CFSTR("tags")};
    const void *values[] = {list};
    CFDictionaryRef out = CFDictionaryCreate(allocator, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(list);
    return out;
}

OSStatus CMTagCollectionCreateFromDictionary(CFDictionaryRef dict, CFAllocatorRef allocator, CMTagCollectionRef *newCollectionOut)
{
    if (!dict || !newCollectionOut)
        return kCMTagCollectionError_ParamErr;
    CMTagCollectionRef out = NULL;
    OSStatus status = CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, (CMMutableTagCollectionRef *)&out);
    if (status)
        return status;
    CFArrayRef list = CFDictionaryGetValue(dict, CFSTR("tags"));
    if (list && CFGetTypeID(list) == CFArrayGetTypeID()) {
        CFIndex count = CFArrayGetCount(list);
        for (CFIndex index = 0; index < count; index++) {
            CFDictionaryRef entry = CFArrayGetValueAtIndex(list, index);
            if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID())
                continue;
            int category = 0, value = 0, flags = 0;
            CFNumberGetValue(CFDictionaryGetValue(entry, kCMTagCategoryKey), kCFNumberIntType, &category);
            CFNumberGetValue(CFDictionaryGetValue(entry, kCMTagValueKey), kCFNumberIntType, &value);
            CFNumberGetValue(CFDictionaryGetValue(entry, kCMTagDataTypeKey), kCFNumberIntType, &flags);
            CMTag tag = {(CMTagCategory)category, (CMTagDataType)flags, (uint32_t)value};
            [charon_to(out) charon_insert:tag];
        }
    }
    (void)allocator;
    *newCollectionOut = out;
    return noErr;
}
