#import "CharonCMTag26.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

// The CMTagCollection of iOS 17. A CMTag is three machine words with no lifetime of its own, so a
// collection is a sorted array of them and everything here is a search, an insert or a run over it; the
// class is the port's own behind 26.2's bridged CMTagCollectionRef. facts/CoreMedia/TagCollection.md

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

CF_EXPORT const CFStringRef kCMTagCategoryKey = CFSTR("category");
CF_EXPORT const CFStringRef kCMTagValueKey = CFSTR("value");
CF_EXPORT const CFStringRef kCMTagDataTypeKey = CFSTR("flags");

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
    return CMTagCollectionCreateMutable(allocator, (CFIndex)(source ? source.charon_count : 0), newMutableCollectionCopyOut);
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

