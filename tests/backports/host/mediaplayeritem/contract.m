// The contract for MediaPlayer's 7.0 group, compiled against the port's own source and a stand-in.
//
// The expected answers are generated from ONE list of (name, type, key) - the same list the mutating
// copies below are made from - so the check, the mutants and the getters cannot drift apart: a change to
// the list changes all three, and nothing here is typed by hand twice.
#import "MPMediaItemStandin.h"

// (name, type, key)
static char *const members[][3] = {
    {"albumTrackNumber", "NSUInteger", "albumTrackNumber"},
    {"discNumber",       "NSUInteger", "discNumber"},
};

@implementation MPMediaItem
{
    NSDictionary *properties;
}
- (void)charon_set_properties:(NSDictionary *)properties { self->properties = properties; }
- (id)valueForProperty:(NSString *)property { return self->properties[property]; }
@end

// The port's own source, verbatim, with its own stand-in seam taken.
#define CHARON_MEDIAPLAYER_STANDIN 1
#include "MPMediaItem70.m"

static int failures = 0;

static void check(const char *what, int held, const char *expected, const char *got) {
    if (held) {
        printf("  ok   %s: %s\n", what, expected);
    } else {
        printf("  RED  %s: expected %s, got %s\n", what, expected, got);
        failures++;
    }
}

// Two buffers, because a check prints its expected and its got in one call and one buffer would have
// both columns read the same number - a mutant would still be caught, but its line would not say what.
static const char *number(NSUInteger value, int which) {
    static char text[2][32];
    snprintf(text[which], sizeof text[which], "%lu", (unsigned long)value);
    return text[which];
}

int main(void) {
    MPMediaItem *item = [[MPMediaItem alloc] init];
    [item charon_set_properties:@{@"albumTrackNumber": @7, @"discNumber": @2}];
    printf("the port's own source, against a stand-in that answers valueForProperty:\n");
    const NSUInteger wanted[] = {7, 2};
    for (size_t i = 0; i < sizeof members / sizeof *members; ++i) {
        NSUInteger got = (i == 0) ? item.albumTrackNumber : item.discNumber;
        check(members[i][0], got == wanted[i], number(wanted[i], 0), number(got, 1));
    }
    // A key the dictionary does not hold: nil, so the conversion answers zero and nothing raises.
    MPMediaItem *empty = [[MPMediaItem alloc] init];
    [empty charon_set_properties:@{}];
    check("a missing key answers 0", [empty albumTrackNumber] == 0 && [empty discNumber] == 0, "0 and 0", "other");
    if (failures) {
        printf("contract: %d RED\n", failures);
        return 1;
    }
    printf("contract: OK (0 failures)\n");
    return 0;
}
