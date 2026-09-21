#import <Foundation/Foundation.h>
#import "errorprovider-cases.h"

int main(void)
{
    @autoreleasepool {
        NSMutableDictionary *records = [NSMutableDictionary dictionary];
        errorprovider_run(^(NSString *name, NSString *value) {
            records[name] = value;
            printf("%s: %s\n", name.UTF8String, value.UTF8String);
        });
        [[NSJSONSerialization dataWithJSONObject:records options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL] writeToFile:@(getenv("ERRORPROVIDER_RECORDS")) atomically:YES];
    }
    return 0;
}
