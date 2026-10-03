#import <CoreImage/CoreImage.h>

// The CIFilter convenience constructors of iOS 18.0: 8 of the 239 the SDK's own
// CIFilterBuiltins.h declares, which are class methods that take nothing and answer a filter.
//
// iOS 18.0 is the first held rung that exports the other eight.
//
// WHAT THEY ARE, MEASURED: on the host, +[CIFilter areaAlphaWeightedHistogramFilter] answers exactly the object
// +[CIFilter filterWithName:@"CIAreaAlphaWeightedHistogram"] answers - the same class, the same name, the same
// inputKeys, outputKeys and attributes, and, for 237 of the 239, the same rendered RGBA
// bytes over a fixed 32x32 window.  tests/backports/host/ciimagefilter/ builds these very objects with
// their selectors prefixed and asks both in one process; it compared 478 fields over all 239
// constructors, rendered and compared 237 of them, and reported 0 differences.  Every
// input of every filter is given the value a FRESH filter of that name already answers for it, so the
// values compared are Apple's own defaults and not ones the harness chose; the two it cannot render are
// named in facts/CoreImage/FilterBuiltins.md.
//
// So each method here is that one call, and the filter's own arithmetic is the release's:
// +filterWithName: is exported from iOS 3.0 and answers nil for a name the release has no filter of,
// which is what Apple documents for a filter that does not exist on the running system
// (facts/CoreImage/ImageApplyingFilter.md).
//
// The port carries CIFilter's constructors and not CIFilter: the class is the release's own from
// iOS 5.0 (tools/cache-index/first-rung.py _OBJC_CLASS_$_CIFilter -> 5.0), so these are a category
// on it, and charon_collect installs a category method only where the class does not answer the
// selector, which is exactly the band this object is for.

@implementation CIFilter (CharonFilterBuiltins18)

+ (CIFilter *)areaAlphaWeightedHistogramFilter
{
    return [CIFilter filterWithName:@"CIAreaAlphaWeightedHistogram"];
}

+ (CIFilter *)areaBoundsRedFilter
{
    return [CIFilter filterWithName:@"CIAreaBoundsRed"];
}

+ (CIFilter *)blurredRectangleGeneratorFilter
{
    return [CIFilter filterWithName:@"CIBlurredRectangleGenerator"];
}

+ (CIFilter *)cannyEdgeDetectorFilter
{
    return [CIFilter filterWithName:@"CICannyEdgeDetector"];
}

+ (CIFilter *)maximumScaleTransformFilter
{
    return [CIFilter filterWithName:@"CIMaximumScaleTransform"];
}

+ (CIFilter *)roundedRectangleStrokeGeneratorFilter
{
    return [CIFilter filterWithName:@"CIRoundedRectangleStrokeGenerator"];
}

+ (CIFilter *)sobelGradientsFilter
{
    return [CIFilter filterWithName:@"CISobelGradients"];
}

+ (CIFilter *)toneMapHeadroomFilter
{
    return [CIFilter filterWithName:@"CIToneMapHeadroom"];
}

@end
