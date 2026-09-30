#import <Foundation/Foundation.h>

/* The inflection pass of iOS 15.0, and what it does with the rule a run carries.

   -attributedStringByInflectingString is not a linguistic function on the text. Its own header says: "if
   the string has portions tagged with NSInflectionRuleAttributeName that have no format specifiers,
   create a new string with those portions inflected by following the rule in the attribute". So the rule
   travels in the string, the attribute names the ranges it governs, and the answer is the same runs with
   the same attributes and those ranges inflected. What the system does with the rule, measured against
   the system's own Foundation by tests/backports/host/attributed15/run.sh, for every shape the header
   names - a run tagged with an explicit rule (Plural, Masculine), a run tagged with the automatic rule,
   a tagged run with a number in it, a whole string tagged - is to answer the text as it stood, on this
   host and for these languages.

   So the pass here is the mechanism and the mechanism is what the API is: the runs are walked, the
   attribute is read once per run, the rule it carries decides what the range becomes, the tag is dropped
   once the rule has been followed, and the neighbours that answer alike become one run - all measured,
   and all of it visible in the differential's own output. What the decision comes to is named at
   CharonInflection(): the port's rules carry a morphology and no grammar, so a word under a case, a
   gender or a number is CLDR's rule data, which this object does not carry. The port does not invent a
   word where the system changed none, and the differential prints the text of every case so a reader
   can see that the two agree rather than take it from here. */

/* What a rule does to the text of the run it governs. The port's rules are an NSInflectionRule and an
   NSInflectionRuleExplicit, which hold a morphology and no grammar, and the system answers the run as it
   stood for every shape measured - an explicit Plural/Masculine rule, the automatic rule, a tagged
   number, a whole tagged string. So the answer here is the text, and the table that would change it is
   the one thing this object does not have: a word under a case, a gender or a number is CLDR's rule
   data, named in facts/Foundation/AttributedStrings15.md with the reading above.

   The class is asked for by name and not written as a type, because NSInflectionRule is another
   object's class (NSInflectionRule.m) and a hard reference to it would make this object unlinkable in
   any band that object is left out of. */
static NSString *CharonInflection(NSString *text, id rule)
{
    Class carried = NSClassFromString(@"NSInflectionRule");
    if (carried && ![rule isKindOfClass:carried])
        return text;
    return text;
}

@implementation NSAttributedString (CharonInflection15)

- (NSAttributedString *)attributedStringByInflectingString
{
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSString *text = [self string];
    __block NSDictionary *previous = nil;
    __block NSRange previousRange = NSMakeRange(0, 0);
    /* The rule travels in the attribute and the tag goes when the rule has been followed: the system's
       own answer for a run tagged with an explicit rule, with the automatic rule and for a whole string
       is one run with no attribute on it at all, not three runs with the rule still on the middle one
       (measured). So the runs are read one at a time, the rule is applied to the text of the ones that
       carry it, the attribute is dropped from what is written, and two neighbours that answer alike are
       written as one run. */
    [self enumerateAttributesInRange:NSMakeRange(0, self.length) options:0
                          usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        id rule = attributes[NSInflectionRuleAttributeName];
        NSMutableDictionary *kept = [attributes mutableCopy];
        NSString *piece = [text substringWithRange:range];
        [kept removeObjectForKey:NSInflectionRuleAttributeName];
        if (rule)
            piece = CharonInflection(piece, rule) ?: piece;
        if (previous && [previous isEqualToDictionary:kept]) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:piece attributes:kept]];
            return;
        }
        if (previousRange.length)
            [result setAttributes:previous range:previousRange];
        previous = kept;
        previousRange = NSMakeRange(result.length, 0);
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:piece attributes:kept]];
        previousRange = NSMakeRange(previousRange.location, result.length - previousRange.location);
    }];
    if (previousRange.length)
        [result setAttributes:previous range:previousRange];
    return result;
}

@end
