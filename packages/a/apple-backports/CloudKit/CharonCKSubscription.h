// What the subscription family of this package shares.
//
// The SDK's CKSubscription declares no initialiser at all - a caller is meant to build one of the
// three subclasses - so the base class's own designated initialiser, the one that takes the name the
// service will know it by, is declared here for the subclasses in the other files of this folder. It
// is the port's declaration and not the SDK's, which is why it is not in the registry: no SDK header
// names it, and the rule that covers such a name is R4 of .agents/skills/patch-merge, which says the
// lift's sets are re-measured in the same push.

#ifndef CHARON_CK_SUBSCRIPTION_H
#define CHARON_CK_SUBSCRIPTION_H

#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@interface CKQueryCursor (CharonCKBuilding)
// The cursor is the service's own token and nothing else, and the SDK's class declares no way to be
// built from one, so this is the initialiser the transport uses to hand the service's answer back to
// a caller. -serverChangeToken reads it out again.
- (instancetype)initWithToken:(NSData *)token;
- (NSData *)serverChangeToken;
@end

@interface CKSubscription (CharonCKBuilding)
- (instancetype)initWithSubscriptionID:(CKSubscriptionID)subscriptionID;
@end

// CKNotificationID is an empty class in the SDK: it declares no method at all, so the initialiser
// that gives one a name is declared here for the notification files of this folder.
@interface CKNotificationID (CharonCKBuilding)
- (instancetype)initWithNotificationName:(NSString *)notificationName object:(id)object;
@end

@interface CKShareParticipant (CharonCKBuilding)
- (instancetype)initWithType:(CKShareParticipantType)type;
@end

#endif
