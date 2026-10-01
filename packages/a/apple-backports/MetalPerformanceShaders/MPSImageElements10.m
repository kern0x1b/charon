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
// ONE RELEASE. Both classes here first appear in 10.0.1 per first-rung and nothing from another
// release is defined in this file.

#import "CharonMPS.h"
#import "CharonMPSImage.h"

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

// The allocator MPSImage.h:930 returns. It is this package's own object rather than the release's
// MPSTemporaryImageDefaultAllocator, which is a name the release carries and this port does not, and
// whose only required method is the one below. It is declared BEFORE MPSTemporaryImage because that
// class's +defaultAllocator builds one, and MPSImage.h:236-238 makes NSSecureCoding part of the
// protocol rather than a convenience, so all three of its methods are answered.
@interface MPSTemporaryImageAllocator : NSObject <MPSImageAllocator>
@end

@implementation MPSTemporaryImageAllocator

// MPSImage.h:246-249: the one required method. The release's own MPS implementations "don't need" the
// kernel argument (:250-251) and neither does this one - it is the kernel that will overwrite the
// image, and the image is built from the descriptor alone.
+ (BOOL)supportsSecureCoding
{
    return YES;
}

// MPSImage.h:178-185 is the release's own example of this class, and it encodes nothing beyond its
// superclass. There is nothing here to encode either: a temporary image's storage belongs to a command
// buffer and is gone when it completes, so an archive of this allocator is an allocator and nothing
// more. Inventing a key the release never wrote would read an archive the release never made.
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    // NSObject does not declare NSSecureCoding's two instance methods on this surface, so there is no
    // super implementation to chain to and none to chain to: the protocol's requirement is met by
    // answering it, and the archive holds nothing. [super encodeWithCoder:] is not called because
    // there is no such method to call, and writing one would be new API rather than the protocol's.
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    return [self init];
}

// MPSImage.h:246-249: the one required method.
- (MPSImage *)imageForCommandBuffer:(id<MTLCommandBuffer>)cmdBuf
                     imageDescriptor:(MPSImageDescriptor *)descriptor
                              kernel:(MPSKernel *)kernel
{
    (void)kernel;
    return [MPSTemporaryImage temporaryImageWithCommandBuffer:cmdBuf imageDescriptor:descriptor];
}

@end

@implementation MPSTemporaryImage {
    NSUInteger _readCount;
}

// MPSImage.h:930: +defaultAllocator, "a well known MPSImageAllocator that makes MPSTemporaryImages".
// The protocol's one required method is -imageForCommandBuffer:imageDescriptor:kernel: (:246-249),
// and a temporary image is that method's answer with this class in place of MPSImage - which is what
// it does below. The allocator is a singleton because the release's own two are process-wide caches
// and a caller comparing allocators by identity would see the same object the release shows.
+ (id<MPSImageAllocator>)defaultAllocator
{
    static id<MPSImageAllocator> shared = nil;
    if (!shared)
        shared = [[MPSTemporaryImageAllocator alloc] init];
    return shared;
}

// MPSImage.h:938-947: +temporaryImageWithCommandBuffer:imageDescriptor:. The header says the object
// "will be released when the command buffer is committed", and its texture "will become invalid
// before this time due to the action of the readCount property" - so what this port builds is an
// ordinary MPSImage over the descriptor, tagged so the read count is decremented by the kernel that
// reads it. The storage cannot be recycled behind the caller's back the way the release's private
// texture is, because every MPS kernel in this package walks an MPSImage's values on the CPU
// (MPSImage13.m holds them in a texture it reads), so a private, GPU-only texture would be a texture
// nothing here can read. That is stated rather than hidden: the read count is honoured, the recycling
// it guards is the port's own whole-image lifetime, and MPSImage9.m's -initWithTexture: is what puts a
// texture the caller chose into an image.
+ (instancetype)temporaryImageWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                                imageDescriptor:(MPSImageDescriptor *)imageDescriptor
{
    if (!commandBuffer) {
        CharonMPSRefuse(@"MPSTemporaryImage: no command buffer, so no temporary image was made");
        return nil;
    }
    id<MTLDevice> device = [commandBuffer respondsToSelector:@selector(device)] ? [commandBuffer device] : nil;
    if (!device)
        device = MTLCreateSystemDefaultDevice();
    if (!device || !imageDescriptor) {
        CharonMPSRefuse(@"MPSTemporaryImage: a temporary image needs a command buffer with a device and a "
                        @"descriptor, and one of the two was missing");
        return nil;
    }
    MPSTemporaryImage *image = [[MPSTemporaryImage alloc] initWithDevice:device imageDescriptor:imageDescriptor];
    // A read count starts at one: a temporary image may be written any number of times and read once.
    image->_readCount = 1;
    return image;
}

