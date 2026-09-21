#import <Foundation/Foundation.h>

typedef void (^VisionRecorder)(NSString *name, NSString *value);

void vision_run(VisionRecorder record);
