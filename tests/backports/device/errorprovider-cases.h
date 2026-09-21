#import <Foundation/Foundation.h>

typedef void (^ErrorProviderRecorder)(NSString *name, NSString *value);

void errorprovider_run(ErrorProviderRecorder record);
