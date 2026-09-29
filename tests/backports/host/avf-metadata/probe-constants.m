//
//  probe-constants.m
//  The 47 metadata key-space, coordinated-playback and player-rate constants, read out of whichever
//  build this binary is.
//
//  One program, linked twice by run.sh. Linked plain, every name below is Apple's own exported
//  symbol and the values are the host's. Linked with the rename list and the port's four sources,
//  the same names are the port's own definitions and the same table is read out of them. The two
//  tables are diffed, so a difference is a difference in the port's file and not in the question.
//
//  The names are reached through &symbol, not dlsym: the rename rewrites the reference, so this file
//  needs no knowledge of which build it is in, and a name the port does not define is a link error
//  rather than a row that quietly reads as absent.
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

struct row {
    const char *name;
    NSString *const *value;
};

static const struct row table[] = {
#include "table.inc"
};

int main(void)
{
    @autoreleasepool {
        for (unsigned i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
            NSString *value = *table[i].value;
            printf("%-72s = %s\n", table[i].name, value ? [value UTF8String] : "(null)");
        }
        printf("rows: %u\n", (unsigned)(sizeof(table) / sizeof(table[0])));
    }
    return 0;
}
