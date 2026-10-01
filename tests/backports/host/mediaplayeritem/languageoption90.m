// MPNowPlayingInfoLanguageOption and MPNowPlayingInfoLanguageOptionGroup: the 9.0 pair the release
// carries no class for (facts/MediaPlayer/LanguageOptions.md).
//
// Compiled against MPMediaItemStandin.h rather than this Mac's own MediaPlayer, so the check measures
// the port's source and not a framework that has the classes for a different reason. The designated
// initializers store what they were given, the two "automatic" accessors answer from the stored TYPE -
// which is the distinction MPNowPlayingInfoLanguageOption.h:56-73 draws - and the group holds the set it
// was built with.
//
// Every assertion here has been shown to FAIL on a mutation of the object it covers: retaining instead
// of copying the characteristics array, answering the automatic accessors without reading the type, and
// dropping the caller's allowEmptySelection flag each turn one line RED. The languageTag copy is
// deliberately NOT asserted, and the reason is written below where a reader will meet it.
#import <Foundation/Foundation.h>
#import "MPMediaItemStandin.h"

#define CHARON_MEDIAPLAYER_STANDIN 1
#include "MPNowPlayingInfoLanguageOption90.m"

static int failures = 0;
static void check(const char *what, int held, const char *got) {
    if (held) { printf("  ok   %s: %s\n", what, got); }
    else { printf("  RED  %s: %s\n", what, got); failures++; }
}

int main(void) {
    NSMutableArray *chars = [@[ @"public.audio", @"public.subtitles" ] mutableCopy];
    MPNowPlayingInfoLanguageOption *legible =
        [[MPNowPlayingInfoLanguageOption alloc] initWithType:MPNowPlayingInfoLanguageOptionTypeLegible
                                                 languageTag:@"en"
                                             characteristics:chars
                                                 displayName:@"English"
                                                  identifier:@"opt-en"];
    check("the designated initializer's type reads back",
          legible.languageOptionType == MPNowPlayingInfoLanguageOptionTypeLegible, "Legible");
    check("characteristics read back", [legible.languageOptionCharacteristics isEqualToArray:chars], "2");
    check("displayName reads back", [legible.displayName isEqualToString:@"English"], "English");
    check("identifier reads back", [legible.identifier isEqualToString:@"opt-en"], "opt-en");

    MPNowPlayingInfoLanguageOption *audible =
        [[MPNowPlayingInfoLanguageOption alloc] initWithType:MPNowPlayingInfoLanguageOptionTypeAudible
                                                 languageTag:@"en"
                                             characteristics:nil
                                                 displayName:@"English"
                                                  identifier:@"aud-en"];
    check("a Legible-typed option is the automatic LEGIBLE one",
          [legible isAutomaticLegibleLanguageOption] &&
          ![legible isAutomaticAudibleLanguageOption], "legible only");
    check("an Audible-typed option is the automatic AUDIBLE one",
          [audible isAutomaticAudibleLanguageOption] &&
          ![audible isAutomaticLegibleLanguageOption], "audible only");

    // The array is copied, so a later mutation of the caller's array cannot change what the option
    // reads. This is the ONE copy check that can fail: -languageTag is also copied, but an NSString is
    // immutable, so [string copy] is a retain and a check on it would pass either way - measured, by
    // mutating the object to retain the tag and watching this file still print OK. The array is the
    // case where copy and retain are different observable behaviour, so that is what is asserted.
    [chars addObject:@"public.music"];
    check("characteristics were copied, not retained",
          legible.languageOptionCharacteristics.count == 2, "2");

    MPNowPlayingInfoLanguageOptionGroup *group =
        [[MPNowPlayingInfoLanguageOptionGroup alloc] initWithLanguageOptions:@[ legible, audible ]
                                                      defaultLanguageOption:legible
                                                        allowEmptySelection:YES];
    check("languageOptions reads back", group.languageOptions.count == 2, "2");
    check("defaultLanguageOption reads back", group.defaultLanguageOption == legible, "the legible one");
    check("allowEmptySelection reads back", group.allowEmptySelection, "YES");
    // The header calls the group mutually exclusive; the object holds what it was given rather than
    // dropping options the caller passed. Asserted so a change to that decision has to be made on
    // purpose and shows up here.
    check("the group keeps every option it was given rather than enforcing exclusivity",
          [group.languageOptions containsObject:audible], "both kept");

    if (failures) { printf("langcheck: %d RED\n", failures); return 1; }
    printf("langcheck: OK (0 failures)\n");
    return 0;
}
