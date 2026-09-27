#import <Foundation/Foundation.h>

/* NSTermOfAddress, as the 26.2 header declares it, for a build whose SDK is older than the class.
   The lift lowers the availability of the SDK's own NSTermOfAddress.h once the registry carries it,
   and then the SDK's declaration is the one that is used; this is here so the file also builds
   against a release of the SDK that has no such header at all, and the two cannot both be visible. */
#if !__has_include(<Foundation/NSTermOfAddress.h>)
@interface NSTermOfAddress : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)neutral;
+ (instancetype)feminine;
+ (instancetype)masculine;
+ (instancetype)currentUser;
+ (instancetype)localizedForLanguageIdentifier:(NSString *)language withPronouns:(NSArray *)pronouns;
@property (nullable, readonly, copy) NSString *languageIdentifier;
@property (nullable, readonly, copy) NSArray *pronouns;
@end
#endif
