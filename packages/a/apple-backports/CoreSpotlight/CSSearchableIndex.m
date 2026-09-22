#import <CoreSpotlight/CoreSpotlight.h>

NSString * const CSIndexErrorDomain = @"CSIndexErrorDomain";

static NSError *CharonIndexingUnsupportedError(void)
{
    return [NSError errorWithDomain:CSIndexErrorDomain
                                code:CSIndexErrorCodeIndexingUnsupported
                            userInfo:@{NSLocalizedDescriptionKey: @"Indexing isn't supported on this device"}];
}

@interface CSSearchableIndex ()
@property (copy) NSString *charonName;
@end

@implementation CSSearchableIndex

@synthesize charonName = _charonName;

+ (BOOL)isIndexingAvailable
{
    return NO;
}

+ (instancetype)defaultSearchableIndex
{
    static CSSearchableIndex *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[CSSearchableIndex alloc] initWithName:@"__defaultIndex"];
    });
    return shared;
}

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name protectionClass:nil];
}

- (instancetype)initWithName:(NSString *)name protectionClass:(NSFileProtectionType)protectionClass
{
    if ((self = [super init]))
        self.charonName = name;
    return self;
}

- (void)indexSearchableItems:(NSArray<CSSearchableItem *> *)items completionHandler:(void (^)(NSError *))completionHandler
{
    if (completionHandler)
        completionHandler(CharonIndexingUnsupportedError());
}

- (void)deleteSearchableItemsWithIdentifiers:(NSArray<NSString *> *)identifiers completionHandler:(void (^)(NSError *))completionHandler
{
    if (completionHandler)
        completionHandler(CharonIndexingUnsupportedError());
}

- (void)deleteSearchableItemsWithDomainIdentifiers:(NSArray<NSString *> *)domainIdentifiers completionHandler:(void (^)(NSError *))completionHandler
{
    if (completionHandler)
        completionHandler(CharonIndexingUnsupportedError());
}

- (void)deleteAllSearchableItemsWithCompletionHandler:(void (^)(NSError *))completionHandler
{
    if (completionHandler)
        completionHandler(CharonIndexingUnsupportedError());
}

- (void)beginIndexBatch
{
}

- (void)endIndexBatchWithClientState:(NSData *)clientState completionHandler:(void (^)(NSError *))completionHandler
{
    if (completionHandler)
        completionHandler(CharonIndexingUnsupportedError());
}

- (void)fetchLastClientStateWithCompletionHandler:(void (^)(NSData *, NSError *))completionHandler
{
    if (completionHandler)
        completionHandler(nil, CharonIndexingUnsupportedError());
}

@end
