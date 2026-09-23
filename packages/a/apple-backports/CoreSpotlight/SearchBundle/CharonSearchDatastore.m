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

// This class runs inside searchd, not the process that launches it, so printf/NSLog to this
// process's own stdout/stderr reaches nobody - a file is the one channel proven to survive that
// boundary (the same one CTCellularData9.m's device test used earlier this session). Appends only;
// never assume the channel works without a line like this one actually landing on disk.
static void CharonSearchDatastoreLog(NSString *line)
{
    FILE *file = fopen("/private/var/backports/searchbundle.log", "a");
    if (!file)
        return;
    fprintf(file, "%s\n", line.UTF8String);
    fclose(file);
}

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
        return [NSArray array];
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
    CharonSearchDatastoreLog([NSString stringWithFormat:@"CharonSearchMatches: query class=%@", NSStringFromClass([query class])]);
    NSString *searchString = nil;
    @try {
        searchString = [(NSObject *)query valueForKey:@"searchString"];
    } @catch (NSException *exception) {
        CharonSearchDatastoreLog([NSString stringWithFormat:@"valueForKey:searchString raised %@: %@", exception.name, exception.reason]);
    }
    CharonSearchDatastoreLog([NSString stringWithFormat:@"searchString -> %@", searchString]);
    searchString = searchString ?: @"";
    if (searchString.length == 0)
        return [NSArray array];
    NSArray *items = CharonSearchLoadAllItems();
    CharonSearchDatastoreLog([NSString stringWithFormat:@"CharonSearchLoadAllItems -> %lu items", (unsigned long)items.count]);
    NSMutableArray *results = [NSMutableArray array];
    // Measured on device: this factory is a class method of SPContentResult (our own base class,
    // confirmed by apple.objc's inventory() reading the real __objc_classlist entry, not strings),
    // not SPSearchResult as an earlier strings-only pass attributed it - SPSearchResult only
    // happens to be SPContentResult's own superclass, a second wrong-owner mistake this pass
    // corrected on measurement rather than compounding on top of the first.
    Class resultClass = NSClassFromString(@"SPContentResult");
    SEL factory = sel_registerName("resultWithIdentifier:title:subtitle:summary:auxiliaryTitle:auxiliarySubtitle:actionURL:searchableContent:");
    if (!resultClass || ![resultClass respondsToSelector:factory]) {
        CharonSearchDatastoreLog([NSString stringWithFormat:@"SPContentResult factory unavailable: class=%@ responds=%d", resultClass, [resultClass respondsToSelector:factory]]);
        return [NSArray array];
    }
    for (id item in items) {
        id attributeSet = [item valueForKey:@"attributeSet"];
        // CSSearchableItemAttributeSet.m in this port does not carry contentDescription (measured
        // on device: an unentitled valueForKey: on it raises NSUnknownKeyException, not answers
        // nil) - title is the only field this port's attribute set actually backs, so it is the
        // only one matched against.
        NSString *title = [attributeSet valueForKey:@"title"] ?: @"";
        CharonSearchDatastoreLog([NSString stringWithFormat:@"item title=\"%@\"", title]);
        if ([title rangeOfString:searchString options:NSCaseInsensitiveSearch].location == NSNotFound)
            continue;
        NSString *identifier = [item valueForKey:@"uniqueIdentifier"];
        id result = ((id (*)(id, SEL, id, id, id, id, id, id, id, id))objc_msgSend)(
            resultClass, factory, identifier, title, nil, nil, nil, nil, nil, nil);
        CharonSearchDatastoreLog([NSString stringWithFormat:@"built result -> %@", result]);
        if (result)
            [results addObject:result];
    }
    return results;
}

// Temporary device-pass diagnostic: this class runs inside searchd, not the process that launched
static id CharonDisplayIdentifierForDomain(id self, SEL _cmd, unsigned int domain)
{
    CharonSearchDatastoreLog([NSString stringWithFormat:@"displayIdentifierForDomain: %u", domain]);
    return @"Charon";
}

static id CharonSearchDomains(id self, SEL _cmd)
{
    CharonSearchDatastoreLog(@"searchDomains called");
    return @[@999];
}

