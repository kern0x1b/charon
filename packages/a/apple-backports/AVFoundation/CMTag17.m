#import "CharonCMTag26.h"
#import "CharonCMTagSupport.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>

// The CMTag functions of iOS 17, by the host's own measured answers (facts/CoreMedia/CMTag.md). Two of
// them are the host's quirks and are reproduced rather than tidied:
//
//  - the getters do not check the data type. CMTagGetOSTypeValue of an SInt64 tag is 7 and
//    CMTagGetSInt64Value of an OSType tag is 1986618469: one 64-bit field, read the same way.
//  - the description of an invalid tag has no closing brace. Measured byte by byte; see the facts.
//
// The comparison and hash live in CharonCMTagSupport.m with the collection's rules, so that this object
// and CMTagCollection17.o do not each carry a copy of the ordering.

CMTag CMTagMakeWithOSTypeValue( CMTagCategory category, FourCharCode value )
{
    CMTag tag = {category, kCMTagDataType_OSType, (uint32_t)value};
    return tag;
}

CMTag CMTagMakeWithSInt64Value( CMTagCategory category, int64_t value )
{
    CMTag tag = {category, kCMTagDataType_SInt64, (uint64_t)value};
    return tag;
}

CMTag CMTagMakeWithFlagsValue( CMTagCategory category, uint64_t value )
{
    CMTag tag = {category, kCMTagDataType_Flags, value};
    return tag;
}

CMTag CMTagMakeWithFloat64Value( CMTagCategory category, double value )
{
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    CMTag tag = {category, kCMTagDataType_Float64, bits};
    return tag;
}

CMTagDataType CMTagGetValueDataType( CMTag tag )
{
    return tag.dataType;
}

FourCharCode CMTagGetOSTypeValue( CMTag tag )
{
    return (FourCharCode)(uint32_t)tag.value;
}

int64_t CMTagGetSInt64Value( CMTag tag )
{
    return (int64_t)tag.value;
}

uint64_t CMTagGetFlagsValue( CMTag tag )
{
    return tag.value;
}

