// MPSImagePyramid, the base class "for creating different kinds of pyramid images"
// (MPSImageConvolution.h:495), from the iPhoneOS 16.4 surface of MPSImageConvolution.h.
//
// One object for one release, and the release's own measurement is the judge rather than the header's
// annotation. MPSImageConvolution.h:519 annotates this class ios(10.0), and the registry's
// sdk-26.2-surface.tsv carries 10.0 for it, so this object's registry rows keep `introduced` at what
// the SDK declares. But the release does not EXPORT it until 16.0, and an object's placement is
// decided by what a client can bind, not by whether the name is in the cache:
//
//   * tools/cache-index/first-rung.py answers 10.0.1 for _OBJC_CLASS_$_MPSImagePyramid, and that is
//     TRUE and not the question: first-rung measures whether a rung CARRIES a name, and this one
//     carries it from 10.0.1 because MPSImageGaussianPyramid's super_class points at it.
//   * tools/release-split.lua measures what a rung EXPORTS, and answers 16.0 - which is what
//     modules/apple/backports.lua's band() places an object by, and what makes an object carrying
//     this class and MPSImageGaussianPyramid (10.0.1) a file that band() refuses with "an object
//     carries API that arrived in one release, so split it". Both run over the held ladder and agree.
//
// MEASURED over the held armv7/armv7s ladder, the MPS* names each rung's export trie carries that
// contain "Pyramid": 10.0.1 and 11.0 export MPSImageGaussianPyramid and no MPSImagePyramid; 12.0 adds
// MPSImageLaplacianPyramid, +Add and +Subtract and still no MPSImagePyramid; 16.0 adds
// _OBJC_CLASS_$_MPSImagePyramid and _OBJC_METACLASS_$_MPSImagePyramid. So the kernels over this class
// are exported BEFORE it, which is why MPSImagePyramid10.m and MPSImageLaplacianPyramid12.m can both
// read the filter this object publishes and neither needs to ask whether it is there: a band keeps an
// object exactly when the release does not export it, so a band that keeps either kernel - below 10.0.1
// and below 12.0 respectively - is below 16.0 and keeps this one too. What the three objects share is in
// CharonMPSPyramid.h.
//
// THE FILTER, which every pyramid here uses and which the header gives three ways.
//   the default (MPSImageConvolution.h:505-506)  "The filter kernel is the outer product of
//     w = [ 1/16,  1/4,  3/8,  1/4,  1/16 ]^T, with itself"
//   by a centre weight (:527-528)  "the outer product ww^T, where
//     w = [ (1/4 - a/2),  1/4,  a,  1/4,  (1/4 - a/2) ]^T"
//   or the caller's own (:548-552, row major, kernelWidth * kernelHeight values)
// The kernel must be odd in both directions (:562-569), and that is refused by name rather than
// answered with a filter the header does not describe.
//
// WHAT IS NOT CLAIMED. No number in this file is a measurement of Apple's code - the release's own MPS
// crashes on this family's encode, which facts/MetalPerformanceShaders/Elements10.md records with its
// transcript. What is written here is transcribed from the header above; what has been checked is the
// armv7 link, that this object defines the class it says.

#import "CharonMPSPyramid.h"

// MPSImageConvolution.h marks -initWithDevice:kernelWidth:kernelHeight:weights: the designated
// initializer of MPSImagePyramid (:578 area) and -initWithCoder:device: another, and this class refuses
// the coder form because the release's keys for a filter are in no header, so it cannot chain to a
// designated initializer of its own. The same pragma MPSImage9.m carries for the same reason.
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation MPSImagePyramid {
    NSMutableData *_kernel;      // the filter's own weights, row major, kernelWidth * kernelHeight of them
    NSUInteger _kernelWidth, _kernelHeight;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device kernelWidth:(NSUInteger)kernelWidth kernelHeight:(NSUInteger)kernelHeight weights:(const float *)kernelWeights
{
    if (!(self = [super initWithDevice:device]))
        return nil;
    if (!kernelWidth || !kernelHeight || !kernelWeights ||
        (kernelWidth % 2) == 0 || (kernelHeight % 2) == 0) {
        CharonMPSRefuse(@"MPSImagePyramid: a %lu by %lu kernel with weights %s is refused;"
                        @" MPSImageConvolution.h:562-569 says the width and the height must be odd",
                        (unsigned long)kernelWidth, (unsigned long)kernelHeight,
                        kernelWeights ? "given" : "not given");
        return nil;
    }
    _kernelWidth = kernelWidth;
    _kernelHeight = kernelHeight;
    _kernel = [NSMutableData dataWithLength:kernelWidth * kernelHeight * sizeof(float)];
    if (!_kernel) {
        CharonMPSRefuse(@"MPSImagePyramid: no memory for a %lux%lu kernel, so no object was made",
                        (unsigned long)kernelWidth, (unsigned long)kernelHeight);
        return nil;
    }
    [_kernel replaceBytesInRange:NSMakeRange(0, kernelWidth * kernelHeight * sizeof(float)) withBytes:kernelWeights];
    return self;
}

// The default filter of :505-506, w = [ 1/16, 1/4, 3/8, 1/4, 1/16 ]^T as the outer product ww^T.
- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    float w[5] = { 1.0f / 16.0f, 1.0f / 4.0f, 3.0f / 8.0f, 1.0f / 4.0f, 1.0f / 16.0f };
    float kernel[25];
    for (NSUInteger ky = 0; ky < 5; ky++)
        for (NSUInteger kx = 0; kx < 5; kx++)
            kernel[ky * 5 + kx] = w[ky] * w[kx];
    return [self initWithDevice:device kernelWidth:5 kernelHeight:5 weights:kernel];
}

// The centre weight of :527-528: w = [ (1/4 - a/2), 1/4, a, 1/4, (1/4 - a/2) ]^T as the outer product.
- (instancetype)initWithDevice:(id<MTLDevice>)device centerWeight:(float)centerWeight
{
    float edge = 1.0f / 4.0f - centerWeight / 2.0f;
    float w[5] = { edge, 1.0f / 4.0f, centerWeight, 1.0f / 4.0f, edge };
    float kernel[25];
    for (NSUInteger ky = 0; ky < 5; ky++)
        for (NSUInteger kx = 0; kx < 5; kx++)
            kernel[ky * 5 + kx] = w[ky] * w[kx];
    return [self initWithDevice:device kernelWidth:5 kernelHeight:5 weights:kernel];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    // For the reason MPSImageConvolution13.m gives for its own: the release's keys for a kernel's filter
    // are in no header, so an invented key would read an archive the release never wrote. Not recorded
    // as round-tripping; the initializers above are the way to make one.
    (void)aDecoder;
    (void)device;
    CharonMPSRefuse(@"MPSImagePyramid: -initWithCoder:device: is not carried - the release's keys for a"
                    @" pyramid's filter are in no header, so a decoder cannot rebuild them honestly");
    return nil;
}

- (NSUInteger)kernelWidth { return _kernelWidth; }
- (NSUInteger)kernelHeight { return _kernelHeight; }

// The three the kernels over this class read, out of the two ivars above, which a subclass's category
// cannot see - the compiler says so outright ("instance variable '_kernel' is private"). The names are
// Charon's own: no SDK header declares them.
- (const float *)charon_mps_filter { return (const float *)[_kernel bytes]; }
- (NSUInteger)charon_mps_filterWidth { return _kernelWidth; }
- (NSUInteger)charon_mps_filterHeight { return _kernelHeight; }

@end
