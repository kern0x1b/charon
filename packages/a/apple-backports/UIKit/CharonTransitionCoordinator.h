#import <UIKit/UIKit.h>

@interface CharonTransitionCoordinator : NSObject <UIViewControllerTransitionCoordinator>
- (instancetype)initWithFrom:(UIViewController *)from to:(UIViewController *)to container:(UIView *)container animated:(BOOL)animated duration:(NSTimeInterval)duration style:(UIModalPresentationStyle)style;
- (void)begin;
- (void)finish;
@end

NSTimeInterval charon_default_duration(BOOL modal);
