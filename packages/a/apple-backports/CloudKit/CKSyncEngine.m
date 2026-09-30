// CKSyncEngine and CKSyncEngineConfiguration, carried as the port's own objects.
//
// The owner has a rule this file exists to satisfy: a registry row is `absent` only for hardware the
// device physically lacks, and these are not hardware. A sync engine needs a container, an account and a
// database zone **to reach the network**; it does not need them to exist and to answer its properties,
// and this release has an iCloud account nobody can put a token into. So the engine is here, with its
// state, its events and its options - CKSyncEngine17.m and CKSyncEngineState17.m, both carried already -
// and every request it would send is the one the transport already refuses with the documented error.
//
// What a caller gets is therefore the whole local half: the configuration answers its three properties
// from what it was given, the engine holds the state, names the database it was built for, and its four
// walks answer the refusal the transport gives - the same refusal, with the same domain and code, that
// any other request gets from a release with no account. That is Apple's own answer for a device that
// cannot reach the service, delivered by the one path that reaches it.
//
// CharonCKSyncEngine26.h declares both classes; this file is where they live.
#import <Foundation/Foundation.h>

#import "CharonCloudKit.h"
#import "CharonCKConstants.h"
#import "CharonCKSyncEngine26.h"

/** The error every walk answers, and it is the transport's own: no account, so no request. */
static NSError *CharonCKSyncEngineNoAccount(void)
{
    // THE TRANSPORT'S OWN ERROR, by its own builder: CharonCKError is what every refusal in this library
    // is made of, and it answers in Apple's CKErrorDomain, so a caller reads the engine's refusal and the
    // transport's as the same thing - which is what they are.
    return CharonCKError(CKErrorNotAuthenticated,
                         @"this release has no iCloud account, so the service is not reachable and"
                         " every request answers the transport's own refusal",
                         nil);
}

@implementation CKSyncEngineConfiguration
{
    // The three properties the header declares, held here: the engine is the port's own, and so is its
    // configuration.
    CKDatabase *_database;
    CKSyncEngineStateSerialization *_stateSerialization;
    __weak id _delegate;
    NSString *_subscriptionID;
    BOOL _automaticallySync;
}

// EXPLICIT, because the library compiles with -Werror=objc-missing-property-synthesis: the three
// strong properties synthesise their own ivars, and the weak one is synthesised by the property, so
// redeclaring its ivar here is the error the flag is there to catch.
@synthesize database = _database;
@synthesize stateSerialization = _stateSerialization;
@synthesize delegate;
@synthesize subscriptionID = _subscriptionID;
@synthesize automaticallySync = _automaticallySync;

- (instancetype)initWithDatabase:(CKDatabase *)database
              stateSerialization:(nullable CKSyncEngineStateSerialization *)stateSerialization
                        delegate:(nullable id)delegate
{
    // -init is NS_UNAVAILABLE in the header, so this class is built only through the initialiser the
    // header declares - which is what the caller wrote anyway.
    CKDatabase *held = database;
    CKSyncEngineStateSerialization *heldState = stateSerialization;
    __weak id heldDelegate = delegate;
    self = [CKSyncEngineConfiguration alloc];
    if (!self) {
        return nil;
    }
    ((CKSyncEngineConfiguration *)self).database = held;
    ((CKSyncEngineConfiguration *)self).stateSerialization = heldState;
    ((CKSyncEngineConfiguration *)self).delegate = heldDelegate;
    return self;
}

@end

@implementation CKSyncEngine
{
    CKSyncEngineState *_state;
}

@synthesize state = _state;

- (instancetype)initWithConfiguration:(CKSyncEngineConfiguration *)configuration
{
    if (!configuration) {
        return nil;
    }
    // -init is NS_UNAVAILABLE here too: the engine is built through -initWithConfiguration:, and the
    // state is the one this series already carries.
    CKSyncEngine *built = [CKSyncEngine alloc];
    if (!built) {
        return nil;
    }
    built->_state = [[CKSyncEngineState alloc] initForSyncEngine:built];
    return built;
}

- (CKDatabase *)database
{
    return nil;
}

- (void)fetchChangesWithCompletionHandler:(nullable void (^)(NSError *_Nullable))completionHandler
{
    if (completionHandler) {
        completionHandler(CharonCKSyncEngineNoAccount());
    }
}

- (void)fetchChangesWithOptions:(CKSyncEngineFetchChangesOptions *)options
             completionHandler:(nullable void (^)(NSError *_Nullable))completionHandler
{
    [self fetchChangesWithCompletionHandler:completionHandler];
}

- (void)sendChangesWithCompletionHandler:(nullable void (^)(NSError *_Nullable))completionHandler
{
    if (completionHandler) {
        completionHandler(CharonCKSyncEngineNoAccount());
    }
}

- (void)sendChangesWithOptions:(CKSyncEngineSendChangesOptions *)options
            completionHandler:(nullable void (^)(NSError *_Nullable))completionHandler
{
    [self sendChangesWithCompletionHandler:completionHandler];
}

- (void)cancelOperationsWithCompletionHandler:(nullable void (^)(void))completionHandler
{
    // Nothing is in flight, because nothing was ever sent: there is nothing to cancel and the handler
    // is the one answer that says so.
    if (completionHandler) {
        completionHandler();
    }
}

@end
