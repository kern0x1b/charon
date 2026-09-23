// The principal class of org.charon.corespotlight.searchBundle, packaged separately from
// libCoreSpotlightBackports.dylib (see write_searchbundle in modules/apple/backports.lua) and
// installed at /System/Library/SearchBundles/, the directory this session measured
// Search.framework's own -_loadSearchBundles to scan
// (.agent-work/handoffs/2026-09-23-corespotlight-searchbundle-measurement.md).
//
// The protocol here is not guessed: NotesDatastore, MobileNotes.searchBundle's own principal
// class, was read with llvm-otool -oV (the tool that bypasses the extract()/otool defect this
// session also closed practically) and its selectors resolved against the iOS 6.1.3 shared cache
// directly, cross-checked against SPSearchDatastore's own required-method list rather than trusted
// from a nearby string. A CharonSearchDatastore instance is created by name, at runtime, as a real
// subclass of the release's own SPSearchDatastore (objc_allocateClassPair, the same technique this
// project already uses to extend private base classes it cannot import a header for), the way
// NotesDatastore itself is a real subclass rather than a bare NSObject that happens to answer the
// protocol's selectors.
// CSSearchableItem/CSSearchableItemAttributeSet are this port's own classes (CoreSpotlight.framework
// does not exist on iOS 6), resolved by name at runtime through the dlopen below - no
// <CoreSpotlight/CoreSpotlight.h> import here, and every value that crosses that boundary is typed
// id and read with valueForKey:, the way this project already handles a symbol a real SDK header
// would otherwise bind at link time for a class this specific binary must not require.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// Must match CSSearchableIndex.m's CharonSpotlightSharedRoot exactly - duplicated as a literal
// rather than linked, since this bundle is built and installed on its own (write_searchbundle),
// not against one specific band of libCoreSpotlightBackports.dylib.
static NSString *const CharonSpotlightSharedRoot = @"/var/mobile/Library/Caches/org.charon.corespotlight";

// CSSearchableItem is this port's own class, not Apple's - iOS 6 carries no CoreSpotlight.framework
// at all - so unarchiving one needs the class registered first, which only happens once the band's
// own dylib is loaded. The install path a device's own postinst keeps linked regardless of which
// band answers this release, so this dlopen reaches the right implementation without the bundle
// needing to be rebuilt or relinked per band.
static void CharonSearchLoadClasses(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/usr/lib/charon/org.charon.apple-backports/libCoreSpotlightBackports.dylib", RTLD_LAZY);
    });
}

static NSArray *CharonSearchLoadAllItems(void)
{
    CharonSearchLoadClasses();
    Class itemClass = NSClassFromString(@"CSSearchableItem");
    if (!itemClass)
        return @[];
    NSMutableArray *items = [NSMutableArray array];
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *application in [files contentsOfDirectoryAtPath:CharonSpotlightSharedRoot error:NULL]) {
        NSString *appDirectory = [CharonSpotlightSharedRoot stringByAppendingPathComponent:application];
        for (NSString *name in [files contentsOfDirectoryAtPath:appDirectory error:NULL]) {
            if (![name.pathExtension isEqualToString:@"plist"])
                continue;
            NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:[appDirectory stringByAppendingPathComponent:name]];
            NSDictionary<NSString *, NSData *> *entries = disk[@"entries"];
            for (NSData *archived in entries.allValues) {
                @try {
                    id item = [NSKeyedUnarchiver unarchiveObjectWithData:archived];
                    if ([item isKindOfClass:itemClass])
                        [items addObject:item];
                } @catch (__unused NSException *exception) {
                }
            }
        }
    }
    return items;
}

static NSArray *CharonSearchMatches(id query)
{
    NSString *searchString = [(NSObject *)query valueForKey:@"searchString"] ?: @"";
    if (searchString.length == 0)
        return @[];
    NSMutableArray *results = [NSMutableArray array];
    Class resultClass = NSClassFromString(@"SPSearchResult");
    SEL factory = sel_registerName("resultWithIdentifier:title:subtitle:summary:auxiliaryTitle:auxiliarySubtitle:actionURL:searchableContent:");
    if (!resultClass || ![resultClass respondsToSelector:factory])
        return @[];
    for (id item in CharonSearchLoadAllItems()) {
        id attributeSet = [item valueForKey:@"attributeSet"];
        NSString *title = [attributeSet valueForKey:@"title"] ?: @"";
        NSString *description = [attributeSet valueForKey:@"contentDescription"] ?: @"";
        if ([title rangeOfString:searchString options:NSCaseInsensitiveSearch].location == NSNotFound &&
            [description rangeOfString:searchString options:NSCaseInsensitiveSearch].location == NSNotFound)
            continue;
        NSString *identifier = [item valueForKey:@"uniqueIdentifier"];
        id result = ((id (*)(id, SEL, id, id, id, id, id, id, id, id))objc_msgSend)(
            resultClass, factory, identifier, title, description, nil, nil, nil, nil, nil);
        if (result)
            [results addObject:result];
    }
    return results;
}

static id CharonDisplayIdentifierForDomain(id self, SEL _cmd, unsigned int domain)
{
    return @"Charon";
}

static id CharonSearchDomains(id self, SEL _cmd)
{
    return @[@0];
}

static void CharonPerformQuery(id self, SEL _cmd, id query, id resultsPipe)
{
    NSArray *matches = CharonSearchMatches(query);
    if (matches.count == 0 || !resultsPipe)
        return;
    ((void (*)(id, SEL, id))objc_msgSend)(resultsPipe, sel_registerName("addResults:"), matches);
}

__attribute__((constructor))
static void CharonSearchDatastoreRegister(void)
{
    if (NSClassFromString(@"CharonSearchDatastore"))
        return;
    Class base = NSClassFromString(@"SPSearchDatastore") ?: [NSObject class];
    Class cls = objc_allocateClassPair(base, "CharonSearchDatastore", 0);
    if (!cls)
        return;
    class_addMethod(cls, sel_registerName("displayIdentifierForDomain:"), (IMP)CharonDisplayIdentifierForDomain, "@12@0:4I8");
    class_addMethod(cls, sel_registerName("searchDomains"), (IMP)CharonSearchDomains, "@8@0:4");
    class_addMethod(cls, sel_registerName("performQuery:withResultsPipe:"), (IMP)CharonPerformQuery, "v16@0:4@8@12");
    objc_registerClassPair(cls);
}
