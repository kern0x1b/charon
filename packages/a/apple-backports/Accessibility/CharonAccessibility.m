//
//  CharonAccessibility.m
//  Accessibility
//
//  The Accessibility names the port's own SDK does not have, and what each of them answers where
//  this release cannot reach the service behind it. facts/Accessibility/Accessibility.md has the
//  whole of it; the three places that matter here are:
//
//  * **A request is the system's.** +[AXRequest currentRequest] is the request the system's
//    assistive technology is currently serving, and its technology is the one serving it. This
//    release runs no assistive-technology service that holds a current request, so there is none
//    and the class is the container an application keeps its own request in.
//  * **A feature override is a service.** beginOverrideSession… is how an application asks the
//    system to turn grayscale on, or Voice Control on, for a while. The system that does it is not
//    on this release, so the manager answers nil with the error the header's own enumeration has
//    for exactly this - AXFeatureOverrideSessionErrorAppNotEntitled is the wrong one, and
//    Undefined is the one that says nothing: there is no service to be entitled to. A session that
//    cannot exist is not invented so that endOverrideSession: has something to end.
//  * **A braille table is Apple's data.** AXBrailleTable is a table of dot patterns that a
//    provider supplies, and AXBrailleTranslator maps print text onto the table it is given. The
//    table is a value this port cannot invent and the system does not ship in a form a port may
//    read, so +defaultTableForLocale: and the two sets answer empty, and a translation is only
//    what the table says: an input with no table maps to no cells.
//

#import "CharonAccessibility.h"

#import "../Intents/CharonIntentsCoding.h"

#pragma mark - AXRequest

@implementation AXRequest {
    // An NSString, not an AXTechnology: Apple spells that typedef as NSString *const, so an ivar
    // of that type is a const pointer and could never be assigned. The property's own type is
    // the same object, so the accessor answers it unchanged.
    NSString *_servingTechnology;
}

// The header marks -init unavailable, so a request is built here: the technology that will serve
// it, and the request's own storage.
- (instancetype)charon_withTechnology:(AXTechnology)technology
{
    // Not an initialiser by its name, so it cannot chain to -init the way an initialiser does; it
    // builds through the allocation and sets what it was given, which is the same object the
    // header's -init NS_UNAVAILABLE means only that there is no argument-less one.
    AXRequest *request = [[AXRequest alloc] init];
    [request charon_setTechnology:technology];
    return request;
}

- (void)charon_setTechnology:(AXTechnology)technology
{
    _servingTechnology = [technology copy];
}

- (AXTechnology)technology
{
    return _servingTechnology;
}

+ (AXRequest *)currentRequest
{
    // Nothing on this release is serving a request, so there is no current one. The container
    // below is how an application keeps the request it is answering, which is what the property
    // is for on a release that has an assistive technology to ask.
    return nil;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        charon_intents_decode(self, coder);
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    charon_intents_encode(self, coder);
}

- (id)copyWithZone:(NSZone *)zone
{
    AXRequest *copy = [[AXRequest allocWithZone:zone] charon_withTechnology:_servingTechnology];
    return copy;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AXRequest technology %@>", _servingTechnology ?: @"(none)"];
}

@end

#pragma mark - AXFeatureOverrideSessionManager

@implementation AXFeatureOverrideSessionManager

+ (AXFeatureOverrideSessionManager *)sharedInstance
{
    static AXFeatureOverrideSessionManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[AXFeatureOverrideSessionManager alloc] init];
    });
    return shared;
}

- (AXFeatureOverrideSession *)beginOverrideSessionEnablingOptions:(AXFeatureOverrideSessionOptions)enableOptions
                                                   disablingOptions:(AXFeatureOverrideSessionOptions)disableOptions
                                                            error:(NSError **)error
{
    // The system that turns these on is not on this release. Undefined is the header's own name
    // for a session that could not be begun for no more specific reason, and there is no more
    // specific one here: there is no service, so there is nothing to be entitled to and nothing
    // already active and nothing registered under a UUID. The manager is real and answers.
    if (error) {
        *error = [NSError errorWithDomain:@"AXFeatureOverrideSessionErrorDomain"
                                     code:AXFeatureOverrideSessionErrorUndefined
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"this release runs no service that overrides an "
                                                @"accessibility feature, so no session can be begun"}];
    }
    return nil;
}

- (BOOL)endOverrideSession:(AXFeatureOverrideSession *)session error:(NSError **)error
{
    // No session was begun, so none is active. Ending one is therefore a NO, and it says why.
    if (error) {
        *error = [NSError errorWithDomain:@"AXFeatureOverrideSessionErrorDomain"
                                     code:AXFeatureOverrideSessionErrorUndefined
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"no session was begun, so none is active"}];
    }
    return NO;
}