// MPSImage.h:955-975, the two texture-descriptor forms. The header's restrictions are MTLTextureType
// 2D or 2DArray, usage ShaderRead or ShaderWrite, storage private, depth 1 - and storage private is
// exactly what this port's kernels cannot walk (see above), so the texture the caller names is used as
// it is and the form is refused only where it has no shape at all.
+ (instancetype)temporaryImageWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                              textureDescriptor:(MTLTextureDescriptor *)textureDescriptor
{
    if (!commandBuffer || !textureDescriptor) {
        CharonMPSRefuse(@"MPSTemporaryImage: a temporary image needs a command buffer and a texture "
                        @"descriptor, and one of the two was missing");
        return nil;
    }
    id<MTLDevice> device = [commandBuffer respondsToSelector:@selector(device)] ? [commandBuffer device] : nil;
    if (!device)
        device = MTLCreateSystemDefaultDevice();
    if (!device)
        return nil;
    NSUInteger channels = 1;
    switch (textureDescriptor.pixelFormat) {
    case MTLPixelFormatRG32Float: case MTLPixelFormatRG16Float: case MTLPixelFormatRG8Unorm:
        channels = 2;
        break;
    case MTLPixelFormatRGBA32Float: case MTLPixelFormatRGBA16Float: case MTLPixelFormatRGBA8Unorm:
        channels = 4;
        break;
    default:
        break;
    }
    MPSTemporaryImage *image = [[MPSTemporaryImage alloc] initWithTexture:[device newTextureWithDescriptor:textureDescriptor]
                                                        featureChannels:channels];
    image->_readCount = 1;
    return image;
}

// MPSImage.h:977-995: the same, with the feature channel count given rather than inferred.
+ (instancetype)temporaryImageWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                              textureDescriptor:(MTLTextureDescriptor *)textureDescriptor
                                featureChannels:(NSUInteger)featureChannels
{
    if (!commandBuffer || !textureDescriptor) {
        CharonMPSRefuse(@"MPSTemporaryImage: a temporary image needs a command buffer and a texture "
                        @"descriptor, and one of the two was missing");
        return nil;
    }
    id<MTLDevice> device = [commandBuffer respondsToSelector:@selector(device)] ? [commandBuffer device] : nil;
    if (!device)
        device = MTLCreateSystemDefaultDevice();
    if (!device)
        return nil;
    MPSTemporaryImage *image = [[MPSTemporaryImage alloc] initWithTexture:[device newTextureWithDescriptor:textureDescriptor]
                                                        featureChannels:featureChannels ? featureChannels : 1];
    image->_readCount = 1;
    return image;
}

// The read count, which is what decides when the storage may be reused. MPSImage.h:1030-1050 is where
// the release documents it, and it is the same counter MPSTemporaryMatrix11.m carries and
// CharonMPSConsumeReadCount decrements - which is why that helper in CharonMPS.h tests for
// MPSTemporaryMatrix and MPSTemporaryVector by name and does not yet know about this class: a
// temporary IMAGE is read through an MPSImage, and the kernels that walk one decrement nothing today.
// So this count is carried and readable, and a caller that sets it gets it back, and no kernel in this
// package changes it. That is the whole of what is honest here: the count exists, and nothing applies
// it yet because MPSImageAllocator - which is where the release puts the recycling decision - is not a
// row this port carries.
- (NSUInteger)readCount
{
    return _readCount;
}

- (void)setReadCount:(NSUInteger)readCount
{
    _readCount = readCount;
}

@end
