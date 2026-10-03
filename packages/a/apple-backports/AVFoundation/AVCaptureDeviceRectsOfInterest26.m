// AVCaptureDeviceRectsOfInterest26.m - the eight members of iOS 26's rectangles of interest, as real geometry
// over the release's own point of interest.
//
// WHY IT IS GEOMETRY AND NOT FOUR ANSWERS, which is the whole design. A rectangle of interest is a way of
// saying where the focus or the exposure should weigh, and 26.0's header says exactly what happens to it:
// "Setting focusRectOfInterest updates the device's focusPointOfInterest to the center of your provided
// rectangle of interest" (AVCaptureDevice.h:1171, and :1415 for the exposure). The release this port runs on
// has that point of interest and nothing else: 6.1.3's AVCaptureDevice owns -isFocusPointOfInterestSupported,
// -focusPointOfInterest, -setFocusPointOfInterest:, -isExposurePointOfInterestSupported,
// -exposurePointOfInterest, -setExposurePointOfInterest: and -lockForConfiguration: (measured,
// tools/corpus/objc-inventory.lua over ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7), and it owns NONE of the
// eight members below at any release held here. So the rectangle is carried by its centre through the
// release's own setter, the two support flags are the release's own support answers for the point, and the
// two refusals are the release's own refusals for the point - the 16.4 header states them for the point in the
// same words the 26.2 header states them for the rectangle (SDK 16.4 AVCaptureDevice.h:1083 and :1269 against
// 26.2's :1171).
//
//   -isFocusRectOfInterestSupported    the release's own -isFocusPointOfInterestSupported. Not a constant and
//                                     not a guess: a device whose focus cannot be pointed at cannot be told
//                                     where to weigh, and one whose focus can is told through the rectangle's
//                                     centre, which is exactly what the header says the setter does.
//   -minFocusRectOfInterestSize        { 0, 0 }, for the reason the geometry gives and the header's own words
//                                     agree with. Apple's minimum is the smallest area the sensor's focus
//                                     machinery can weigh, which it measures in sensor pixels of the active
//                                     format and normalizes; the release has no focus area anywhere - its
//                                     camera device carries a point and a format description and no such
//                                     quantity - so the smallest rectangle that still denotes a point is the
//                                     degenerate one, and { 0, 0 } is also what the header documents for a
//                                     device that does not support the rectangle at all (:1167). The
//                                     consequence is stated rather than hidden: the size check in the setter
//                                     can refuse a rectangle with a negative extent and nothing else.
//   -focusRectOfInterest               the rectangle the caller set, or the default rectangle for the
//                                     release's own current point of interest when none was set, or CGRectNull
//                                     when the device does not support the rectangle. The third case is
//                                     measured on this host's own camera: every rectangle of interest and
//                                     every default rectangle reads (inf, inf, 0, 0), which is CGRectNull.
//   -setFocusRectOfInterest:           the three refusals in the order Apple's own raises them (measured on
//                                     this host: sent unlocked it raises NSGenericException even though the
//                                     device does not support the rectangle, so the lock is checked first),
//                                     then the centre is applied through the release's own
//                                     -setFocusPointOfInterest: and the rectangle is kept.
//   -defaultRectForFocusPointOfInterest:
//                                     the degenerate rectangle at the point asked for, or CGRectNull for a
//                                     device that does not support the rectangle - which is what the header
//                                     says this method returns in that case (:1184) and what the host answers
//                                     here (measured, CGRectIsNull 1).
//
// ONE RESET, AND IT IS THE HEADER'S OWN: "If you later set the device's focusPointOfInterest, the
// focusRectOfInterest resets to the default sized rectangle of interest for the new focus point of interest"
// (:1171). The release's own point setter cannot be wrapped from a category, so the getter reconciles
// instead: a stored rectangle whose centre is no longer the release's point of interest was one the release's
// own setter has moved past, and the getter answers the default rectangle for the point that is current. The
// same sentence's other half - "If you change your AVCaptureDevice/activeFormat, the point of interest and
// rectangle of interest both revert to their default values" - needs nothing: the release reverts its own
// point, and the reconciliation follows it.
//
// ONE THING NOT CARRIED, and it is not small: Apple's minimum size and its default rectangle come from the
// hardware's focus area, and no release here has one. So on this port the extent of a rectangle of interest
// carries nothing: the rectangle is honoured through its centre, exactly as the header describes, and its
// size is bookkeeping the port keeps and hands back. That is stated here, in the registry rows and on the
// facts page rather than left for a reader to discover.
#import "CharonAVCaptureDeviceRectsOfInterest26.h"
#import <objc/runtime.h>

