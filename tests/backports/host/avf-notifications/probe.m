//
//  probe.m
//  The notification names, user-info keys and option keys, read out of whichever build this is.
//
//  One program, linked twice by run.sh. Linked plain, every name is Apple's own exported symbol and
//  the table is the host's. Linked with the rename list and the port's four objects, the same names
//  are the port's definitions in the same binary, and the table is read out of them - so the harness
//  COMPILES the port's sources, LINKS them beside Apple's, and READS the port's object. That is the
//  point: a value that the port's object does not define cannot be read at all, which is a link
//  error and not a row that quietly reads as equal on both sides.
//
//  Two lines per name: the value as text, and the value as bytes. The bytes are not tidiness - a
//  value that is not valid UTF-8 answers NULL from -UTF8String and would print "(null)" on both sides
//  and pass, so the byte line is what makes "every one of these is printable ASCII and decodes byte
//  for byte to its printed text" a check rather than a claim.
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

struct row { const char *name; NSString *const *value; };
static const struct row table[] = {
#include "table.inc"
};

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        for (unsigned i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
            NSString *value = *table[i].value;
            const char *utf8 = value ? [value UTF8String] : NULL;
            printf("%-78s = %s\n", table[i].name, utf8 ? utf8 : "(null)");
            printf("%-78s   bytes:", table[i].name);
            if (!utf8) {
                printf(" (no UTF-8: the value is not valid UTF-8)");
            } else {
                for (const unsigned char *p = (const unsigned char *)utf8; *p; p++) {
                    printf(" %02x", *p);
                }
            }
            printf("\n");
            fflush(stdout);
        }
        printf("rows: %u\n", (unsigned)(sizeof(table) / sizeof(table[0])));
    }
    return 0;
}
