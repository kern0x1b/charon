#import <UIKit/UIKit.h>

@interface CharonDragDropSession : NSObject <UIDropSession>
@end

@implementation CharonDragDropSession

- (BOOL)canLoadObjectsOfClass:(Class<NSItemProviderReading>)aClass
{
    return NO;
}

- (NSProgress *)loadObjectsOfClass:(Class<NSItemProviderReading>)aClass completion:(void (^)(NSArray<__kindof id<NSItemProviderReading>> *objects))completion
{
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    progress.completedUnitCount = 1;
    if (completion)
        completion(@[]);
    return progress;
}

@end
