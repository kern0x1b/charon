#import <Foundation/Foundation.h>

/* The 26.2 Foundation's NSMorphology.h and NSInflectionRule.h, the part of it the SDK the port builds
   against does not carry, declared here so the port can implement it.
 *
 * The 16.5 SDK declares NSMorphology and NSInflectionRule, so those two are **not** declared here -
   a redeclaration is a duplicate definition and the gate fails on it. What it does not carry is the
   iOS 17.0 set of members and the custom-pronoun and inflection-rule classes, and those are below:
 * the five grammatical properties as a **category**, because a category cannot add an ivar and their
 * storage is a side table (CharonMorphology.m), and the three classes whole, because they are
 * classes and a category cannot make one.
 *
 * Transcribed from $HOME/Git/projects/ios/charon/.agent-work/sdk-26.2/iPhoneOS26.2.sdk/System/Library/
 * Frameworks/Foundation.framework/Headers/{NSMorphology.h,NSInflectionRule.h}, read whole - 163 and
 * 44 lines. The enums NSGrammaticalGender, NSGrammaticalPartOfSpeech, NSGrammaticalNumber,
 * NSGrammaticalCase, NSGrammaticalPronounType, NSGrammaticalPerson, NSGrammaticalDetermination and
 * NSGrammaticalDefiniteness are in the 16.5 SDK and are not repeated here. */

/* The five iOS 17.0 enums are **not** in the 16.5 SDK the port builds against - it has the three
   15.0 ones and not these - so they are transcribed here, in the 26.2 header's order, which is the
   portability of the API: NSGrammaticalCase runs NotSet, Nominative, Accusative, Dative, Genitive,
   Prepositional ... and NSGrammaticalDefiniteness runs NotSet, Indefinite, Definite. */
#ifdef CHARON_MORPHOLOGY_IOS17_ENUMS
/* The package defines CHARON_MORPHOLOGY_IOS17_ENUMS, because the iOS SDK it builds against has the
   three 15.0 enums and not these five (grep -c on iPhoneOS16.5.sdk's NSMorphology.h: 1 for each of
   Gender, PartOfSpeech and Number, 0 for each of these). The macOS SDK the host differential builds
   against has all eight, so a differential that did not define this would see a redeclaration - which
   is why the define is the package's and not the header's guess. */
typedef NS_ENUM(NSInteger, NSGrammaticalCase) {
    NSGrammaticalCaseNotSet = 0,
    NSGrammaticalCaseNominative,
    NSGrammaticalCaseAccusative,
    NSGrammaticalCaseDative,
    NSGrammaticalCaseGenitive,
    NSGrammaticalCasePrepositional,
    NSGrammaticalCaseAblative,
    NSGrammaticalCaseAdessive,
    NSGrammaticalCaseAllative,
    NSGrammaticalCaseElative,
    NSGrammaticalCaseIllative,
    NSGrammaticalCaseEssive,
    NSGrammaticalCaseInessive,
    NSGrammaticalCaseLocative,
    NSGrammaticalCaseTranslative
};

typedef NS_ENUM(NSInteger, NSGrammaticalPronounType) {
    NSGrammaticalPronounTypeNotSet = 0,
    NSGrammaticalPronounTypePersonal,
    NSGrammaticalPronounTypeReflexive,
    NSGrammaticalPronounTypePossessive
};

typedef NS_ENUM(NSInteger, NSGrammaticalPerson) {
    NSGrammaticalPersonNotSet = 0,
    NSGrammaticalPersonFirst,
    NSGrammaticalPersonSecond,
    NSGrammaticalPersonThird
};

typedef NS_ENUM(NSInteger, NSGrammaticalDetermination) {
    NSGrammaticalDeterminationNotSet = 0,
    NSGrammaticalDeterminationIndependent,
    NSGrammaticalDeterminationDependent
};