@end

#pragma mark - AXFeatureOverrideSession

// The header gives the session nothing: it is a token the manager hands out and takes back. There
// is no manager that can hand one out on this release, so the class is a container of its own and
// the equality the header implies is by identity.
@implementation AXFeatureOverrideSession

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AXFeatureOverrideSession %p>", self];
}

@end

#pragma mark - AXBrailleTable

@implementation AXBrailleTable {
    NSString *_identifier;
    NSString *_localizedName;
    NSString *_providerIdentifier;
    NSString *_localizedProviderName;
    NSString *_language;
    NSSet<NSLocale *> *_locales;
    BOOL _isEightDot;
}

@synthesize identifier = _identifier;
@synthesize localizedName = _localizedName;
@synthesize providerIdentifier = _providerIdentifier;
@synthesize localizedProviderName = _localizedProviderName;
@synthesize language = _language;
@synthesize locales = _locales;
@synthesize isEightDot = _isEightDot;

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (!identifier) {
        return nil;
    }
    if ((self = [super init])) {
        _identifier = [identifier copy];
    }
    return self;
}

+ (NSSet<NSLocale *> *)supportedLocales
{
    // The set of locales a braille table exists for is Apple's data, one table per provider per
    // locale, and none of it is on this release. An empty set is the answer, and it is what makes
    // +defaultTableForLocale: and the two other sets answer nothing rather than something invented.
    return [NSSet set];
}

+ (AXBrailleTable *)defaultTableForLocale:(NSLocale *)locale
{
    return nil;
}

+ (NSSet<AXBrailleTable *> *)tablesForLocale:(NSLocale *)locale
{
    return [NSSet set];
}

+ (NSSet<AXBrailleTable *> *)languageAgnosticTables
{
    return [NSSet set];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    // The header marks -init unavailable, so an archive reads its identifier and builds through
    // the one initialiser there is; every other property comes out of the archive.
    NSString *identifier = [coder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
    if ((self = [[[self class] alloc] initWithIdentifier:identifier])) {
        charon_intents_decode(self, coder);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    charon_intents_encode(self, coder);
}

- (id)copyWithZone:(NSZone *)zone
{
    AXBrailleTable *copy = [[[self class] allocWithZone:zone] initWithIdentifier:_identifier];
    copy->_localizedName = _localizedName;
    copy->_providerIdentifier = _providerIdentifier;
    copy->_localizedProviderName = _localizedProviderName;
    copy->_language = _language;
    copy->_locales = _locales;
    copy->_isEightDot = _isEightDot;
    return copy;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AXBrailleTable %@ %@>", _identifier, _localizedName];
}

@end

#pragma mark - AXBrailleTranslator

@implementation AXBrailleTranslator {
    AXBrailleTable *_brailleTable;
}

- (instancetype)initWithBrailleTable:(AXBrailleTable *)brailleTable
{
    if ((self = [super init])) {
        _brailleTable = brailleTable;
    }
    return self;
}

- (AXBrailleTranslationResult *)translatePrintText:(NSString *)printText
{
    // A translation is what the table maps the text onto, and the table carries the provider's dot
    // patterns. This release has no table from a provider - +supportedLocales is empty - so there
    // is nothing to map onto and the result is the input with no cells, which is what a
    // translation of nothing is: the location map is empty because no cell was produced.
    return [[AXBrailleTranslationResult alloc] charon_withResultString:printText ?: @"" locations:[NSArray array]];
}

- (AXBrailleTranslationResult *)backTranslateBraille:(NSString *)braille
{
    // The other direction needs the same table and the same reading of it, so it answers the same
    // way: the braille it was given, with no cells, rather than print text this port would have had
    // to guess at from dot patterns.
    return [[AXBrailleTranslationResult alloc] charon_withResultString:braille ?: @"" locations:[NSArray array]];
}

@end

#pragma mark - AXBrailleTranslationResult

@implementation AXBrailleTranslationResult {
    NSString *_resultString;
    NSArray<NSNumber *> *_locationMap;
}

@synthesize resultString = _resultString;
@synthesize locationMap = _locationMap;

- (instancetype)charon_withResultString:(NSString *)resultString
                                locations:(NSArray<NSNumber *> *)locations
{
    AXBrailleTranslationResult *result = [[AXBrailleTranslationResult alloc] init];
    result->_resultString = [resultString copy];
    result->_locationMap = [locations copy];
    return result;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        charon_intents_decode(self, coder);
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    charon_intents_encode(self, coder);
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[AXBrailleTranslationResult alloc] charon_withResultString:_resultString
                                                               locations:_locationMap];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<AXBrailleTranslationResult %@ %lu cell(s)>",
            _resultString, (unsigned long)[_locationMap count]];
}

@end
