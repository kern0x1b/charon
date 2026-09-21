#import <CallKit/CallKit.h>

typedef NS_ENUM(NSInteger, CharonCallEvent) {
    CharonCallEventAppeared,
    CharonCallEventChanged,
    CharonCallEventEnded
};

@interface CXAction ()
- (instancetype)charon_initWithUUID:(NSUUID *)UUID __attribute__((objc_method_family(init)));
@property (nonatomic, weak) CXProvider *charon_provider;
@property (nonatomic, weak) CXTransaction *charon_transaction;
@property (nonatomic, readonly) BOOL charon_fulfilled;
- (void)charon_setComplete:(BOOL)complete;
- (SEL)charon_performSelector;
// How long the action has to be fulfilled or failed, which is a property of
// the class and not of the transaction it goes in.
+ (NSTimeInterval)charon_timeout;
- (void)charon_timedOut;
@end

@interface CXCallAction ()
// The date the application gives to fulfillWithDateStarted:, -DateConnected:
// or -DateEnded:, which the provider reads off the action once the transaction
// is done. Fulfilling without one means the moment of the fulfilment.
@property (nonatomic) NSDate *charon_date;
- (void)charon_completeWithDate:(NSDate *)date;
@end

@interface CXCallUpdate ()
- (void)charon_applyOver:(CXCallUpdate *)previous;
@end

@interface CXTransaction ()
@property (nonatomic, weak) CXProvider *charon_provider;
- (void)charon_actionCompleted:(CXAction *)action;
@end

@interface CXCall ()
- (instancetype)charon_initWithUUID:(NSUUID *)UUID outgoing:(BOOL)outgoing __attribute__((objc_method_family(init)));
@property (nonatomic, weak) CXProvider *charon_provider;
@property (nonatomic, copy) CXCallUpdate *charon_update;
@property (nonatomic) NSDate *charon_dateStartedConnecting;
@property (nonatomic) NSDate *charon_dateConnected;
@property (nonatomic) NSDate *charon_dateEnded;
@property (nonatomic) CXCallEndedReason charon_endedReason;
@property (nonatomic) BOOL charon_muted;
@property (nonatomic, copy) NSUUID *charon_groupedWith;
- (void)charon_setOnHold:(BOOL)onHold;
- (void)charon_setHasConnected:(BOOL)hasConnected;
- (void)charon_setHasEnded:(BOOL)hasEnded;
- (CXCall *)charon_snapshot;
@end

@interface CXCallObserver ()
- (void)charon_callChanged:(CXCall *)call;
@end

@interface CXProvider ()
- (void)charon_execute:(CXTransaction *)transaction;
- (void)charon_removeTransaction:(CXTransaction *)transaction;
- (void)charon_actionTimedOut:(CXAction *)action;
- (BOOL)charon_isValid;
- (id<CXProviderDelegate>)charon_delegate;
// Where the system call screen is put up for a call the provider reports. The
// framework on its own draws nothing: the screen belongs to SpringBoard, and
// what reaches it is the tweak's business, not the library's.
- (void)charon_presentIncomingCall:(CXCall *)call;
@property (nonatomic, readonly) dispatch_queue_t charon_queue;
@end

// The one place in the process that knows which calls exist. On a release with
// CallKit this is callservicesd, one daemon for every application; iOS 6 runs
// no such daemon and gives no way to write one that another process would
// find, so the broker is per process: a provider and a call controller of the
// same application meet here, and an application never sees the calls of
// another. What crosses the process boundary is the telephony of the release,
// which the broker watches through CoreTelephony and hands to the observers
// beside the calls of the application itself.
@interface CharonCallBroker : NSObject

+ (instancetype)shared;

- (void)addProvider:(CXProvider *)provider;
- (void)removeProvider:(CXProvider *)provider;
- (CXProvider *)anyProvider;

- (void)addObserver:(CXCallObserver *)observer;
- (void)removeObserver:(CXCallObserver *)observer;

- (NSArray<CXCall *> *)calls;
- (CXCall *)callWithUUID:(NSUUID *)UUID;
- (NSArray<CXCall *> *)callsOfProvider:(CXProvider *)provider;

- (BOOL)addCall:(CXCall *)call;
- (void)applyAction:(CXAction *)action;
- (void)removeCall:(CXCall *)call;
- (void)callChanged:(CXCall *)call;

- (NSUInteger)groupsOfProvider:(CXProvider *)provider;

@end

extern NSError *charon_callkit_error(NSString *domain, NSInteger code);