typedef NS_ENUM(NSInteger, NSGrammaticalDefiniteness) {
    NSGrammaticalDefinitenessNotSet = 0,
    NSGrammaticalDefinitenessIndefinite,
    NSGrammaticalDefinitenessDefinite
};
#endif /* CHARON_MORPHOLOGY_IOS17_ENUMS */

@class NSMorphologyCustomPronoun;

/* The languages the custom pronoun pair supports and the keys each requires, both measured, and both
   asked from NSMorphologyCustomPronoun.m and NSMorphology.m, so they are declared here. */
FOUNDATION_EXPORT BOOL CharonCustomPronounSupportedLanguage(NSString *language);
FOUNDATION_EXPORT NSArray<NSString *> *CharonCustomPronounRequiredKeys(void);

/* The seven attribute-name constants, all FOUNDATION_EXPORT NSAttributedStringKey in the 26.2 SDK's
   NSAttributedString.h and all measured out of the host's own image (NSMorphology, NSInflect,
   NSInflectionAlternative, NSContextInflectionConcepts, NSInflectionAgreementConcept,
   NSInflectionAgreementArgument, NSInflectionReferentConcept). They are defined in
   NSMorphologyCustomPronoun.m, which is where the family keeps its value tables, except
   NSMorphologyAttributeName which is NSMorphology's own. */
FOUNDATION_EXPORT NSAttributedStringKey const NSInflectionRuleAttributeName;
FOUNDATION_EXPORT NSAttributedStringKey const NSInflectionAlternativeAttributeName;
FOUNDATION_EXPORT NSString *const NSInflectionConceptsKey;
FOUNDATION_EXPORT NSAttributedStringKey const NSInflectionAgreementConceptAttributeName;
FOUNDATION_EXPORT NSAttributedStringKey const NSInflectionAgreementArgumentAttributeName;
FOUNDATION_EXPORT NSAttributedStringKey const NSInflectionReferentConceptAttributeName;

/* Five enumerations the 16.4 SDK -- the one this port compiles against -- does not declare, and
   that the 26.2 header does. Transcribed from
   iPhoneOS26.2.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSMorphology.h, lines
   47-89, the values verbatim and in the header's own order. The 16.4 header declares only
   NSGrammaticalGender, NSGrammaticalPartOfSpeech and NSGrammaticalNumber; the other five arrived
   with ios(17.0) per the header's own API_AVAILABLE, so the port has to spell them itself for the
   releases below that. Each is behind its own guard, the pattern nw_connection.m uses for
   nw_connection_state_setup: a build SDK that does declare one must not see a second typedef for
   it. Nothing here is inferred - every enumerator is the header's, and the facts page names the
   file and lines. */

#ifndef CHARON_NSGRAMMATICALCASE_DECLARED
typedef NS_ENUM(NSInteger, NSGrammaticalCase) {
    NSGrammaticalCaseNotSet = 0,
    NSGrammaticalCaseNominative,
    NSGrammaticalCaseAccusative,
    NSGrammaticalCaseDative,
    NSGrammaticalCaseGenitive,
    NSGrammaticalCasePrepositional,
    NSGrammaticalCaseAblative,
    NSGrammaticalCaseAdessive,
    NSGrammaticalCaseAllative,
    NSGrammaticalCaseElative,
    NSGrammaticalCaseIllative,
    NSGrammaticalCaseEssive,
    NSGrammaticalCaseInessive,
    NSGrammaticalCaseLocative,
    NSGrammaticalCaseTranslative
};
#define CHARON_NSGRAMMATICALCASE_DECLARED 1
#endif

#ifndef CHARON_NSGRAMMATICALPRONOUNTYPE_DECLARED
typedef NS_ENUM(NSInteger, NSGrammaticalPronounType) {
    NSGrammaticalPronounTypeNotSet = 0,
    NSGrammaticalPronounTypePersonal,
    NSGrammaticalPronounTypeReflexive,
    NSGrammaticalPronounTypePossessive
};
#define CHARON_NSGRAMMATICALPRONOUNTYPE_DECLARED 1
#endif

