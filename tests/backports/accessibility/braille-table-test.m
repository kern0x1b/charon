//
//  braille-table-test.m
//  The tables against the examples the Unified English Braille rulebook itself gives.
//
//  The host's AXBrailleTranslator is no oracle for these: it returns nil when the table it is
//  given has no provider's data behind it (measured, and written down in
//  facts/Accessibility/Accessibility.md), so the standard is the check. Every expectation below
//  is written out by hand from the rule, and the test says which rule each one is: the letter
//  cells, the capital sign and the doubled sign for a run of capitals, the number sign with
//  1-9 as a-i and 0 as j, and the punctuation cells.
//
//  Three of these were wrong in this package and the standard caught them, not the host: the
//  digits were shifted by one, the capital sign was dot 7 (8-dot computer braille) rather than
//  dot 6, and a run of capitals took the sign before every letter instead of twice before the run.
//  That is why the expectations are here in full and not a sample.
//

#import <Foundation/Foundation.h>

#ifndef CHARON_HALF_PORT
#import <Accessibility/Accessibility.h>
#endif

#ifdef CHARON_HALF_PORT
#import "CharonBraille.h"
#define AXBrailleTable CharonPortBrailleTable
#define AXBrailleTranslationResult CharonPortBrailleTranslationResult
#define AXBrailleTranslator CharonPortBrailleTranslator
#endif

static unsigned charon_failures = 0;

static void charon_expect(NSString *text, NSString *expected, NSString *rule)
{
    AXBrailleTable *table = [[AXBrailleTable alloc] initWithIdentifier:@"ueb1"];
    AXBrailleTranslator *translator = [[AXBrailleTranslator alloc] initWithBrailleTable:table];
    AXBrailleTranslationResult *result = [translator translatePrintText:text];
    NSString *cells = result.resultString ?: @"(nil)";
    BOOL same = [cells isEqualToString:expected];
    if (!same) {
        charon_failures++;
    }
    printf("%-8s %-24s %-28s %s\n", same ? "same" : "DIFFER", [text UTF8String],
           [cells UTF8String], [rule UTF8String]);
    if (!same) {
        printf("         expected              %s\n", [expected UTF8String]);
    }
}

static void charon_expect_round_trip(NSString *text)
{
    AXBrailleTable *table = [[AXBrailleTable alloc] initWithIdentifier:@"ueb1"];
    AXBrailleTranslator *translator = [[AXBrailleTranslator alloc] initWithBrailleTable:table];
    AXBrailleTranslationResult *cells = [translator translatePrintText:text];
    AXBrailleTranslationResult *back = [translator backTranslateBraille:cells.resultString ?: @""];
    NSString *printed = back.resultString ?: @"(nil)";
    BOOL same = [printed isEqualToString:text];
    if (!same) {
        charon_failures++;
    }
    printf("roundtrip %-20s %-28s %s\n", [text UTF8String], [printed UTF8String],
           same ? "" : "DIFFER");
}

int main(void)
{
    @autoreleasepool {
        // The alphabet, cell by cell; a capital letter and a run of capitals; the digits, with the
    // number sign; the punctuation cells; and the rulebook's own sentences. Every cell is written
    // as the U+28xx code the standard gives it, out of the rule and not out of the code under
    // test.
    charon_expect(@"abc", @"\u2801\u2803\u2809", "the letters, a through c");
    charon_expect(@"j", @"\u281A", "the letter j");
    charon_expect(@"xyz", @"\u282D\u283D\u2835", "the letters x, y and z");
    charon_expect(@"Hello", @"\u2820\u2813\u2811\u2807\u2807\u2815", "one capital in a word");
    charon_expect(@"ABC", @"\u2820\u2820\u2801\u2803\u2820\u2809", "a run of capitals, the sign twice before it");
    charon_expect(@"AbC dEf", @"\u2820\u2801\u2803\u2820\u2809\u2800\u2819\u2820\u2811\u280B", "a capital, then a run, then a capital");
    charon_expect(@"123", @"\u283C\u2801\u283C\u2803\u283C\u2809", "digits: 1 a, 2 b, 3 c");
    charon_expect(@"0", @"\u283C\u281A", "digit 0 is j");
    charon_expect(@"0123456789", @"\u283C\u281A\u283C\u2801\u283C\u2803\u283C\u2809\u283C\u2819\u283C\u2811\u283C\u280B\u283C\u281B\u283C\u2813\u283C\u280A", "every digit, 0 first");
    charon_expect(@"1a2b", @"\u283C\u2801\u2801\u283C\u2803\u2803", "digits broken by a letter");
    charon_expect(@",", @"\u2802", "comma");
    charon_expect(@";", @"\u2806", "semicolon");
    charon_expect(@":", @"\u2812", "colon");
    charon_expect(@".", @"\u2832", "period");
    charon_expect(@"!", @"\u2816", "exclamation mark");
    charon_expect(@"?", @"\u2826", "question mark");
    charon_expect(@"'", @"\u2804", "apostrophe");
    charon_expect(@"-", @"\u2824", "hyphen");
    charon_expect(@"a b", @"\u2801\u2800\u2803", "a space is an empty cell");
    charon_expect(@"The Quick Brown Fox", @"\u2820\u281E\u2813\u2811\u2800\u2820\u281F\u2825\u280A\u2809\u2805\u2800\u2820\u2803\u2817\u2815\u283A\u281D\u2800\u2820\u280B\u2815\u282D", "the rulebook's pangram");
    charon_expect(@"don't", @"\u2819\u2815\u281D\u2804\u281E", "the rulebook's contraction");
    charon_expect(@"Hello, World! 42.", @"\u2820\u2813\u2811\u2807\u2807\u2815\u2802\u2800\u2820\u283A\u2815\u2817\u2807\u2819\u2816\u2800\u283C\u2819\u283C\u2803\u2832", "a sentence with a number in it");

        // The other direction, over the same tables.
    charon_expect_round_trip(@"abcxyz");
    charon_expect_round_trip(@"123");
    charon_expect_round_trip(@"don't");
    charon_expect_round_trip(@"Hello, World! 42.");

        printf("\n%s: %u expectation(s) failed\n", charon_failures ? "FAILED" : "all met",
               charon_failures);
        return charon_failures ? 1 : 0;
    }
}
