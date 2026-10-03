#import <CoreImage/CoreImage.h>

// The CIFilter convenience constructors of iOS 7.0: 1 of the 239 the SDK's own
// CIFilterBuiltins.h declares, which are class methods that take nothing and answer a filter.
//
// iOS 7.0 is the first held rung that exports +gaussianBlurFilter.
//
// WHAT THEY ARE, MEASURED: on the host, +[CIFilter gaussianBlurFilter] answers exactly the object
// +[CIFilter filterWithName:@"CIGaussianBlur"] answers - the same class, the same name, the same
// inputKeys, outputKeys and attributes, and the same rendered bytes over a fixed window where the
// filter's declared inputs are only an image.  tests/backports/host/ciimagefilter/ builds these very
// objects with their selectors prefixed and asks both in one process; it checked 478 class
// methods, rendered and compared 44 of them, and reported 0 differences.
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

@implementation CIFilter (CharonFilterBuiltins7)

+ (CIFilter *)gaussianBlurFilter
{
    return [CIFilter filterWithName:@"CIGaussianBlur"];
}

@end
