#import <CoreMedia/CoreMedia.h>
#import <CoreMedia/CMTag.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
// Every measured pair, as a fixture the fitter reads: the two tags by value and the host's answer,
// one line per unordered pair, plus both argument orders for the pair the differential disagreed on.
static CMTag tag(CMTagCategory c, CMTagDataType d, uint64_t v){ CMTag m={c,d,v}; return m; }
int main(void){ setvbuf(stdout,NULL,_IONBF,0); @autoreleasepool {
    CMTag t[] = {
        tag(0, 0, 0),                                              // 0  invalid
        tag(0, 5, 0),                                              // 1  zero category, OSType
        tag(0, 2, -1),                                             // 2  zero category, int64 -1
        tag(1, 5, 0),                                              // 3
        tag(0x6d646961, 0, 0),                                      // 4  'mdia', no data type
        tag(0x6d646961, 5, 0x76696465),                            // 5  'vide'
        tag(0x7472616b, 2, 7),                                      // 6  'trak' int64 7
        tag(0x7472616b, 3, 0x3FF8000000000000ULL),                  // 7  'trak' float 1.5
        tag(0x70697866, 7, 3),                                       // 8  'pixf' flags 3
        tag(0x7a7a7a7a, 7, 3),                                      // 9  'zzzz' flags 3
        tag(0xffffffff, 5, 0),                                      // 10
        tag(0x6d646961, 2, 7),                                      // 11
        tag(0x6d646961, 5, 0),                                      // 12 'mdia' OSType 0
    };
    size_t count = sizeof t / sizeof *t;
    printf("# a b host\n");
    for (size_t a = 0; a < count; a++)
        for (size_t b = a + 1; b < count; b++)
            printf("%zu %zu %ld\n", a, b, (long)CMTagCompare(t[a], t[b]));
    printf("# the pair the differential disagreed on, both argument orders\n");
    printf("# 7 3 %ld\n", (long)CMTagCompare(t[7], t[3]));
    printf("# 3 7 %ld\n", (long)CMTagCompare(t[3], t[7]));
    printf("# hash samples\n");
    for (size_t a = 0; a < count; a++)
        printf("H %zu %lu\n", a, (unsigned long)CMTagHash(t[a]));
} return 0; }
