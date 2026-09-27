#import <Foundation/Foundation.h>
#ifndef CHARON_BRAILLE_ONLY
#import <Accessibility/Accessibility.h>
#endif
#import <stdint.h>
#import <ctype.h>

#import "CharonBraille.h"
#import "../Intents/CharonIntentsCoding.h"

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
