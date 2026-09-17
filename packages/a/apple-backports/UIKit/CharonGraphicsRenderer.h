#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

CG_EXTERN size_t CGBitmapGetAlignedBytesPerRow(size_t bytesPerRow);
CG_EXTERN CGBlendMode CGContextGetBlendMode(CGContextRef context);
CG_EXTERN CGFloat CGContextGetLineWidth(CGContextRef context);

@interface UIGraphicsRendererFormat (CharonRenderer)
- (void)_setBounds:(CGRect)bounds;
@end

@interface UIGraphicsRendererContext (CharonRenderer)
- (instancetype)initWithCGContext:(CGContextRef)context format:(UIGraphicsRendererFormat *)format;
@property (nonatomic) BOOL __createsImages;
@end

@interface UIGraphicsImageRendererFormat (CharonRenderer)
- (CGFloat)_contextScale;
@end