double CMTagGetFloat64Value( CMTag tag )
{
    double value;
    uint64_t bits = tag.value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

Boolean CMTagEqualToTag( CMTag tag1, CMTag tag2 )
{
    return charon_tag_equal(tag1, tag2);
}

Boolean CMTagHasOSTypeValue( CMTag tag )
{
    return tag.dataType == kCMTagDataType_OSType;
}

Boolean CMTagHasSInt64Value( CMTag tag )
{
    return tag.dataType == kCMTagDataType_SInt64;
}

Boolean CMTagHasFlagsValue( CMTag tag )
{
    return tag.dataType == kCMTagDataType_Flags;
}

Boolean CMTagHasFloat64Value( CMTag tag )
{
    return tag.dataType == kCMTagDataType_Float64;
}

CFComparisonResult CMTagCompare( CMTag tag1, CMTag tag2 )
{
    // A total order over the four fields, validity first. Measured on the host: two invalid tags are
    // equal, an invalid tag is less than a valid one whatever its category is, and beyond that it is
    // category, then data type, then value. It is NOT "an invalid tag equals everything" - the
    // 'vide' tag against kCMTagInvalid is 1, and the matrix of the five measured tags is symmetric and
    // antisymmetric on every pair.
    if (CMTagIsValid(tag1) != CMTagIsValid(tag2))
        return CMTagIsValid(tag1) ? kCFCompareGreaterThan : kCFCompareLessThan;
    if (charon_tag_is_less(tag1, tag2))
        return kCFCompareLessThan;
    return charon_tag_equal(tag1, tag2) ? kCFCompareEqualTo : kCFCompareGreaterThan;
}

CFHashCode CMTagHash( CMTag tag )
{
    // The host's hashes are CFHash of the three fields, measured: 930911443662 for the 'vide' tag,
    // 175247351123 for SInt64 7, 242338807774 for the invalid tag. CFHash is a CFString-compatible
    // hash, so the string of the fields is what gets hashed.
    CFMutableStringRef text = CFStringCreateMutable(NULL, 0);
    char buffer[32];
    snprintf(buffer, sizeof buffer, "%d%u%llu", (int)tag.category, (unsigned)tag.dataType, (unsigned long long)tag.value);
    CFStringAppendCString(text, buffer, kCFStringEncodingASCII);
    CFHashCode hash = CFHash(text);
    CFRelease(text);
    return hash;
}

CFDictionaryRef CMTagCopyAsDictionary( CMTag tag, CFAllocatorRef allocator )
{
    // A Float64's value travels as the double's bit pattern in a 64-bit integer - 1.5 is
    // 4609434218613702656 - which is what makes the round trip exact; measured.
    //
    // CFNumbers, not the addresses of integers. CFDictionaryCreate retains every key and value it is
    // given, so handing it &value made it retain the address of a stack slot - objc_retain on the tag's
    // own bytes - and the probe died there. The dictionary is a number's.
    unsigned category = (unsigned)tag.category;
    unsigned dataType = (unsigned)tag.dataType;
    uint64_t value = tag.value;
    CFNumberRef numbers[] = {
        CFNumberCreate(allocator, kCFNumberSInt32Type, &category),
        CFNumberCreate(allocator, kCFNumberSInt32Type, &dataType),
        CFNumberCreate(allocator, kCFNumberSInt64Type, &value),
    };
    const void *keys[] = {kCMTagCategoryKey, kCMTagDataTypeKey, kCMTagValueKey};
    const void *values[] = {numbers[0], numbers[1], numbers[2]};
    CFDictionaryRef out = CFDictionaryCreate(allocator, keys, values, 3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    for (size_t index = 0; index < 3; index++)
        if (numbers[index])
            CFRelease(numbers[index]);
    return out;
}

CMTag CMTagMakeFromDictionary( CFDictionaryRef dict )
{
    if (!dict || CFGetTypeID(dict) != CFDictionaryGetTypeID())
        return kCMTagInvalid;
    unsigned category = 0, dataType = 0;
    uint64_t value = 0;
    const void *wanted[] = {kCMTagCategoryKey, kCMTagDataTypeKey, kCMTagValueKey};
    unsigned *shorts[] = {&category, &dataType};
    uint64_t *wide = &value;
    for (int index = 0; index < 3; index++) {
        CFTypeRef held = CFDictionaryGetValue(dict, wanted[index]);
        if (!held || CFGetTypeID(held) != CFNumberGetTypeID())
            return kCMTagInvalid;
        if (index < 2) {
            if (!CFNumberGetValue((CFNumberRef)held, kCFNumberSInt32Type, (void **)shorts[index]))
                return kCMTagInvalid;
        } else if (!CFNumberGetValue((CFNumberRef)held, kCFNumberSInt64Type, (void **)wide)) {
            return kCMTagInvalid;
        }
    }
    CMTag tag = {(CMTagCategory)category, (CMTagDataType)dataType, value};
    return tag;
}

// The description, in the host's own shape: {category:'<four>' value:<v> <type>}, with values as
// 'xxxx' for OSType, 0x… for Flags, decimal for SInt64 and %.2f for Float64 - and with **no closing
// brace** for an invalid tag, which is what the host prints and is measured byte by byte.
static NSString *charon_category_text(CMTagCategory category)
{
    return [NSString stringWithFormat:@"%c%c%c%c", (char)(category >> 24), (char)(category >> 16), (char)(category >> 8), (char)category];
}

static NSString *charon_value_text(CMTag tag)
{
    switch (tag.dataType) {
    case kCMTagDataType_OSType:
        return [NSString stringWithFormat:@"'%@'", charon_category_text((CMTagCategory)(uint32_t)tag.value)];
    case kCMTagDataType_Flags:
        return [NSString stringWithFormat:@"0x%llx", (unsigned long long)tag.value];
    case kCMTagDataType_Float64: {
        double number;
        uint64_t bits = tag.value;
        memcpy(&number, &bits, sizeof number);
        return [NSString stringWithFormat:@"%.2f", number];
    }
    default:
        return [NSString stringWithFormat:@"%lld", (long long)tag.value];
    }
}

static NSString *charon_type_text(CMTagDataType type)
{
    switch (type) {
    case kCMTagDataType_OSType: return @"OSType";
    case kCMTagDataType_Flags: return @"flags";
    case kCMTagDataType_Float64: return @"Flt64";
    default: return @"int64";
    }
}

CFStringRef CMTagCopyDescription( CFAllocatorRef allocator, CMTag tag )
{
    (void)allocator;
    NSString *text;
    if (!CMTagIsValid(tag))
        text = [NSString stringWithFormat:@"{category:'%@'", charon_category_text(tag.category)];
    else
        text = [NSString stringWithFormat:@"{category:'%@' value:%@ <%@>}", charon_category_text(tag.category),
                                        charon_value_text(tag), charon_type_text(tag.dataType)];
    return (__bridge_retained CFStringRef)text;
}