#ifndef CHARON_NSGRAMMATICALPERSON_DECLARED
typedef NS_ENUM(NSInteger, NSGrammaticalPerson) {
    NSGrammaticalPersonNotSet = 0,
    NSGrammaticalPersonFirst,
    NSGrammaticalPersonSecond,
    NSGrammaticalPersonThird
};
#define CHARON_NSGRAMMATICALPERSON_DECLARED 1
#endif

#ifndef CHARON_NSGRAMMATICALDETERMINATION_DECLARED
typedef NS_ENUM(NSInteger, NSGrammaticalDetermination) {
    NSGrammaticalDeterminationNotSet = 0,
    NSGrammaticalDeterminationIndependent,
    NSGrammaticalDeterminationDependent
};
#define CHARON_NSGRAMMATICALDETERMINATION_DECLARED 1
#endif

#ifndef CHARON_NSGRAMMATICALDEFINITENESS_DECLARED
typedef NS_ENUM(NSInteger, NSGrammaticalDefiniteness) {
    NSGrammaticalDefinitenessNotSet = 0,
    NSGrammaticalDefinitenessIndefinite,
    NSGrammaticalDefinitenessDefinite
};
#define CHARON_NSGRAMMATICALDEFINITENESS_DECLARED 1
#endif

/* One class the 16.4 SDK does not declare at all, and that the 26.2 header does: NSMorphologyPronoun.
   Transcribed from iPhoneOS26.2.sdk/.../Foundation.framework/Headers/NSMorphology.h:108-113 - the
   superclass, the two protocols, the two initialisers the header marks unavailable, and the three
   that build one. Without an interface the compiler treats the port's own @implementation as a root
   class, and '[super init]' and the inherited +class are then errors; with it, they compile. The
   properties the carry reads are declared in the same block. Guarded by its own name, as the five
   enumerations are. */

#ifndef CHARON_NSMORPHOLOGYPRONOUN_DECLARED
@interface NSMorphologyPronoun : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPronoun:(NSString *)pronoun
                       morphology:(NSMorphology *)morphology
              dependentMorphology:(nullable NSMorphology *)dependentMorphology;
@property (readonly, copy) NSString *pronoun;
@property (readonly, strong) NSMorphology *morphology;
@property (readonly, strong, nullable) NSMorphology *dependentMorphology;
@end
#define CHARON_NSMORPHOLOGYPRONOUN_DECLARED 1
#endif

@interface NSMorphology (CharonGrammatical17)

@property (nonatomic) NSGrammaticalCase grammaticalCase;
@property (nonatomic) NSGrammaticalDetermination determination;
@property (nonatomic) NSGrammaticalPerson grammaticalPerson;
@property (nonatomic) NSGrammaticalPronounType pronounType;
@property (nonatomic) NSGrammaticalDefiniteness definiteness;

@end

@interface NSMorphologyCustomPronoun (CharonPrivate)
- (NSString *)charon_firstMissingKey;
@end

/* NSMorphologyPronoun arrived in iOS 17.0 and the 16.5 SDK has no such class, so it is declared
   here in full - which is why the port's own file is free of a redeclaration that the gate would
   refuse. Its superclass is NSObject and not NSFormatter: the 26.2 header says NSObject. */
#ifdef CHARON_MORPHOLOGY_IOS17_PRONOUN
@interface NSMorphologyPronoun : NSObject <NSCopying, NSSecureCoding>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPronoun:(NSString *)pronoun
                      morphology:(NSMorphology *)morphology
              dependentMorphology:(nullable NSMorphology *)dependentMorphology;

@property (readonly, copy) NSString *pronoun;
@property (readonly, copy) NSMorphology *morphology;
@property (readonly, copy, nullable) NSMorphology *dependentMorphology;

@end
#endif /* CHARON_MORPHOLOGY_IOS17_PRONOUN */

