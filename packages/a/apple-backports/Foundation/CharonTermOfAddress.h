#import <Foundation/Foundation.h>

/* NSTermOfAddress of iOS 17.0, transcribed from the SDK 26.2 header because the SDK the package is
   compiled against does not declare it.

   The build resolves charon@iphoneos-sdk to 16.4 -- build-gate.lua names it and every line of a gate
   says `sdk=16.4` -- and an API that arrived after 16.4 has no @interface here. An @implementation
   written without one is a root class, and `[super init]` in it is an error. The 6.1.3 gate said so,
   in exactly this shape:

     the registry does not describe what the backports carry:
       listed as implemented, but nothing of that name is built: +[NSTermOfAddress currentUser]
       +[NSTermOfAddress feminine] +[NSTermOfAddress localizedForLanguageIdentifier:withPronouns:]
       +[NSTermOfAddress masculine] +[NSTermOfAddress neutral] NSTermOfAddress
       NSTermOfAddress.languageIdentifier NSTermOfAddress.pronouns

   and `nm` on the object said why: `_OBJC_CLASSLIST_REFERENCES_$_` with an **empty** class name,
   which is what the compiler emits for an @implementation it will not place. It read the class
   through the lift's overlay, whose copy of NSTermOfAddress.h still carries
   `API_AVAILABLE(ios(17.0))` -- the lift cannot lower a header the build's own SDK has not got, so
   nothing told the compiler the class is there at 6.1.3 -- and an unavailable class at the
   deployment target is not emitted at all.

   So the declaration is here, and it carries **no availability mark**: on this release the class is
   available from the band's minimum, which is what the band's registry entry says (`minimum: 6.0`,
   `maximum: 16.0`, because 18.0 has the class and a band from there on answers with the release's
   own). Nothing here changes a member's spelling or type -- these are the same declarations, in the
   same order, from the same file:

     NSTermOfAddress.h    NSTermOfAddress, iOS 17.0

   and the class is checked against the 16.4 SDK for absence first (grep finds no
   NSTermOfAddress.h and no @interface NSTermOfAddress in it), so the day the build SDK moves past
   17.0 this header goes away instead of shadowing the real one. AVAudioSessionCapability26.m and
   CharonAVFAudioNew.h are the same shape for the same reason. */

/* Whether the build's own SDK declares the class is a question about the SDK's version, not about
   whether a file of that name is reachable. NSTermOfAddress is iOS 17.0, so a build SDK whose newest
   release is older than that has no declaration of its own and needs this one; a newer one has the
   real declaration and this header must be silent rather than shadow it. The two are compared as the
   SDK spells them, and an SDK only spells the versions it knows: the port's 16.4 SDK defines
   __IPHONE_16_4 and no __IPHONE_17_0, and the host's 27.0 SDK defines __IPHONE_17_0. So "older than
   17.0" is "does not define it", and that is the test -- comparing __IPHONE_OS_VERSION_MAX_ALLOWED
   against 170000 is false on both, and against __IPHONE_17_0 is false on the 16.4 SDK too, because
   the macro it compares to is not defined there and the whole condition drops out.
   AVAudioSessionCapability26.m and CharonAVFAudioNew.h are the same shape for the same reason. */

#if !defined(__IPHONE_17_0)

NS_ASSUME_NONNULL_BEGIN

@interface NSTermOfAddress : NSObject <NSCopying, NSSecureCoding>

/* Term of address that uses gender-neutral pronouns (e.g. they/them/theirs in
   English), and an epicene grammatical gender when inflecting verbs and
   adjectives referring to the person
 */
+ (instancetype)neutral;
/* Term of address that uses feminine pronouns (e.g. she/her/hers in English),
   and a feminine grammatical gender when inflecting verbs and adjectives
   referring to the person
 */
+ (instancetype)feminine;
/* Term of address that uses masculine pronouns (e.g. he/him/his in English),
   and a masculine grammatical gender when inflecting verbs and adjectives
   referring to the person
 */
+ (instancetype)masculine;

/* The term of address that should be used for addressing the user

   This term of address will only compare equal to another `+[NSTermOfAddress currentUser]`
 */
+ (instancetype)currentUser;

/* A term of address restricted to a given language
 @param language ISO language code identifier for the language
 @param pronouns A list of pronouns in the target language that can be used to
                 refer to the person.
 */
+ (instancetype)localizedForLanguageIdentifier:(NSString*)language
                                  withPronouns:(NSArray *)pronouns;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/// The ISO language code if this is a localized term of address
@property(nullable, readonly, copy) NSString* languageIdentifier;
/// A list of pronouns for a localized term of address
@property(nullable, readonly, copy) NSArray *pronouns;
@end

NS_ASSUME_NONNULL_END

#endif