// The release's own lock reader, which is not in any public header but is a method of the release's own
// AVCaptureDevice at 5.1.1, 6.0, 6.1 and 6.1.3 (the configuration lock count above 0) and is what every
// public setter of 6.1.3's camera device asks before it does anything else. The same seam, and the same
// reason for it, as packages/a/apple-backports/AVFoundation/AVCaptureDevice+VideoZoom7.m and
// AVCaptureDevice+ActiveFrameDuration.m.
@interface AVCaptureDevice (CharonReleaseLock)
- (BOOL)isLockedForConfiguration;
@end

// One key per rectangle of interest. An associated object is the only place a category can keep one: the class
// belongs to the release and a category cannot add an ivar to it.
static const char charon_focus_rect_key;
static const char charon_exposure_rect_key;

// The default rectangle for a point of interest: the degenerate rectangle AT that point, which is the smallest
// rectangle the release's own unit can express (its point of interest is a CGPoint, with no extent). The
// helper exists because the same rectangle is the answer in three places - both default-rectangle methods and
// both resets - and writing it three times would be three chances to spell the geometry differently.
static CGRect charon_rect_for_point(CGPoint point)
{
    return CGRectMake(point.x, point.y, 0.0, 0.0);
}

// The centre of a rectangle, which is what the header says a set rectangle does to the point of interest.
static CGPoint charon_point_for_rect(CGRect rect)
{
    return CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
}

// Whether a rectangle is at least as large as the minimum this device's rectangle of interest has. The
// comparison is component-wise, which is what "your provided rectangle's size is smaller than the
// minFocusRectOfInterestSize" says, and CGRectZero is what both minimum sizes are here (see above).
static BOOL charon_rect_is_large_enough(CGRect rect, CGSize minimum)
{
    return rect.size.width >= minimum.width && rect.size.height >= minimum.height;
}

// A rectangle in an NSValue, and back. -[NSValue valueWithCGRect:] is UIKit's, not Foundation's, in SDK 16.4
// (measured: the selector is in no Foundation header of that SDK, and three files of this package that store a
// CGRect import <UIKit/UIKit.h> for it - which an AVFoundation source has no reason to do), so the rectangle
// travels as the bytes it is, with its own type encoding.
static NSValue *charon_rect_value(CGRect rect)
{
    return [NSValue valueWithBytes:&rect objCType:@encode(CGRect)];
}

static BOOL charon_rect_from_value(id stored, CGRect *out)
{
    if (![stored isKindOfClass:[NSValue class]])
        return NO;
    [(NSValue *)stored getValue:out];
    return YES;
}

// The rectangle the port keeps for one of the two, reconciled against the release's own point of interest: a
// stored rectangle whose centre is no longer that point is one the release's own setter has moved past, and the
// answer is then the default rectangle for the point that is current (the header's own reset, :1171/:1415).
static CGRect charon_rect_kept_or_default(id object, const char *key, CGPoint point, BOOL supported)
{
    if (!supported)
        return CGRectNull;
    CGRect kept;
    if (!charon_rect_from_value(objc_getAssociatedObject(object, key), &kept))
        return charon_rect_for_point(point);
    CGPoint centre = charon_point_for_rect(kept);
    if (centre.x != point.x || centre.y != point.y)
        return charon_rect_for_point(point);
    return kept;
}

@implementation AVCaptureDevice (CharonCaptureDeviceRectsOfInterest26)

#pragma mark - focus

