// MPSImageElements10.m - the image classes iOS 10 added that this port answers, in ONE object for the
// ONE release they belong to. Every number on these rows is measured against the host's own MPS and
// not read off the header: tests/backports/host/mpsimage10/run.sh is the harness.
//
// WHAT IS HERE:
//
//   MPSImageLaplacian   the fixed 3x3 second derivative, MPSImageConvolution.h:108-133: the weights
//                      [0 1 0; 1 -4 1; 0 1 0] at :110-114, and a bias of its own at :118-131.
//
//   MPSTemporaryImage   the MPSImage subclass whose storage the framework recycles,
//                      MPSImage.h:927-1010. Its three class methods and its two initialisers are the
//                      whole of what a caller reaches, and all five are below.
//
// WHY THE LAPLACIAN IS NOT A SECOND CONVOLUTION. The header calls this class "an optimized variant
// of the MPSImageConvolution filter" (:109-110) and says the same result is reached by building an
// MPSImageConvolution with those weights (:115-116) - so the arithmetic is MPSImageConvolution13.m's
// and is not written twice. What is new at 10.0 is the class: the weights are fixed, so this object
// holds none of them, and what it adds is the bias. The walk is reached through the one method added
// to MPSUnaryImageKernel below, which is the seam shape MPSImageThreshold13.m already uses for the
// five threshold kernels' shared walk. It cannot be a shared C function: AGENTS.md records that a file
// whose exports a band's release already has is left out of that band, so a cross-object C call is
// Undefined symbols in later bands only - `backports-gate` links one band and passes and the
// all-band build is where it breaks.
//
// MEASURED, and it is the whole content of the laplacian row. Over a 4x4 of 1..16 with the edge mode
// left at its default, the release answers, row by row:
//
//     3   2   1  -5        -4   0   0  -9        -8   0   0 -13       -29 -18 -19 -37
//
// and with -bias set to 1 every one of those is exactly one larger. That settles the ORDER of
// MPSImageConvolution.h:62-72 ("added to convolved pixel before it is converted back to the storage
// format") by measurement rather than by reading: sum, then bias, then store.
//
// The off-image value is ZERO and not the nearest value. A clamped border would answer 2 at (0,0)
// rather than 3, because the clamped left and top neighbours would both be the corner's own value.
// The window is centred on the output, so a 4-wide image's rightmost column reads one column off
// the edge and answers -5 at (3,0) from 4 - 4*4 + 3 + 0.
//
// WHAT IS NOT HERE, each with the measurement that decides it, and none of it decided dead:
//
//   MPSImagePyramid and MPSImageGaussianPyramid. Both classes resolve on this host and hold their
//   parameters - kernelWidth 5 and kernelHeight 5 by default from -initWithDevice:,
//   MPSImageConvolution.h:527-531, and 3x3 from the custom initialiser at :540-544, all measured - so
//   nothing here is a dead name. What is missing is a substrate that answers the ENCODE, and the
//   measurement is the host's own crash: the pyramid is "enqueued as a in-place operation" that
//   "fills all mipmap levels after level=1" (:513-520), and running it against this host's own MPS on
//   an 8x8 R32Float texture with four mip levels takes the process down with SIGSEGV, exit 139,
//   transcript .agent-work/runs/host/mpsr10/pyramid.txt. Seen from this side the same gap is that
//   MPSImage13.m makes every texture with mipmapped:NO (:253), so there are no mip levels for such a
//   fill to write into.
//
//   MPSImageConversion. Its designated initialiser takes a CGColorConversionInfoRef,
//   MPSImageConversion.h:60-64, and that whole CoreGraphics family is absent from this port
//   (registry/CoreGraphics/absent_CoreGraphics.json, five rows); first-rung answers
//   _CGColorConversionInfoCreate at 10.0.1. A conversion kernel whose colourspace converter does not
//   exist is a class that cannot do its one job, and its measured no-op path is not the job.
//
//   MPSImageLaplacianPyramid, MPSImageLaplacianPyramidAdd and MPSImageLaplacianPyramidSubtract are NOT
//   in this release at all: first-rung answers 12.0 for all three, against 10.0.1 for the two classes
//   above, so a 10.0 object carrying them would mix two releases. They are 12.0 work.
//
// THE ALLOCATOR IS NOT IN THIS FILE. MPSImage.h:930 declares +defaultAllocator, which returns an
// id<MPSImageAllocator>, and the allocator this port answers it with is a class of its own - and a
// class of its own is an _OBJC_CLASS_$_ symbol, which no release carries, so defining it here made
// release-split read this object as spanning 10.0.1 and "none". MEASURED: the run printed
//   MPSImageElements10.o  MIXED-RELEASES  10.0.1,none
// and named the two symbols. So the allocator is in CharonMPSTemporaryImage.m, which exports one
// charon_-prefixed C function and no API symbol of its own - the shape
// packages/a/apple-backports/UIKit/UIViewController+DocumentMenu.m uses, and the reason is in
// charon/AGENTS.md: a file whose exports a band's release already has is left out of that band.
//
// ONE RELEASE. Both classes here first appear in 10.0.1 per first-rung and nothing from another
// release is defined in this file.

#import "CharonMPS.h"
#import "CharonMPSImage.h"
#import "CharonMPSTemporaryImage.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"

// [0 1 0; 1 -4 1; 0 1 0] row-major, MPSImageConvolution.h:110-114. File-scope and static, so it is
// this package's own data and not an exported symbol of any release - no release exports a kernel of
// weights, and release-split's internal() reads the `Charon` name and agrees. It is `k`-prefixed as
// well so it cannot be mistaken for an API a caller writes.
static const float kCharonMPSImageLaplacianWeights[9] = { 0.0f, 1.0f, 0.0f,
                                                           1.0f, -4.0f, 1.0f,
                                                           0.0f, 1.0f, 0.0f };

// The walk MPSImageConvolution13.m already has, reached by a method rather than by its C function, so
// that this 10.0 object and that 9.0 object can share one implementation across bands. The edge mode is
// NOT checked here: MPSImageConvolution13.m already refuses anything but MPSImageEdgeModeZero by name,
// so a caller who asked for a clamp is told by the walk itself instead of being answered with a zero
// border they did not ask for.
@interface MPSUnaryImageKernel (CharonMPSConvolutionSeam)
- (void)charon_mps_convolveRegionWithSource:(MPSImage *)source
                                destination:(MPSImage *)destination
                                 kernelWidth:(NSUInteger)kernelWidth
                                kernelHeight:(NSUInteger)kernelHeight
                                    weights:(const float *)weights
                                        bias:(double)bias
                                        what:(NSString *)what;
@end

@implementation MPSImageLaplacian {
    float _bias;
}

@synthesize bias = _bias;

// MPSImageConvolution.h:118-131 declares bias, "Default value is 0.0f". Measured on a fresh kernel of
// this class: 0, which is also the header's stated default. That is the whole of this class's own
// state - the kernel is the header's fixed one and the bias is the one property it declares.
- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _bias = 0.0f;
    }
    return self;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  sourceImage:(MPSImage *)sourceImage
               destinationImage:(MPSImage *)destinationImage
{
    [self charon_mps_convolveRegionWithSource:sourceImage
                                  destination:destinationImage
                                   kernelWidth:3
                                  kernelHeight:3
                                      weights:kCharonMPSImageLaplacianWeights
                                          bias:(double)self.bias
                                          what:@"MPSImageLaplacian"];
}

@end
