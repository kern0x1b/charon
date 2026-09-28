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

// The three serialisation keys, compared as the strings they are, and then used: the host builds its
// dictionary of a serialised collection under them, so looking each of the *port's* keys up in the
// host's own dictionary is what makes a wrong one fail. Printing them would not.
static void readKeys(const CFStringRef * const *portKeys)
{
    static const char *names[] = {"kCMTagCategoryKey", "kCMTagValueKey", "kCMTagDataTypeKey"};
    CFStringRef hostKeys[] = {kCMTagCategoryKey, kCMTagValueKey, kCMTagDataTypeKey};
    for (size_t index = 0; index < 3; index++) {
        const CFStringRef *portKey = portKeys[index];
        char hostText[256] = {0}, portText[256] = {0};
        if (hostKeys[index])
            CFStringGetCString(hostKeys[index], hostText, sizeof hostText, kCFStringEncodingUTF8);
        if (portKey && *portKey)
            CFStringGetCString(*portKey, portText, sizeof portText, kCFStringEncodingUTF8);
        printf("%s = \"%s\"\n", names[index], hostText);
        same(names[index], @(hostText), @(portText));
    }
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
#define BIND_KEY(symbol) const CFStringRef *port_##symbol = (const CFStringRef *)dlsym(port, "port_" #symbol); \
    if (!port_##symbol) { printf("missing port_%s in the port image\n", #symbol); return 1; }
        BIND_KEY(kCMTagCategoryKey)
        BIND_KEY(kCMTagValueKey)
        BIND_KEY(kCMTagDataTypeKey)
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
        const CFStringRef *thePortKeys[3] = {port_kCMTagCategoryKey, port_kCMTagValueKey, port_kCMTagDataTypeKey};
        readKeys(thePortKeys);
        printf("%d checks, %d different\n", checks, failures);
    }
    return failures != 0;
}