- (BOOL)isFocusRectOfInterestSupported
{
    return [self isFocusPointOfInterestSupported];
}

- (CGSize)minFocusRectOfInterestSize
{
    return CGSizeZero;
}

- (CGRect)focusRectOfInterest
{
    return charon_rect_kept_or_default(self, &charon_focus_rect_key, self.focusPointOfInterest,
                                       self.isFocusRectOfInterestSupported);
}

- (CGRect)defaultRectForFocusPointOfInterest:(CGPoint)pointOfInterest
{
    if (!self.isFocusRectOfInterestSupported)
        return CGRectNull;
    return charon_rect_for_point(pointOfInterest);
}

- (void)setFocusRectOfInterest:(CGRect)focusRectOfInterest
{
    // The three refusals in the order Apple's own raises them, measured on this host: an unlocked send
    // raises NSGenericException even on a device whose support flag is NO, so the lock comes first.
    if (![self isLockedForConfiguration])
        @throw [NSException exceptionWithName:NSGenericException
                                       reason:@"focusRectOfInterest cannot be set without first successfully"
                                               " gaining exclusive ownership of the device using"
                                               " -lockForConfiguration:"
                                     userInfo:nil];
    if (!self.isFocusRectOfInterestSupported) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[AVCaptureDevice %@] Not supported - use -isFocusRectOfInterestSupported",
                           NSStringFromSelector(_cmd)];
        return;
    }
    if (!charon_rect_is_large_enough(focusRectOfInterest, self.minFocusRectOfInterestSize)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[AVCaptureDevice %@] The rectangle's size is smaller than"
                           @" minFocusRectOfInterestSize, which is what the header refuses"
                           @" (AVCaptureDevice.h:1171)",
                           NSStringFromSelector(_cmd)];
        return;
    }
    // The header's own effect, through the release's own setter: the point of interest becomes the centre of
    // the rectangle. The release asks the lock and its own support rule again, which is its business.
    [self setFocusPointOfInterest:charon_point_for_rect(focusRectOfInterest)];
    objc_setAssociatedObject(self, &charon_focus_rect_key, charon_rect_value(focusRectOfInterest),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - exposure

- (BOOL)isExposureRectOfInterestSupported
{
    return [self isExposurePointOfInterestSupported];
}

- (CGSize)minExposureRectOfInterestSize
{
    return CGSizeZero;
}

- (CGRect)exposureRectOfInterest
{
    return charon_rect_kept_or_default(self, &charon_exposure_rect_key, self.exposurePointOfInterest,
                                       self.isExposureRectOfInterestSupported);
}

- (CGRect)defaultRectForExposurePointOfInterest:(CGPoint)pointOfInterest
{
    if (!self.isExposureRectOfInterestSupported)
        return CGRectNull;
    return charon_rect_for_point(pointOfInterest);
}

- (void)setExposureRectOfInterest:(CGRect)exposureRectOfInterest
{
    if (![self isLockedForConfiguration])
        @throw [NSException exceptionWithName:NSGenericException
                                       reason:@"exposureRectOfInterest cannot be set without first successfully"
                                               " gaining exclusive ownership of the device using"
                                               " -lockForConfiguration:"
                                     userInfo:nil];
    if (!self.isExposureRectOfInterestSupported) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[AVCaptureDevice %@] Not supported - use"
                           @" -isExposureRectOfInterestSupported",
                           NSStringFromSelector(_cmd)];
        return;
    }
    if (!charon_rect_is_large_enough(exposureRectOfInterest, self.minExposureRectOfInterestSize)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[AVCaptureDevice %@] The rectangle's size is smaller than"
                           @" minExposureRectOfInterestSize, which is what the header refuses"
                           @" (AVCaptureDevice.h:1415)",
                           NSStringFromSelector(_cmd)];
        return;
    }
    [self setExposurePointOfInterest:charon_point_for_rect(exposureRectOfInterest)];
    objc_setAssociatedObject(self, &charon_exposure_rect_key, charon_rect_value(exposureRectOfInterest),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end