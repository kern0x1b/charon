#import <CoreMedia/CoreMedia.h>
#import <CoreMedia/CMTag.h>
#import <CoreMedia/CMTagCollection.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

// The port's CMTagCollection, built as its own image, against the host's own CoreMedia. The port keeps
// Apple's names, so the two are two definitions of one name: the calls below reach the system
// framework, and the same names reached through the port's handle - opened RTLD_LOCAL | RTLD_FIRST, so
// dlsym searches that image alone - are the port's. Nothing is renamed and no system header is touched.
//
// __typeof__ gives every binding the host's own type, so the twenty-four lines of BIND cannot drift from
// the header and there is no second spelling of a name to shadow or to prefix twice.

static int failures, checks;
static void *port;

// The three serialisation keys, from the host, read once through the default handle.
static void readKeys(void)
{
    static const char *names[] = {"kCMTagCategoryKey", "kCMTagValueKey", "kCMTagDataTypeKey"};
    CFStringRef values[] = {kCMTagCategoryKey, kCMTagValueKey, kCMTagDataTypeKey};
    for (size_t index = 0; index < 3; index++) {
        char text[256] = {0};
        if (values[index])
            CFStringGetCString(values[index], text, sizeof text, kCFStringEncodingUTF8);
        printf("%s = \"%s\"\n", names[index], text);
    }
}

static CMTag tag(CMTagCategory category, CMTagDataType type, uint64_t value)
{
    CMTag made = {category, type, value};
    return made;
}

static NSString *shown(CMTag one)
{
    return [NSString stringWithFormat:@"%d/%u/%llu", (int)one.category, (unsigned)one.dataType, (unsigned long long)one.value];
}

typedef OSStatus (*GetTagsFn)(CMTagCollectionRef, CMTag *, CMItemCount, CMItemCount *);
typedef CMItemCount (*GetCountFn)(CMTagCollectionRef);

// A port's collection only ever goes to the port's own entry points and a host's only to the host's:
// one collection object is the host's CoreMedia's to interpret or the port's, never both, and handing
// the port's to the host's is the objc_msgSend fault the differential first died of.
static NSString *listed(CMTagCollectionRef collection, GetTagsFn getTags, GetCountFn getCount)
{
    if (!collection)
        return @"(null)";
    CMTag buffer[16] = {{0}};
    CMItemCount copied = 99;
    OSStatus status = getTags(collection, buffer, 16, &copied);
    NSMutableString *out = [NSMutableString stringWithFormat:@"%lu tags %d", (unsigned long)getCount(collection), status];
    for (CMItemCount index = 0; index < copied; index++)
        [out appendFormat:@" %@", shown(buffer[index])];
    return out;
}

static void same(const char *name, NSString *system, NSString *ported)
{
    checks++;
    if (![system isEqualToString:ported]) {
        failures++;
        if (failures < 30)
            printf("DIFFERENT %s:\n  system %s\n  port   %s\n", name, system.UTF8String, ported.UTF8String);
    }
}

// ARC will not let a block literal be cast to a C function pointer, so the appliers and filters are
// plain C functions with their state in file-scope variables, as the two filters above already are.
static NSMutableString *charonSeen;

static void charonAppend(CMTag value, void *context)
{
    (void)context;
    [charonSeen appendFormat:@"%d/%u/%llu;", (int)value.category, (unsigned)value.dataType, (unsigned long long)value.value];
}

static Boolean charonStopAtTrackID(CMTag value, void *context)
{
    (void)context;
    return value.category == kCMTagCategory_TrackID ? true : false;
}

static Boolean charonNever(CMTag value, void *context)
{
    (void)value; (void)context;
    return false;
}

static Boolean notMediaType(CMTag value, void *context) { (void)context; return value.category != kCMTagCategory_MediaType; }
static Boolean onlyTrackID(CMTag value, void *context) { (void)context; return value.category == kCMTagCategory_TrackID; }

