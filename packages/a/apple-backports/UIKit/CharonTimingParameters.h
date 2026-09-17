#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

/* The curve a UICubicTimingParameters holds is one number: 0 to 3 are the four
   UIViewAnimationCurve values, 5 is Core Animation's own default curve and 6 says
   the two control points carry it. */
enum {
    CharonCubicCurveDefault = 5,
    CharonCubicCurveControlPoints = 6
};

@interface _UIViewCubicTimingFunction : NSObject <NSCopying, NSCoding>
- (instancetype)initWithControlPoint1:(CGPoint)point1 controlPoint2:(CGPoint)point2;
@property (nonatomic, readonly) CGPoint controlPoint1;
@property (nonatomic, readonly) CGPoint controlPoint2;
- (CAMediaTimingFunction *)_mediaTimingFunction;
@end

@interface UICubicTimingParameters (CharonTiming)
- (_UIViewCubicTimingFunction *)timingFunction;
- (_UIViewCubicTimingFunction *)effectiveTimingFunction;
@end

@interface UISpringTimingParameters (CharonTiming)
- (BOOL)implicitDuration;
- (CGFloat)mass;
- (CGFloat)stiffness;
- (CGFloat)damping;
- (CGFloat)dampingRatio;
@end
