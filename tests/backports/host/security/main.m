#import <Foundation/Foundation.h>
#import <stdio.h>
#import "security-cases.h"

// Each constant's value, read out of WHICHER build is linked in: the host's own Security.framework, or
// the port's object. compare.py requires them to agree, one check per constant, and the port's values
// were written from the host's answers rather than typed.
//
// The recorder is a plain C function, not a block cast to one: this repository's own guide is explicit
// that a block pointer and a function pointer are not the same thing, and it is right.
static void record(const char *name, const char *value)
{
    printf("%s\t%s\n", name, value);
}

int main(void)
{
    @autoreleasepool {
        security_run(record);
    }
    return 0;
}