#define BIND(name) __typeof__(&name) port_##name = (__typeof__(&name))dlsym(port, #name); \
    if (!port_##name) { printf("missing %s in the port image\n", #name); return 1; }

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        printf("probing %s\n", argv[1]);
        port = dlopen(argc > 1 ? argv[1] : "libCharonCMTag.dylib", RTLD_LOCAL | RTLD_FIRST);
        if (!port) {
            printf("dlopen failed: %s\n", dlerror());
            return 2;
        }
        printf("bound all\n");
        BIND(CMTagCollectionGetTypeID)
        BIND(CMTagCollectionCreate)
        BIND(CMTagCollectionCreateMutable)
        BIND(CMTagCollectionCreateCopy)
        BIND(CMTagCollectionCreateMutableCopy)
        BIND(CMTagCollectionCopyDescription)
        BIND(CMTagCollectionGetCount)
        BIND(CMTagCollectionIsEmpty)
        BIND(CMTagCollectionContainsTag)
        BIND(CMTagCollectionContainsCategory)
        BIND(CMTagCollectionContainsTagsOfCollection)
        BIND(CMTagCollectionContainsSpecifiedTags)
        BIND(CMTagCollectionGetCountOfCategory)
        BIND(CMTagCollectionGetTags)
        BIND(CMTagCollectionGetTagsWithCategory)
        BIND(CMTagCollectionGetTagsWithFilterFunction)
        BIND(CMTagCollectionCountTagsWithFilterFunction)
        BIND(CMTagCollectionAddTag)
        BIND(CMTagCollectionRemoveTag)
        BIND(CMTagCollectionRemoveAllTags)
        BIND(CMTagCollectionRemoveAllTagsOfCategory)
        BIND(CMTagCollectionAddTagsFromCollection)
        BIND(CMTagCollectionAddTagsFromArray)
        BIND(CMTagCollectionCreateDifference)
        BIND(CMTagCollectionCreateExclusiveOr)
        BIND(CMTagCollectionCreateUnion)
        BIND(CMTagCollectionCreateIntersection)
        BIND(CMTagCollectionCopyTagsOfCategories)
        BIND(CMTagCollectionApply)
        BIND(CMTagCollectionApplyUntil)
        BIND(CMTagCollectionCopyAsDictionary)
        BIND(CMTagCollectionCreateFromDictionary)

        printf("bound 24\n");
        CMTag tags[] = {
            tag(kCMTagCategory_MediaType, kCMTagDataType_OSType, 'vide'),
            tag(kCMTagCategory_MediaType, kCMTagDataType_OSType, 'soun'),
            tag(kCMTagCategory_TrackID, kCMTagDataType_SInt64, 7),
            tag(kCMTagCategory_PixelFormat, kCMTagDataType_Flags, 3),
            tag(kCMTagCategory_PackingType, kCMTagDataType_OSType, 0),
        };
        CMTag missing = tag(kCMTagCategory_TrackID, kCMTagDataType_SInt64, 99);
        CMTag extra = tag(kCMTagCategory_ChannelID, kCMTagDataType_SInt64, 5);
        CMTag more[2] = {tag(kCMTagCategory_VideoLayerID, kCMTagDataType_SInt64, 1), tag(kCMTagCategory_VideoLayerID, kCMTagDataType_SInt64, 2)};
        static const CMTagCategory categories[] = {kCMTagCategory_MediaType, kCMTagCategory_TrackID, kCMTagCategory_Undefined};
        static const CMItemCount counts[] = {0, 1, 3, 5};
        char label[96];

        for (size_t index = 0; index < sizeof counts / sizeof *counts; index++) {
            CMTagCollectionRef system = NULL, ported = NULL;
            snprintf(label, sizeof label, "Create %lu tags", (unsigned long)counts[index]);
            printf("case %d\n", (int)index);
            same(label,
                 [NSString stringWithFormat:@"%d %@", CMTagCollectionCreate(kCFAllocatorDefault, tags, counts[index], &system), listed(system, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                 [NSString stringWithFormat:@"%d %@", port_CMTagCollectionCreate(kCFAllocatorDefault, tags, counts[index], &ported), listed(ported, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);

            CMTagCollectionRef systemCopy = NULL, portCopy = NULL;
            CMTagCollectionCreateCopy(system, NULL, &systemCopy);
            port_CMTagCollectionCreateCopy(ported, NULL, &portCopy);
            same("CreateCopy", listed(systemCopy, CMTagCollectionGetTags, CMTagCollectionGetCount), listed(portCopy, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount));

            same("GetTypeID", [NSString stringWithFormat:@"%d", CMTagCollectionGetTypeID() != 0],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionGetTypeID() != 0]);
            {
                CFStringRef systemText = CMTagCollectionCopyDescription(NULL, system);
                CFStringRef portText = port_CMTagCollectionCopyDescription(NULL, ported);
                same("CopyDescription", systemText ? (__bridge NSString *)systemText : @"(null)",
                     portText ? (__bridge NSString *)portText : @"(null)");
            }
            same("GetCount", [NSString stringWithFormat:@"%lu", (unsigned long)CMTagCollectionGetCount(system)],
                 [NSString stringWithFormat:@"%lu", (unsigned long)port_CMTagCollectionGetCount(ported)]);

            same("IsEmpty", [NSString stringWithFormat:@"%d", CMTagCollectionIsEmpty(system)],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionIsEmpty(ported)]);
            for (size_t one = 0; one < sizeof tags / sizeof *tags; one++) {
                same("ContainsTag", [NSString stringWithFormat:@"%d", CMTagCollectionContainsTag(system, tags[one])],
                     [NSString stringWithFormat:@"%d", port_CMTagCollectionContainsTag(ported, tags[one])]);
            }
            same("ContainsTag missing", [NSString stringWithFormat:@"%d", CMTagCollectionContainsTag(system, missing)],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionContainsTag(ported, missing)]);
            for (size_t one = 0; one < 3; one++) {
                same("GetCountOfCategory", [NSString stringWithFormat:@"%lu", (unsigned long)CMTagCollectionGetCountOfCategory(system, categories[one])],
                     [NSString stringWithFormat:@"%lu", (unsigned long)port_CMTagCollectionGetCountOfCategory(ported, categories[one])]);
                same("ContainsCategory", [NSString stringWithFormat:@"%d", CMTagCollectionContainsCategory(system, categories[one])],
                     [NSString stringWithFormat:@"%d", port_CMTagCollectionContainsCategory(ported, categories[one])]);
            }
            same("ContainsTagsOfCollection", [NSString stringWithFormat:@"%d", CMTagCollectionContainsTagsOfCollection(system, systemCopy)],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionContainsTagsOfCollection(ported, portCopy)]);
            same("ContainsSpecifiedTags", [NSString stringWithFormat:@"%d", CMTagCollectionContainsSpecifiedTags(system, tags, counts[index])],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionContainsSpecifiedTags(ported, tags, counts[index])]);

            for (CMItemCount size = 0; size <= 6; size++) {
                CMTag systemBuffer[8] = {{0}}, portBuffer[8] = {{0}};
                CMItemCount systemCopied = 99, portCopied = 99;
                OSStatus a = CMTagCollectionGetTags(system, systemBuffer, size, &systemCopied);
                OSStatus b = port_CMTagCollectionGetTags(ported, portBuffer, size, &portCopied);
                NSMutableString *mine = [NSMutableString stringWithFormat:@"%d %lu", a, (unsigned long)systemCopied];
                NSMutableString *theirs = [NSMutableString stringWithFormat:@"%d %lu", b, (unsigned long)portCopied];
                for (CMItemCount slot = 0; slot < size; slot++) {
                    [mine appendFormat:@" %@", shown(systemBuffer[slot])];
                    [theirs appendFormat:@" %@", shown(portBuffer[slot])];
                }
                same("GetTags", mine, theirs);

                CMTag systemByCategory[8] = {{0}}, portByCategory[8] = {{0}};
                systemCopied = portCopied = 99;
                a = CMTagCollectionGetTagsWithCategory(system, kCMTagCategory_MediaType, systemByCategory, size, &systemCopied);
                b = port_CMTagCollectionGetTagsWithCategory(ported, kCMTagCategory_MediaType, portByCategory, size, &portCopied);
                mine = [NSMutableString stringWithFormat:@"%d %lu", a, (unsigned long)systemCopied];
                theirs = [NSMutableString stringWithFormat:@"%d %lu", b, (unsigned long)portCopied];
                for (CMItemCount slot = 0; slot < size; slot++) {
                    [mine appendFormat:@" %@", shown(systemByCategory[slot])];
                    [theirs appendFormat:@" %@", shown(portByCategory[slot])];
                }
                same("GetTagsWithCategory", mine, theirs);
            }

            for (int which = 0; which < 2; which++) {
                CMTagCollectionTagFilterFunction filter = which ? onlyTrackID : notMediaType;
                same("CountTagsWithFilter", [NSString stringWithFormat:@"%lu", (unsigned long)CMTagCollectionCountTagsWithFilterFunction(system, filter, NULL)],
                     [NSString stringWithFormat:@"%lu", (unsigned long)port_CMTagCollectionCountTagsWithFilterFunction(ported, filter, NULL)]);
                CMTag systemBuffer[8] = {{0}}, portBuffer[8] = {{0}};
                CMItemCount systemCopied = 99, portCopied = 99;
                OSStatus a = CMTagCollectionGetTagsWithFilterFunction(system, systemBuffer, 8, &systemCopied, filter, NULL);
                OSStatus b = port_CMTagCollectionGetTagsWithFilterFunction(ported, portBuffer, 8, &portCopied, filter, NULL);
                NSMutableString *mine = [NSMutableString stringWithFormat:@"%d %lu", a, (unsigned long)systemCopied];
                NSMutableString *theirs = [NSMutableString stringWithFormat:@"%d %lu", b, (unsigned long)portCopied];
                for (CMItemCount slot = 0; slot < 8; slot++) {
                    if (slot < systemCopied) [mine appendFormat:@" %@", shown(systemBuffer[slot])];
                    if (slot < portCopied) [theirs appendFormat:@" %@", shown(portBuffer[slot])];
                }
                same("GetTagsWithFilterFunction", mine, theirs);
            }

            CMMutableTagCollectionRef systemMutable = NULL, portMutable = NULL;
            CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, &systemMutable);
            port_CMTagCollectionCreateMutable(kCFAllocatorDefault, 0, &portMutable);
            CMMutableTagCollectionRef systemMutableCopy = NULL, portMutableCopy = NULL;
            CMTagCollectionCreateMutableCopy(system, NULL, &systemMutableCopy);
            port_CMTagCollectionCreateMutableCopy(ported, NULL, &portMutableCopy);
            same("CreateMutableCopy", listed(systemMutableCopy, CMTagCollectionGetTags, CMTagCollectionGetCount),
                 listed(portMutableCopy, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount));
            for (size_t one = 0; one < sizeof tags / sizeof *tags; one++)
                same("AddTag", [NSString stringWithFormat:@"%d", CMTagCollectionAddTag(systemMutable, tags[one])],
                     [NSString stringWithFormat:@"%d", port_CMTagCollectionAddTag(portMutable, tags[one])]);
            same("AddTag", [NSString stringWithFormat:@"%d", CMTagCollectionAddTag(systemMutable, extra)],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionAddTag(portMutable, extra)]);
            same("RemoveTag missing", [NSString stringWithFormat:@"%d", CMTagCollectionRemoveTag(systemMutable, missing)],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionRemoveTag(portMutable, missing)]);
            same("RemoveTag present", [NSString stringWithFormat:@"%d %@", CMTagCollectionRemoveTag(systemMutable, tags[0]), listed(systemMutable, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                 [NSString stringWithFormat:@"%d %@", port_CMTagCollectionRemoveTag(portMutable, tags[0]), listed(portMutable, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
            same("RemoveAllTagsOfCategory", [NSString stringWithFormat:@"%d %@", CMTagCollectionRemoveAllTagsOfCategory(systemMutable, kCMTagCategory_MediaType), listed(systemMutable, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                 [NSString stringWithFormat:@"%d %@", port_CMTagCollectionRemoveAllTagsOfCategory(portMutable, kCMTagCategory_MediaType), listed(portMutable, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
            same("AddTagsFromCollection", [NSString stringWithFormat:@"%d %@", CMTagCollectionAddTagsFromCollection(systemMutable, systemCopy), listed(systemMutable, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                 [NSString stringWithFormat:@"%d %@", port_CMTagCollectionAddTagsFromCollection(portMutable, portCopy), listed(portMutable, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
            same("AddTagsFromArray", [NSString stringWithFormat:@"%d %@", CMTagCollectionAddTagsFromArray(systemMutable, more, 2), listed(systemMutable, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                 [NSString stringWithFormat:@"%d %@", port_CMTagCollectionAddTagsFromArray(portMutable, more, 2), listed(portMutable, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
            same("RemoveAllTags", [NSString stringWithFormat:@"%d %@", CMTagCollectionRemoveAllTags(systemMutable), listed(systemMutable, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                 [NSString stringWithFormat:@"%d %@", port_CMTagCollectionRemoveAllTags(portMutable), listed(portMutable, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
            {
                CMItemCount systemBefore = CMTagCollectionGetCount(systemMutable);
                CMItemCount portBefore = port_CMTagCollectionGetCount(portMutable);
                OSStatus systemStatus = CMTagCollectionAddTag(systemMutable, kCMTagInvalid);
                OSStatus portStatus = port_CMTagCollectionAddTag(portMutable, kCMTagInvalid);
                same("AddTag kCMTagInvalid", [NSString stringWithFormat:@"%d count %lu -> %lu", systemStatus,
                                              (unsigned long)systemBefore, (unsigned long)CMTagCollectionGetCount(systemMutable)],
                     [NSString stringWithFormat:@"%d count %lu -> %lu", portStatus,
                      (unsigned long)portBefore, (unsigned long)port_CMTagCollectionGetCount(portMutable)]);
                const CMTag *portInvalid = dlsym(port, "port_kCMTagInvalid");
                same("kCMTagInvalid value", [NSString stringWithFormat:@"%d/%u/%llu", (int)kCMTagInvalid.category,
                                             (unsigned)kCMTagInvalid.dataType, (unsigned long long)kCMTagInvalid.value],
                     [NSString stringWithFormat:@"%d/%u/%llu", (int)portInvalid->category,
                      (unsigned)portInvalid->dataType, (unsigned long long)portInvalid->value]);
            }
            {
                // the set algebra, the category filter, the two appliers and the dictionary form
                CMTagCollectionRef systemOther = NULL, portOther = NULL, systemLeft = NULL, portLeft = NULL;
                CMItemCount half = counts[index] < 3 ? counts[index] : 3;
                CMTagCollectionCreate(kCFAllocatorDefault, tags, half, &systemLeft);
                port_CMTagCollectionCreate(kCFAllocatorDefault, tags, half, &portLeft);
                CMTagCollectionCreate(kCFAllocatorDefault, tags, 2, &systemOther);
                port_CMTagCollectionCreate(kCFAllocatorDefault, tags, 2, &portOther);
                typedef OSStatus (*SetOp)(CMTagCollectionRef, CMTagCollectionRef, CMTagCollectionRef *);
                SetOp systemOps[] = {CMTagCollectionCreateUnion, CMTagCollectionCreateIntersection,
                                     CMTagCollectionCreateDifference, CMTagCollectionCreateExclusiveOr};
                SetOp portOps[] = {port_CMTagCollectionCreateUnion, port_CMTagCollectionCreateIntersection,
                                    port_CMTagCollectionCreateDifference, port_CMTagCollectionCreateExclusiveOr};

                const char *opNames[] = {"Union", "Intersection", "Difference", "ExclusiveOr"};
                for (int op = 0; op < 4; op++) {
                    CMTagCollectionRef systemOut = NULL, portOut = NULL;
                    OSStatus a = systemOps[op](systemLeft, systemOther, &systemOut);
                    OSStatus b = portOps[op](portLeft, portOther, &portOut);
                    same(opNames[op], [NSString stringWithFormat:@"%d %@", a, listed(systemOut, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                         [NSString stringWithFormat:@"%d %@", b, listed(portOut, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
                    if (systemOut) CFRelease(systemOut);
                    if (portOut) CFRelease(portOut);
                }
                static const CMTagCategory wanted[] = {kCMTagCategory_MediaType, kCMTagCategory_TrackID, kCMTagCategory_Undefined};
                for (CMItemCount howMany = 0; howMany <= 3; howMany++) {
                    CMTagCollectionRef systemOut = NULL, portOut = NULL;
                    OSStatus a = CMTagCollectionCopyTagsOfCategories(NULL, systemLeft, wanted, howMany, &systemOut);
                    OSStatus b = port_CMTagCollectionCopyTagsOfCategories(NULL, portLeft, wanted, howMany, &portOut);
                    same("CopyTagsOfCategories", [NSString stringWithFormat:@"%d %@", a, listed(systemOut, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                         [NSString stringWithFormat:@"%d %@", b, listed(portOut, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
                    if (systemOut) CFRelease(systemOut);
                    if (portOut) CFRelease(portOut);
                }
                {
                    charonSeen = [NSMutableString string];
                    CMTagCollectionApply(systemLeft, charonAppend, NULL);
                    NSString *systemSeen = charonSeen;
                    charonSeen = [NSMutableString string];
                    port_CMTagCollectionApply(portLeft, charonAppend, NULL);
                    same("Apply", systemSeen, charonSeen);
                    same("ApplyUntil found", shown(CMTagCollectionApplyUntil(systemLeft, charonStopAtTrackID, NULL)),
                         shown(port_CMTagCollectionApplyUntil(portLeft, charonStopAtTrackID, NULL)));
                    same("ApplyUntil missed", shown(CMTagCollectionApplyUntil(systemLeft, charonNever, NULL)),
                         shown(port_CMTagCollectionApplyUntil(portLeft, charonNever, NULL)));
                }
                {
                    CFDictionaryRef systemDict = CMTagCollectionCopyAsDictionary(systemLeft, NULL);
                    CFDictionaryRef portDict = port_CMTagCollectionCopyAsDictionary(portLeft, NULL);
                    same("CopyAsDictionary", [NSString stringWithFormat:@"%@", systemDict ? (__bridge NSDictionary *)systemDict : @"(null)"],
                         [NSString stringWithFormat:@"%@", portDict ? (__bridge NSDictionary *)portDict : @"(null)"]);
                    CMTagCollectionRef systemBack = NULL, portBack = NULL;
                    OSStatus a = CMTagCollectionCreateFromDictionary(systemDict, NULL, &systemBack);
                    OSStatus b = port_CMTagCollectionCreateFromDictionary(portDict, NULL, &portBack);
                    same("CreateFromDictionary", [NSString stringWithFormat:@"%d %@", a, listed(systemBack, CMTagCollectionGetTags, CMTagCollectionGetCount)],
                         [NSString stringWithFormat:@"%d %@", b, listed(portBack, port_CMTagCollectionGetTags, port_CMTagCollectionGetCount)]);
                    if (systemDict) CFRelease(systemDict);
                    if (portDict) CFRelease(portDict);
                    if (systemBack) CFRelease(systemBack);
                    if (portBack) CFRelease(portBack);
                }
                if (systemOther) CFRelease(systemOther);
                if (portOther) CFRelease(portOther);
                if (systemLeft) CFRelease(systemLeft);
                if (portLeft) CFRelease(portLeft);
            }
            same("Create no out", [NSString stringWithFormat:@"%d", CMTagCollectionCreate(kCFAllocatorDefault, tags, 2, NULL) != 0],
                 [NSString stringWithFormat:@"%d", port_CMTagCollectionCreate(kCFAllocatorDefault, tags, 2, NULL) != 0]);

            if (systemCopy) CFRelease(systemCopy);
            if (portCopy) CFRelease(portCopy);
            if (systemMutable) CFRelease(systemMutable);
            if (portMutable) CFRelease(portMutable);
            if (systemMutableCopy) CFRelease(systemMutableCopy);
            if (portMutableCopy) CFRelease(portMutableCopy);
            if (system) CFRelease(system);
            if (ported) CFRelease(ported);
        }
        readKeys();
        printf("%d checks, %d different\n", checks, failures);
    }
    return failures != 0;
}
