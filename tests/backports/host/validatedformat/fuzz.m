#import <Foundation/Foundation.h>
#include <stdint.h>
#include <sys/wait.h>
#include <unistd.h>

/* The port is compiled into this file under other selectors, so that the host's own methods stay the
   host's and the port's static functions are at hand to type the arguments. */
#define stringWithValidatedFormat charonHostStringWithValidatedFormat
#define localizedStringWithValidatedFormat charonHostLocalizedStringWithValidatedFormat
#define initWithValidatedFormat initWithCharonHostValidatedFormat
#include CHARON_VALIDATED_FORMAT
#undef stringWithValidatedFormat
#undef localizedStringWithValidatedFormat
#undef initWithValidatedFormat

static char c_string[64] = "x";
static unichar wide_string[32] = {'x', 0};

static NSString *pick(NSArray *choices)
{
    return choices[arc4random_uniform((uint32_t)choices.count)];
}

static NSString *specifier(BOOL wild)
{
    NSMutableString *made = [NSMutableString stringWithString:@"%"];
    if (arc4random_uniform(4) == 0)
        [made appendFormat:@"%u$", arc4random_uniform(wild ? 13 : 5)];
    if (arc4random_uniform(4) == 0)
        [made appendString:pick(@[@"-", @"+", @" ", @"#", @"0"])];
    uint32_t width = arc4random_uniform(8), precision = arc4random_uniform(8);
    if (width == 0)
        [made appendString:@"10"];
    else if (width == 1 && wild)
        [made appendString:@"*"];
    else if (width == 2 && wild)
        [made appendFormat:@"*%u$", 1 + arc4random_uniform(3)];
    if (precision == 0)
        [made appendString:@".2"];
    else if (precision == 1 && wild)
        [made appendString:@".*"];
    if (arc4random_uniform(3) == 0)
        [made appendString:pick(@[@"h", @"hh", @"l", @"ll", @"q", @"L", @"j", @"z", @"t"])];
    uint32_t odd = wild ? arc4random_uniform(14) : 99;
    if (odd == 0)
        return pick(@[@"%#@key@", @"%#@", @"%[k]@", @"%0$@", @"%13$d", @"%k", @"%y", @"%Z"]);
    [made appendString:odd == 1 ? @"P" : pick(@[@"@", @"d", @"i", @"u", @"x", @"c", @"C", @"f", @"g", @"e", @"s", @"S", @"p", @"D", @"O", @"U", @"a"])];
    return made;
}

static NSString *format(BOOL wild)
{
    NSMutableString *made = [NSMutableString string];
    uint32_t count = arc4random_uniform(wild ? 6 : 4);
    for (uint32_t index = 0; index < count; index++) {
        uint32_t roll = arc4random_uniform(10);
        [made appendString:roll < 2 ? @" a " : roll == 2 ? @"%%" : specifier(wild)];
    }
    if (wild && arc4random_uniform(20) == 0)
        [made appendString:@"%"];
    return made;
}

/* One argument per slot, of the kind the allowed string gives that slot. Every argument is a word,
   which on arm64 is how a variadic argument of any of these kinds is passed. */
static void arguments_for(NSString *allowed, uint64_t *words)
{
    double floating = 2.5;
    uint64_t floatingWord;
    memcpy(&floatingWord, &floating, sizeof floatingWord);
    for (int slot = 0; slot < 13; slot++)
        words[slot] = (uint64_t)(__bridge void *)@"object";
    NSArray *slots = charon_format_slots(allowed, NO);
    for (NSUInteger slot = 0; slot < slots.count && slot < 13; slot++) {
        if (![slots[slot] count])
            continue;
        switch ([slots[slot][0][0] unsignedIntegerValue]) {
            case CharonFormatObject: break;
            case CharonFormatCString: case CharonFormatPascalString: case CharonFormatPointer: case CharonFormatCount:
                words[slot] = (uint64_t)(void *)c_string;
                break;
            case CharonFormatWideString: words[slot] = (uint64_t)(void *)wide_string; break;
            case CharonFormatFloating: case CharonFormatLongFloating: words[slot] = floatingWord; break;
            default: words[slot] = 7; break;
        }
    }
}