static void CharonPerformQuery(id self, SEL _cmd, id query, id resultsPipe)
{
    CharonSearchDatastoreLog([NSString stringWithFormat:@"performQuery:withResultsPipe: query=%@ resultsPipe=%@", query, resultsPipe]);
    NSArray *matches = CharonSearchMatches(query);
    // Measured on device: the object handed to withResultsPipe: is the query object itself
    // (an SDSearchQuery, defined in searchd's own binary, not the shared cache - not
    // SPSearchResultSection, which was a strings-proximity guess and never checked against what
    // this parameter's real class actually answers to). Its real, required protocol is
    // <SPSearchResultsPipe>, and the push method is -appendResults:, not -addResults: -
    // SPSearchResultSection happens to implement a same-shaped -addResults: for an unrelated
    // reason, which is exactly how a wrong name keeps looking plausible.
    CharonSearchDatastoreLog([NSString stringWithFormat:@"matches.count=%lu resultsPipe respondsToAppendResults=%d",
                              (unsigned long)matches.count, [resultsPipe respondsToSelector:sel_registerName("appendResults:")]]);
    if (matches.count == 0 || !resultsPipe)
        return;
    ((void (*)(id, SEL, id))objc_msgSend)(resultsPipe, sel_registerName("appendResults:"), matches);
    CharonSearchDatastoreLog(@"appendResults: sent");
}

__attribute__((constructor))
static void CharonSearchDatastoreRegister(void)
{
    CharonSearchDatastoreLog(@"CharonSearchDatastoreRegister constructor entered");
    if (NSClassFromString(@"CharonSearchDatastore")) {
        CharonSearchDatastoreLog(@"class already registered, skipping");
        return;
    }
    // SPSearchDatastore is a protocol, not a class - NSClassFromString on it answers nil and a
    // plain NSObject fallback is not what NotesDatastore itself subclasses, which is why searchd
    // silently ignored one (measured on device: no crash, no error, -searchDomains simply never
    // called). NotesDatastore's own binary imports _OBJC_CLASS_$_SPContentResult and nothing else
    // SP-prefixed (macho.imported_symbols), so that is the real base class.
    Class base = NSClassFromString(@"SPContentResult") ?: [NSObject class];
    CharonSearchDatastoreLog([NSString stringWithFormat:@"base class SPContentResult -> %@", base]);
    Class cls = objc_allocateClassPair(base, "CharonSearchDatastore", 0);
    if (!cls) {
        CharonSearchDatastoreLog(@"objc_allocateClassPair failed");
        return;
    }
    class_addMethod(cls, sel_registerName("displayIdentifierForDomain:"), (IMP)CharonDisplayIdentifierForDomain, "@12@0:4I8");
    class_addMethod(cls, sel_registerName("searchDomains"), (IMP)CharonSearchDomains, "@8@0:4");
    class_addMethod(cls, sel_registerName("performQuery:withResultsPipe:"), (IMP)CharonPerformQuery, "v16@0:4@8@12");
    // objc_allocateClassPair over SPContentResult does not itself grant <SPSearchDatastore>
    // conformance - NotesDatastore gets it from its own @interface declaration, which
    // class_addMethod alone does not reproduce. The identical gap already cost one silent failure
    // this pass, on the delegate side (SPDaemonQueryDelegate, fixed the same way in
    // searchbundle-probe.m) - applying it here too rather than assuming the method list alone is
    // enough a second time.
    Protocol *protocol = objc_getProtocol("SPSearchDatastore");
    CharonSearchDatastoreLog([NSString stringWithFormat:@"objc_getProtocol(SPSearchDatastore) -> %p", protocol]);
    if (protocol) {
        BOOL added = class_addProtocol(cls, protocol);
        CharonSearchDatastoreLog([NSString stringWithFormat:@"class_addProtocol -> %d", added]);
    }
    objc_registerClassPair(cls);
    CharonSearchDatastoreLog([NSString stringWithFormat:@"objc_registerClassPair done, CharonSearchDatastore is live, conformsToProtocol=%d",
                              protocol ? [cls conformsToProtocol:protocol] : -1]);
}
