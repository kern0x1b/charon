#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

// CIColor exists on iOS 6: what it does not have is a way to name the colour space a colour was
// measured in. The components of a colour given in a space are that colour as the space sees it, so
// the colour is built by matching it into the space the renderer works in - which is what CoreGraphics
// does with a colour and a space, and not an invention. What comes back is the framework's own CIColor,
// so it is a real colour object and every existing method of it works on it.

static CGColorRef CharonCIColorConvert(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha, CGColorSpaceRef space)
{
    // The colour as the named space sees it, and then the same colour in the space the renderer works
    // in, which is the one a CIColor of that colour is made with.
    if (!space)
        space = CGColorSpaceCreateDeviceRGB();
    CGColorRef given = CGColorCreate(space, (CGFloat[]){red, green, blue, alpha});
    // The colour as the named space sees it, matched into the space the renderer works in, which is
    // what CoreGraphics does with a colour and a space and is not a conversion invented here.
    CGColorRef matched = given ? CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceCreateDeviceRGB(),
                                                                        kCGRenderingIntentDefault, given, NULL)
                               : NULL;
    CGColorRelease(given);
    return matched;
}

@implementation CIColor (CharonColorSpace)

+ (instancetype)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue colorSpace:(CGColorSpaceRef)colorSpace
{
    return [self colorWithCGColor:CharonCIColorConvert(red, green, blue, 1, colorSpace)];
}

+ (instancetype)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
                   colorSpace:(CGColorSpaceRef)colorSpace
{
    return [self colorWithCGColor:CharonCIColorConvert(red, green, blue, alpha, colorSpace)];
}

- (instancetype)initWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue colorSpace:(CGColorSpaceRef)colorSpace
{
    return [self initWithCGColor:CharonCIColorConvert(red, green, blue, 1, colorSpace)];
}

- (instancetype)initWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
                  colorSpace:(CGColorSpaceRef)colorSpace
{
    return [self initWithCGColor:CharonCIColorConvert(red, green, blue, alpha, colorSpace)];
}

- (instancetype)initWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
    return [self initWithRed:red green:green blue:blue alpha:1];
}

@end

// The named colours: the primaries and neutrals of the space colours are read in, which is the sRGB
// space the system draws in. Each is built through the caller's own initialiser, so the colour is the
// one that initialiser makes and not a separate table of numbers.
@implementation CIColor (CharonNamedColors)

#define CharonNamedColor(name, r, g, b, a)                                                                                \
    + (CIColor *)name                                                                                                     \
    {                                                                                                                     \
        static CIColor *color;                                                                                            \
        if (!color)                                                                                                       \
            color = [CIColor colorWithRed:r green:g blue:b alpha:a colorSpace:CGColorSpaceCreateDeviceRGB()];                 \
        return color;                                                                                                     \
    }

CharonNamedColor(blackColor, 0, 0, 0, 1)
CharonNamedColor(whiteColor, 1, 1, 1, 1)
CharonNamedColor(grayColor, 0.5, 0.5, 0.5, 1)
CharonNamedColor(redColor, 1, 0, 0, 1)
CharonNamedColor(greenColor, 0, 1, 0, 1)
CharonNamedColor(blueColor, 0, 0, 1, 1)
CharonNamedColor(cyanColor, 0, 1, 1, 1)
CharonNamedColor(magentaColor, 1, 0, 1, 1)
CharonNamedColor(yellowColor, 1, 1, 0, 1)
CharonNamedColor(clearColor, 0, 0, 0, 0)

@end