/* Whether the arguments are those the allowed string describes, in a way that also holds for the format:
   only then is the output comparable, since the host reads eight bytes for every argument and the port
   reads what the allowed string says. */
static BOOL arguments_agree(NSString *wanted, NSString *allowed)
{
    NSArray *asked = charon_format_slots(wanted, NO), *offered = charon_format_slots(allowed, NO);
    for (NSArray *kinds in offered)
        for (NSArray *kind in kinds)
            if (![kind isEqual:kinds[0]])
                return NO;
    for (NSUInteger slot = 0; slot < asked.count; slot++) {
        if (slot >= offered.count || ![offered[slot] count])
            return NO;
        CharonFormatKind given = [offered[slot][0][0] unsignedIntegerValue];
        BOOL word = given == CharonFormatObject || given == CharonFormatCString || given == CharonFormatWideString
                 || given == CharonFormatPascalString || given == CharonFormatPointer;
        for (NSArray *kind in asked[slot]) {
            CharonFormatKind taken = [kind[0] unsignedIntegerValue];
            BOOL pointer = taken == CharonFormatCString || taken == CharonFormatWideString || taken == CharonFormatPascalString
                        || taken == CharonFormatPointer;
            if (taken == CharonFormatPointer && given == CharonFormatObject)
                return NO;
            if (taken != given && !(taken == CharonFormatWideCharacter && given == CharonFormatInteger) && !(word && pointer))
                return NO;
            if (![kind[1] isEqual:offered[slot][0][1]] && !pointer && !word)
                return NO;
        }
    }
    return YES;
}

static NSString *answer(BOOL ours, NSString *wanted, NSString *allowed, uint64_t *w)
{
    NSError *error = nil;
    NSString *made = ours
        ? [NSString charonHostStringWithValidatedFormat:wanted validFormatSpecifiers:allowed error:&error,
           w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8], w[9], w[10], w[11], w[12]]
        : [NSString stringWithValidatedFormat:wanted validFormatSpecifiers:allowed error:&error,
           w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8], w[9], w[10], w[11], w[12]];
    return made ? [@"ok " stringByAppendingString:made] : [NSString stringWithFormat:@"%ld %@", (long)error.code, error.userInfo[NSDebugDescriptionErrorKey]];
}

int main(int argc, char **argv)
{
    int rounds = argc > 1 ? atoi(argv[1]) : 20000, differ = 0, lost = 0, compared = 0;
    for (int round = 0; round < rounds; round++) @autoreleasepool {
        NSString *allowed = format(NO), *wanted = arc4random_uniform(3) == 0 ? allowed : format(round % 3 == 0);
        uint64_t words[13];
        arguments_for(allowed, words);
        BOOL whole = arguments_agree(wanted, allowed);
        int pipes[2];
        pipe(pipes);
        pid_t child = fork();
        if (child == 0) {
            close(pipes[0]);
            NSString *system = answer(NO, wanted, allowed, words), *port = answer(YES, wanted, allowed, words);
            BOOL same = whole ? [system isEqual:port] : [system hasPrefix:@"ok "] == [port hasPrefix:@"ok "];
            NSString *line = same ? @"same" : [NSString stringWithFormat:@"FAIL [%@] against [%@]\n  system: %@\n  port:   %@", wanted, allowed, system, port];
            write(pipes[1], line.UTF8String, strlen(line.UTF8String));
            _exit(0);
        }
        close(pipes[1]);
        char buffer[4096];
        ssize_t got = read(pipes[0], buffer, sizeof buffer - 1);
        close(pipes[0]);
        int status = 0;
        waitpid(child, &status, 0);
        if (got <= 0) {
            lost++;
            continue;
        }
        buffer[got] = 0;
        if (strncmp(buffer, "same", 4)) {
            if (differ++ < 40)
                printf("%s\n", buffer);
        } else if (whole) {
            compared++;
        }
    }
    printf("%d pairs, %d with the whole output compared, %d differ, %d lost to a crash of the formatting\n", rounds, compared, differ, lost);
    return differ != 0;
}
