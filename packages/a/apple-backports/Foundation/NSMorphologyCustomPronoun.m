#import <Foundation/Foundation.h>

#import "CharonMorphology.h"

/* The six attribute-name constants the corpus counts beside the classes, measured out of the host's own
   image and not from the header's names. */
NSAttributedStringKey const NSInflectionRuleAttributeName = @"NSInflect";
NSAttributedStringKey const NSInflectionAlternativeAttributeName = @"NSInflectionAlternative";
NSString *const NSInflectionConceptsKey = @"NSContextInflectionConcepts";
NSAttributedStringKey const NSInflectionAgreementConceptAttributeName = @"NSInflectionAgreementConcept";
NSAttributedStringKey const NSInflectionAgreementArgumentAttributeName = @"NSInflectionAgreementArgument";
NSAttributedStringKey const NSInflectionReferentConceptAttributeName = @"NSInflectionReferentConcept";

/* The three languages the custom pronoun pair supports, measured, and the five keys each of them
   requires in the order the refusal names them. Both are asked from two files - this one and
   NSMorphology.m - so they are here and declared in CharonMorphology.h. */
static NSArray *CharonCustomPronounLanguages(void)
{
    static NSArray *languages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ languages = @[@"en", @"en_US", @"en_GB"]; });
    return languages;
}

NSArray<NSString *> *CharonCustomPronounRequiredKeys(void)
{
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[@"subjectForm", @"objectForm", @"possessiveForm", @"possessiveAdjectiveForm", @"reflexiveForm"];
    });
    return keys;
}

BOOL CharonCustomPronounSupportedLanguage(NSString *language)
{
    return language != nil && [CharonCustomPronounLanguages() containsObject:language];
}

@implementation NSMorphologyCustomPronoun
{
    NSString *_subjectForm, *_objectForm, *_possessiveForm, *_possessiveAdjectiveForm, *_reflexiveForm;
}

+ (BOOL)isSupportedForLanguage:(NSString *)language
{
    return CharonCustomPronounSupportedLanguage(language);
}

+ (NSArray<NSString *> *)requiredKeysForLanguage:(NSString *)language
{
    return CharonCustomPronounSupportedLanguage(language) ? CharonCustomPronounRequiredKeys() : @[];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSMorphologyCustomPronoun *copy = [[[self class] allocWithZone:zone] init];
    copy->_subjectForm = [_subjectForm copy];
    copy->_objectForm = [_objectForm copy];
    copy->_possessiveForm = [_possessiveForm copy];
    copy->_possessiveAdjectiveForm = [_possessiveAdjectiveForm copy];
    copy->_reflexiveForm = [_reflexiveForm copy];
    return copy;
}

/* Every form is read back as written and a form that was never written is nil (measured). */
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_subjectForm forKey:@"subjectForm"];
    [coder encodeObject:_objectForm forKey:@"objectForm"];
    [coder encodeObject:_possessiveForm forKey:@"possessiveForm"];
    [coder encodeObject:_possessiveAdjectiveForm forKey:@"possessiveAdjectiveForm"];
    [coder encodeObject:_reflexiveForm forKey:@"reflexiveForm"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self)
        return nil;
    _subjectForm = [[coder decodeObjectOfClass:[NSString class] forKey:@"subjectForm"] copy];
    _objectForm = [[coder decodeObjectOfClass:[NSString class] forKey:@"objectForm"] copy];
    _possessiveForm = [[coder decodeObjectOfClass:[NSString class] forKey:@"possessiveForm"] copy];
    _possessiveAdjectiveForm = [[coder decodeObjectOfClass:[NSString class] forKey:@"possessiveAdjectiveForm"] copy];
    _reflexiveForm = [[coder decodeObjectOfClass:[NSString class] forKey:@"reflexiveForm"] copy];
    return self;
}

/* The first of the required keys that is not set, which is the one the refusal names: an empty
   pronoun answers "subjectForm" and one with only a subject form answers "objectForm" (measured). */
- (NSString *)charon_firstMissingKey
{
    NSArray *values = @[_subjectForm ?: @"", _objectForm ?: @"", _possessiveForm ?: @"",
                        _possessiveAdjectiveForm ?: @"", _reflexiveForm ?: @""];
    NSArray *keys = CharonCustomPronounRequiredKeys();
    for (NSUInteger index = 0; index < keys.count; index++)
        if (![values[index] length])
            return keys[index];
    return nil;
}

@end
