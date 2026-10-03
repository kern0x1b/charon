// MPSNNGraph and the node layer it walks, from MPSNNGraph.h, MPSNNGraphNodes.h and
// MPSNeuralNetworkTypes.h of the SDK of iOS 16.4. One object for one release: the band machinery keeps
// an object whole or drops it whole, so a file here carries the API of exactly one release.
//
// FOURTEEN CLASSES AND ONE CATEGORY, and the fourteen is the number settled from the headers rather than
// from any note. The file implements MPSNNGraph, MPSNNImageNode, MPSNNStateNode, MPSNNFilterNode,
// MPSNNDefaultPadding, MPSNNBinaryArithmeticNode, MPSNNAdditionNode, MPSNNSubtractionNode,
// MPSNNMultiplicationNode, MPSNNDivisionNode, MPSNNConcatenationNode, MPSCNNPoolingNode,
// MPSCNNPoolingAverageNode and MPSCNNPoolingMaxNode, and adds one category on MPSImage. That is eleven
// MPSNN* classes and three MPSCNNPooling* ones; "fourteen node classes" and "ten classes" are the same
// list counted at two points of its own history, the ten being the first commit's MPSNN* names before the
// pooling nodes arrived in the second.
//
//   python3 tools/cache-index/first-rung.py MPSNNGraph MPSNNImageNode MPSNNStateNode MPSNNFilterNode \
//       MPSNNPadding MPSNNDefaultPadding MPSNNBinaryArithmeticNode MPSNNAdditionNode \
//       MPSNNSubtractionNode MPSNNMultiplicationNode MPSNNDivisionNode MPSNNConcatenationNode \
//       MPSCNNPoolingNode MPSCNNPoolingAverageNode MPSCNNPoolingMaxNode
//
// reads 11.0 for every one of them, and 12.0 for MPSNNGradientFilterNode, MPSNNGradientStateNode,
// MPSNNLabelsNode and MPSNNReduceRowSum. That is why this file stops at the 11.0 names: the gradient and
// training half of the graph arrived a release later and belongs to the object for that release. A 12.0
// name here would make the object carry API of two releases, which `misplaced()` in backports.lua
// refuses and tools/release-split.lua flags independently - release-split reads band points only, so it
// would pass a 12.0 name here silently and be wrong.
//
// WHAT THE RELEASE CARRIES THAT THESE NAMES DO NOT: MPSNNGraph is declared MPS_UNAVAILABLE on
// -initWithDevice:, and MPSNNImageNode, MPSNNStateNode and MPSNNFilterNode all mark -init NS_UNAVAILABLE.
// Those three node classes are placeholders in the release: an image node is a POSITION in a graph, made
// by a filter's .resultImage or by the caller for a graph input; a filter node is a virtual base class
// ("This is a virtual base class. Make MPSNNFilterNode subclass objects instead", MPSNNGraphNodes.h:340).
// So the three classes below hold names and answers and refuse to be built by name, which is what their
// own headers say and what MPSKernel does for the framework's other abstract bases.
//
// WHY THE GRAPH RUNS AT ALL ON iOS 6: nothing here needs Metal. MPSNNGraph walks the node graph it was
// given, and each node's encode runs the kernel object the node holds - an MPSImageAdd, a pooling
// kernel - over host memory behind an MTLBuffer, which is the path every other MPS kernel in this
// package takes (facts/MetalPerformanceShaders/Cnn.md; MPSImageArithmetic13.m says the same of its own
// four). The graph adds the walk, the shape arithmetic and the intermediate-image lifetime. It adds no
// arithmetic of its own that a kernel does not already do.
//
// THE PADDING ARITHMETIC IS THE HEADER'S OWN, NOT A GUESS. MPSNeuralNetworkTypes.h:379-431 gives the two
// formulas in full, as the code a padding policy is expected to write. They are transcribed below one for
// one, including the `style * (filterWindowSize - 1)` term that separates the three size policies from
// each other and the `readSize = (destSize-1)*stride + filterWindowSize` term that is what makes the
// offset negative for a centred window. An offset invented here would move every kernel's output by a
// pixel, and the pooling table in Cnn.md is measured in whole pixels. The host case extracts that C block
// from the header itself, compiles it and compares it with the two functions below over every shape, so
// what it compares is the header's compiled code and not a restatement of it.
//
// THE CONCATENATION RULE IS THE HEADER'S TOO, INCLUDING THE FOUR: MPSNNGraphNodes.h:2443-2446 says
// "As all images are padded out to a multiple of four feature channels, M, N and O here are also
// multiples of four, even when the MPSImages are not", so a destination sized to the UNpadded sum of the
// channels would be a different image than the release's, by up to three channels per source.
//
// WHAT IS NOT HERE, AND WHY, is listed at each class below, where the warning for it is turned off. The
// whole of it is seventeen methods, and clang asks for all seventeen:
//
//   four at iOS 11.3   +paddingForTensorflowAveragePooling, +paddingForTensorflowAveragePoolingValidOnly,
//                      -encodeBatchToCommandBuffer:sourceImages:sourceStates:intermediateImages:destinationStates:,
//                      -[MPSNNBinaryArithmeticNode gradientFiltersWithSources:]
//   one  at iOS 12.0   -trainingGraphWithSourceGradient:nodeHandler:
//   two  at iOS 12.1   -readCountForSourceImageAtIndex:, -readCountForSourceStateAtIndex:
//   two  at iOS 13.0   -initWithDevice:resultImages:resultsAreNeeded:, +graphWithDevice:resultImages:resultsAreNeeded:
//   five at no date, all of which hand back the 12.0 gradient half:
//                      -gradientFilterWithSource:, -gradientFilterWithSources:,
//                      -gradientFiltersWithSource:, -gradientFiltersWithSources:, -gradientClass
//   one  at no date, whose two arguments are NSArray<MPSImageBatch*>* and NSArray<MPSStateBatch*>*:
//                      -encodeBatchToCommandBuffer:sourceImages:sourceStates:
//   two  deprecated    -initWithDevice:resultImage:, +graphWithDevice:resultImage:, both carrying
//                      MPS_AVAILABLE_STARTING_BUT_DEPRECATED ios(11.0, 11.3) - the pre-11.3 spellings of
//                      the two initializers this object does implement.
//
// Not one of the seventeen is a name this release added, and every one's date is written beside its name
// where it is listed.
//
// The four suppressions are push/pop pairs, one above each @implementation that has one, each with its
// own list of names and its own reason - not a file-wide `#pragma clang diagnostic ignored` with no
// record of what it hides. The two ways to have no pragma at all were both measured and both refused:
// defining the seventeen is the mixed release `misplaced()` in backports.lua raises on (and which
// tools/release-split.lua cannot see, because it reads band points and not a file's declared release),
// and `@dynamic` does not silence -Wincomplete-implementation for a method, only for a property
// (measured: for `@dynamic gamma;` clang answers both "method definition for 'gamma' not found
// [-Wincomplete-implementation]" and "property implementation must have its declaration in interface").
// Carrying them would be four more objects, one per release - 11.3, 12.0, 12.1 and 13.0 - each with its
// own placement to measure and its own rows, which is the right way and is a piece of work of its own.

#import "CharonMPS.h"
#import "CharonMPSCnn.h"
#import "CharonMPSImage.h"

// The private surface the graph and its nodes share. None of it is a name an SDK header declares: the
// release reaches a node's kernel and a node's sources through its own internal tables, and a graph in
// this port needs the same three edges - sources, kernel, result - under names of its own. Each selector
// is prefixed so that a class the release also carries is not shadowed, and each is declared on the
// class that owns the edge, so a subclass inherits the default and overrides only what it changes.
//
// MPSNNPadding is the one name here that is NOT private: the SDK declares it, it is a protocol, and
// MPSNNDefaultPadding below CONFORMS to it. The conformance is what emits the protocol's own metadata,
// which is what a row of kind `protocol` is answered by (backports.lua:1938-1946). A forward declaration
// would add nothing, because the SDK header already declares the protocol and its methods.
@interface MPSNNImageNode (CharonMPSNN)
// The image the walk bound to this position. A node holds its position and the image currently there;
// the release keeps the same pair in its own node table and the graph walks the nodes, not the images.
- (MPSImage *)charon_mps_image;
- (void)charon_mps_setImage:(MPSImage *)image;
@end

@interface MPSNNStateNode (CharonMPSNN)
- (MPSState *)charon_mps_state;
- (void)charon_mps_setState:(MPSState *)state;
@end

// An MPSImage's own shape as a descriptor. MPSImage carries its shape as width, height, featureChannels
// and numberOfImages (MPSImage.h:402-417) and has no descriptor property of its own, and a graph has to
// size one node's result from the shape of the node it reads. So the descriptor is made here, in the one
// place that does it, from the four properties the image already answers - it is the shape, and not an
// object with a lifetime of its own.
@interface MPSImage (CharonMPSNN)
- (MPSImageDescriptor *)charon_mps_descriptor;
@end

@interface MPSNNFilterNode (CharonMPSNN)
// The node's sources, in the order its kernel reads them, and the one result image it produces.
- (NSArray<MPSNNImageNode *> *)charon_mps_sourceNodes;
- (void)charon_mps_setSourceNodes:(NSArray<MPSNNImageNode *> *)nodes;
// Add one source to a node that is being built, which is how every subclass in this file wires itself:
// the sources are the node's own edge to the nodes it reads, and there is no other way in.
- (void)charon_mps_addSourceNode:(MPSNNImageNode *)node;
// The kernel the node stands for, and the images bound to it for one encode.
- (MPSKernel *)charon_mps_kernel;
- (MPSImage *)charon_mps_sourceImageAtIndex:(NSUInteger)index;
- (void)charon_mps_setSourceImages:(NSArray<MPSImage *> *)images;
- (MPSImage *)charon_mps_destinationImage;
- (void)charon_mps_setDestinationImage:(MPSImage *)image;
// The shape the result takes, given the shape the source takes. The graph asks every node for this
// before any encode, because the intermediate images are allocated up front and a walk that discovered
// a shape halfway through would have nothing to allocate into.
- (MPSImageDescriptor *)charon_mps_destinationDescriptorForSource:(MPSImageDescriptor *)source;
// The device the node's kernel is made against. An MPSImageArithmetic initialiser takes one and the
// port's kernels do no Metal work with it, so it is the device the graph runs on and nothing else.
- (void)charon_mps_setDevice:(id<MTLDevice>)device;
- (id<MTLDevice>)charon_mps_device;
// This node's share of one encode. The base class has no kernel and says so once; a real node runs its
// own kernel here.
- (void)charon_mps_encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer;
@end


// The three size policies MPSNNPaddingMethodSize* names, as the coefficient the header's own DestSize
// formula takes. MPSNeuralNetworkTypes.h:397-401 gives `sourceSize += style * (filterWindowSize - 1)`
// with StyleValidOnly = -1, StyleSame = 0 and StyleFull = 1, and MPSNeuralNetworkTypes.h:339-341 puts the
// three policies in bits 4 and 5 as 0, 1<<4 and 2<<4. The coefficient is therefore the BITS MINUS ONE,
// and that subtraction is the whole of the translation: without it a ValidOnly window reads one wider
// than the source and a Full one reads three narrower.
//
// MEASURED, and by the header's own code rather than by a restatement of it: the host case extracts the C
// block from MPSNeuralNetworkTypes.h, compiles and runs it, and compares its DestSize and Offset with the
// two functions below over every shape from 1 to 32 sources, strides 1-4 and windows 1-5, in all three
// policies. This line was `bits` rather than `bits - 1` and every ValidOnly and Full shape disagreed.
static inline long CharonMPSNNDestSize(long sourceSize, long stride, long filterWindowSize, MPSNNPaddingMethod method)
{
    long style = (long)((method >> 4) & 0x3) - 1;
    long size = sourceSize + style * (filterWindowSize - 1);
    return (size + stride - 1) / stride;   // "sourceSize / stride, round up" - the header's own words
}

static inline long CharonMPSNNReadSize(long destinationSize, long stride, long filterWindowSize)
{
    return (destinationSize - 1) * stride + filterWindowSize;
}

// The offset in one dimension, MPSNeuralNetworkTypes.h:411-431 verbatim in structure: the correction
// from the window's left edge to its centre, the destination size that correction is measured against,
// the extent a walk must read to fill that destination, how much of that extent the source does not
// have, and how much of the shortfall lands on the left. The header's own centeringPolicy is 0 - "When
// kernelSize is even: 0 pad bottom right. 1 pad top left" (:388) - which is the plain division by two
// below with no rounding correction.
static inline long CharonMPSNNOffset(long sourceSize, long stride, long filterWindowSize, MPSNNPaddingMethod method)
{
    long correction = filterWindowSize / 2;
    long destinationSize = CharonMPSNNDestSize(sourceSize, stride, filterWindowSize, method);
    long readSize = CharonMPSNNReadSize(destinationSize, stride, filterWindowSize);
    long extraSize = readSize - sourceSize;
    long leftExtraPixels = (extraSize + 0) / 2;   // centeringPolicy 0: the leftover goes bottom/right
    return correction - leftExtraPixels;
}

// The node every filter's result image names, so that a walk going backwards from a result image can ask
// "which filter produced this?" without having the list of filters in hand. That question is the whole
// of the walk - MPSNNGraph.h:64-68 - and a graph is built from nodes the caller made BEFORE the graph
// exists, so the answer cannot come from the graph: the release keeps the same pairing in its own node
// table, and this is that table.
//
// This was the second defect the differential caught. The walk first searched the list of filters it was
// building for one whose .resultImage was the node being visited - which finds nothing, because the
// filter that produced that node is by definition not in the list yet. Every node then read as a graph
// input, the graph reported no filters at all, and -encodeToCommandBuffer: answered an image nothing had
// written: all zeros, over the right shape. The pairing is registered where the result node is made, so
// the walk asks the table rather than the list it is filling.
static NSMapTable *CharonMPSNNProducers(void)
{
    static NSMapTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSMapTable strongToStrongObjectsMapTable];
    });
    return table;
}


@implementation MPSNNImageNode {
    id<MPSHandle> _handle;
    MPSImageFeatureChannelFormat _format;
    id<MPSImageAllocator> _imageAllocator;
    BOOL _exportFromGraph;
    MPSImage *_charonImage;
}

@synthesize handle = _handle;
@synthesize format = _format;
@synthesize imageAllocator = _imageAllocator;
@synthesize exportFromGraph = _exportFromGraph;

- (instancetype)initWithHandle:(id<MPSHandle>)handle
{
    // The header's own defaults, MPSNNGraphNodes.h:174/:182/:205: format None so that MPS picks, the
    // temporary image's allocator, and no export.
    if ((self = [super init])) {
        _handle = handle;
        _format = MPSImageFeatureChannelFormatNone;
        _imageAllocator = nil;
        _exportFromGraph = NO;
    }
    return self;
}

+ (instancetype)nodeWithHandle:(id<MPSHandle>)handle
{
    return [[self alloc] initWithHandle:handle];
}

+ (instancetype)exportedNodeWithHandle:(id<MPSHandle>)handle
{
    MPSNNImageNode *node = [[self alloc] initWithHandle:handle];
    node.exportFromGraph = YES;
    return node;
}

- (MPSImage *)charon_mps_image { return _charonImage; }
- (void)charon_mps_setImage:(MPSImage *)image { _charonImage = image; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p handle=%@ channels=%lu>", NSStringFromClass([self class]), (void *)self,
            _handle, (unsigned long)_charonImage.featureChannels];
}

@end


@implementation MPSImage (CharonMPSNN)

// An MPSImage's own shape, as a descriptor: the four properties MPSImage.h:402-417 declares, and the
// channel format the image already answers as its own featureChannelFormat (MPSImage.h:452).
//
// The format is read from that property rather than derived from the pixel formats, and an earlier form
// of this function switched over the pixel formats itself. That is a second copy of a table MPSImage
// already holds, and it was wrong for every image of more than one channel: the pixel format of a
// four-channel float image is RGBA32Float, which that switch did not name, so the descriptor came back
// with MPSImageFeatureChannelFormatNone, the destination image was allocated with no element size, and
// the concatenation case refused with "the destination's channel format names no element size". MPSImage
// is the image's own answer and does not need a second one.
- (MPSImageDescriptor *)charon_mps_descriptor
{
    MPSImageDescriptor *descriptor = [MPSImageDescriptor new];
    descriptor.width = self.width;
    descriptor.height = self.height;
    descriptor.featureChannels = self.featureChannels;
    descriptor.numberOfImages = self.numberOfImages;
    descriptor.channelFormat = self.featureChannelFormat;
    // MPSImage carries no cache mode, storage mode or usage of its own in this surface (MPSImage.h:402-452
    // names width, height, featureChannels, numberOfImages, textureType, pixelFormat, precision, usage and
    // featureChannelFormat), so the descriptor keeps the defaults its own class sets rather than a second
    // guess at what the image is.
    return descriptor;
}

@end


@implementation MPSNNStateNode {
    id<MPSHandle> _handle;
    BOOL _exportFromGraph;
    MPSState *_charonState;
}

@synthesize handle = _handle;
@synthesize exportFromGraph = _exportFromGraph;

- (MPSState *)charon_mps_state { return _charonState; }
- (void)charon_mps_setState:(MPSState *)state { _charonState = state; }

@end


// WHAT THE -Wincomplete-implementation WARNING IS TURNED OFF FOR, and it is one list and one reason.
//
// MPSNNFilterNode's @interface in MPSNNGraphNodes.h:338-486 declares five methods this object does not
// implement, and every one of them is the training half of the graph:
//
//   -gradientFilterWithSource:                                  :404   returns MPSNNGradientFilterNode*
//   -gradientFilterWithSources:                                 :412   returns MPSNNGradientFilterNode*
//   -gradientFiltersWithSources:                                :420   returns MPSNNGradientFilterNode*
//   -gradientFiltersWithSource:                                 :428   returns MPSNNGradientFilterNode*
//   -trainingGraphWithSourceGradient:nodeHandler:               :466   MPS_AVAILABLE_STARTING ios(12.0)
//
// MPSNNGradientFilterNode is 12.0 by the same first-rung.py run printed at the top of this file, so
// implementing any of the five would put a 12.0 name in an 11.0 object - which `misplaced()` in
// backports.lua refuses by raising, and which tools/release-split.lua cannot see at all because it reads
// band points and not a file's declared release. They belong to the object that carries the gradient
// half; the registry rows for MPSNNGradientFilterNode and its 11.3 slice say so in their own words.
//
// The suppression is push/pop around this one @implementation and names its five methods in the comment
// above, rather than a file-wide `#pragma clang diagnostic ignored` with no record of what it hides. The
// alternative that needs no pragma at all - defining the five anyway - is the mixed release the check
// exists to refuse, and the other alternative, a second and third object for the 11.3, 12.0 and 12.1
// halves, is a piece of work of its own: thirteen methods across three later releases, each with its own
// placement to measure and its own rows.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// MPSNNFilterNode's -init is NS_UNAVAILABLE in the header, so the release refuses to build one by name.
// Nothing below calls it: every real node here reaches NSObject's own -init, which does not re-enter it.
@implementation MPSNNFilterNode {
    MPSNNImageNode *_resultImageNode;
    NSMutableArray<MPSNNStateNode *> *_resultStates;
    NSMutableArray<MPSNNImageNode *> *_sourceNodes;
    NSMutableArray<MPSImage *> *_sourceImages;
    id<MPSNNPadding> _paddingPolicy;
    NSString *_label;
    MPSImage *_destinationImage;
    id<MTLDevice> _device;
}

@synthesize paddingPolicy = _paddingPolicy;
@synthesize label = _label;

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    // This package's own way into a node. -init is unavailable in the header, so this is what a node of
    // this package is built with, and every subclass in this file reaches it with [super initWithDevice:].
    if ((self = [super init])) {
        _sourceNodes = [NSMutableArray array];
        _sourceImages = [NSMutableArray array];
        _resultStates = [NSMutableArray array];
        _device = device;
    }
    return self;
}

- (MPSNNImageNode *)resultImage
{
    if (!_resultImageNode) {
        // A filter always has exactly one result image position. The header says it is readonly and
        // nonnull (:350), so it is made on first use rather than in an initialiser a caller might not
        // reach - a node built with a result image already made keeps that one, which is what lets a
        // caller wire a graph by hand. The pairing a walk reads is registered here, where the node is
        // made, because the graph does not exist yet: a caller wires the filters first and builds the
        // graph from the last node.
        _resultImageNode = [[MPSNNImageNode alloc] initWithHandle:nil];
        [CharonMPSNNProducers() setObject:self forKey:_resultImageNode];
    }
    return _resultImageNode;
}

- (NSArray<MPSNNStateNode *> *)resultStates { return _resultStates; }

- (MPSNNStateNode *)resultState
{
    // "convenience method for resultStates[0]" (MPSNNGraphNodes.h:352), and nil when there are none.
    return _resultStates.count ? _resultStates[0] : nil;
}

- (NSArray<MPSNNImageNode *> *)charon_mps_sourceNodes { return _sourceNodes; }

- (void)charon_mps_setSourceNodes:(NSArray<MPSNNImageNode *> *)nodes
{
    [_sourceNodes removeAllObjects];
    [_sourceNodes addObjectsFromArray:nodes];
}

- (void)charon_mps_addSourceNode:(MPSNNImageNode *)node
{
    if (node)
        [_sourceNodes addObject:node];
}

- (MPSKernel *)charon_mps_kernel { return nil; }

- (MPSImage *)charon_mps_sourceImageAtIndex:(NSUInteger)index
{
    return index < _sourceImages.count ? _sourceImages[index] : nil;
}

- (void)charon_mps_setSourceImages:(NSArray<MPSImage *> *)images
{
    [_sourceImages removeAllObjects];
    [_sourceImages addObjectsFromArray:images];
}

- (MPSImage *)charon_mps_destinationImage { return _destinationImage; }
- (void)charon_mps_setDestinationImage:(MPSImage *)image { _destinationImage = image; }
- (void)charon_mps_setDevice:(id<MTLDevice>)device { _device = device; }
- (id<MTLDevice>)charon_mps_device { return _device; }

// The shape of the result, from the shape of the source. What a padding policy decides, in the header's
// own words: "It principally is responsible for setting the MPSCNNKernel.offset and the size of the
// image produced" (MPSNNGraphNodes.h:361-363). A node with no padding policy keeps its source's shape,
// which is what an elementwise node does - MPSNNArithmetic is a per-pixel operation and its header
// (MPSImageMath.h:34-37) names no spatial term at all.
//
// THE POLICY IS HANDED THE NODE'S OWN IMAGES, not the node. MPSNeuralNetworkTypes.h:449 names the first
// parameter "The list of source images to be used", and an earlier form of this method passed
// `@[ (MPSImage *)self ]` - the NODE - so the policy asked its first argument for its shape and sent
// -charon_mps_descriptor to an MPSNNFilterNode. Nothing caught it, because every case until the one that
// set a paddingPolicy left this branch untaken. It is measured, not reasoned: the host case
// tests/backports/host/mpsnn sets MPSNNPaddingMethodSizeSame on a pooling node and the port build died of
// "-[CharonMPSCNNPoolingAverageNode charon_mps_descriptor]: unrecognized selector sent to instance".
- (MPSImageDescriptor *)charon_mps_destinationDescriptorForSource:(MPSImageDescriptor *)source
{
    if (_paddingPolicy && [_paddingPolicy respondsToSelector:@selector(destinationImageDescriptorForSourceImages:sourceStates:forKernel:suggestedDescriptor:)]) {
        NSMutableArray<MPSImage *> *images = [NSMutableArray array];
        for (NSUInteger index = 0; index < self.charon_mps_sourceNodes.count; index++) {
            MPSImage *image = [self charon_mps_sourceImageAtIndex:index];
            if (image)
                [images addObject:image];
        }
        return [_paddingPolicy destinationImageDescriptorForSourceImages:images
                                                           sourceStates:nil
                                                              forKernel:[self charon_mps_kernel]
                                                   suggestedDescriptor:source];
    }
    return source;
}

// One node's share of a graph encode. The base class carries no kernel, so it refuses once, in the log,
// and the walk carries on to the next node: the release asserts on a graph with an abstract node in it,
// and an API in this port never crashes its caller.
- (void)charon_mps_encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    CharonMPSRefuse(@"%@: a virtual base node carries no kernel, so it was not run", NSStringFromClass([self class]));
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %p sources=%lu>", NSStringFromClass([self class]), (void *)self,
            (unsigned long)_sourceNodes.count];
}

@end

#pragma clang diagnostic pop


// MPSNNPadding's required method is -paddingMethod and the sizing method is optional
// (MPSNeuralNetworkTypes.h:369-455); MPSNNDefaultPadding carries both, and it carries the coding pair
// because the protocol's own base list is <NSObject, NSSecureCoding> (MPSNeuralNetworkTypes.h:363) and a
// conformance without -initWithCoder: and -encodeWithCoder: is a claim the runtime cannot keep.
//
// The header's class declares four methods and this implements the two 11.0 ones,
// `+paddingWithMethod:` and `-label`, plus the two coding methods MPSNNPadding's own base list requires.
// It does NOT implement `+paddingForTensorflowAveragePooling` or `+paddingForTensorflowAveragePoolingValidOnly`
// (MPSNeuralNetworkTypes.h:497/:500), because both carry MPS_AVAILABLE_STARTING ios(11.3) and an 11.3 name
// here is the mixed release this object exists to avoid. Nor does it implement `-inverse`
// (MPSNeuralNetworkTypes.h:455), which carries the same ios(11.3); the registry row
// `-[MPSNNPadding inverse]` already says introduced 11.3.
//
// Nor does it implement any other `+paddingFor...`: an earlier form of this file carried six, and five of
// them - `+paddingForTensorflowMaxPooling`, `+paddingForTensorflowConvolution`, `+paddingForCaffePooling`,
// `+paddingForCaffeConvolution` and `+paddingForMXNetPadding` - are declared by NO Apple header. Checked
// in both SDKs on this machine, 16.4 and 26.2:
//
//   grep -rn 'paddingForCaffePooling\|paddingForMXNetPadding\|paddingForCaffeConvolution' \
//       .../MetalPerformanceShaders.framework/Frameworks/*/Headers/
//
// answers nothing in either. A public class method that no release ever had is API the port invented, and
// five of them is worse than one.
//
// So the -Wincomplete-implementation this suppresses is exactly two names, both ios(11.3):
//   +paddingForTensorflowAveragePooling            MPSNeuralNetworkTypes.h:497
//   +paddingForTensorflowAveragePoolingValidOnly   MPSNeuralNetworkTypes.h:500
// -inverse at :455 is a third ios(11.3) name and clang does not ask for it because the protocol declares
// it @optional; it is left out for the same reason and the registry row says why.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSNNDefaultPadding {
    MPSNNPaddingMethod _paddingMethod;
    NSString *_label;
}

// -label is declared @optional on MPSNNPadding (MPSNeuralNetworkTypes.h:373) as a METHOD, not as a
// property, so there is no declaration for @synthesize to point at and it is written out here. A policy
// made by +paddingWithMethod: has no name of its own and says so, which is what the release's own
// non-custom policies do: they carry the method and nothing else.
- (NSString *)label { return _label; }

+ (instancetype)paddingWithMethod:(MPSNNPaddingMethod)method
{
    MPSNNDefaultPadding *padding = [[self alloc] init];
    padding->_paddingMethod = method;
    return padding;
}

- (MPSNNPaddingMethod)paddingMethod { return _paddingMethod; }

- (MPSImageDescriptor *)destinationImageDescriptorForSourceImages:(NSArray<MPSImage *> *)sourceImages
                                                     sourceStates:(NSArray<MPSState *> *)sourceStates
                                                        forKernel:(MPSKernel *)kernel
                                             suggestedDescriptor:(MPSImageDescriptor *)inDescriptor
{
    MPSImage *source = sourceImages.firstObject;
    if (!source)
        return inDescriptor;
    MPSImageDescriptor *sourceDescriptor = [source charon_mps_descriptor];
    if (!sourceDescriptor)
        return inDescriptor;

    // The window and the stride are the kernel's own members, MPSCNNKernel.h:212-219, and a kernel that
    // has none walks a one by one window, which is what the release does for an elementwise node.
    NSUInteger kernelWidth = 1, kernelHeight = 1, strideX = 1, strideY = 1;
    if ([kernel respondsToSelector:@selector(kernelWidth)]) kernelWidth = [(MPSCNNKernel *)kernel kernelWidth];
    if ([kernel respondsToSelector:@selector(kernelHeight)]) kernelHeight = [(MPSCNNKernel *)kernel kernelHeight];
    if ([kernel respondsToSelector:@selector(strideInPixelsX)]) strideX = [(MPSCNNKernel *)kernel strideInPixelsX];
    if ([kernel respondsToSelector:@selector(strideInPixelsY)]) strideY = [(MPSCNNKernel *)kernel strideInPixelsY];
    if (!kernelWidth) kernelWidth = 1;
    if (!kernelHeight) kernelHeight = 1;
    if (!strideX) strideX = 1;
    if (!strideY) strideY = 1;

    MPSNNPaddingMethod method = _paddingMethod;
    long destinationWidth = CharonMPSNNDestSize((long)sourceDescriptor.width, (long)strideX, (long)kernelWidth, method);
    long destinationHeight = CharonMPSNNDestSize((long)sourceDescriptor.height, (long)strideY, (long)kernelHeight, method);
    if (destinationWidth < 1) destinationWidth = 1;
    if (destinationHeight < 1) destinationHeight = 1;

    // The kernel's offset, which is the other half of what a padding policy decides and the half a
    // caller reads back as the kernel's own -offset property.
    if ([kernel respondsToSelector:@selector(setOffset:)]) {
        MPSOffset offset;
        offset.x = (NSInteger)CharonMPSNNOffset((long)sourceDescriptor.width, (long)strideX, (long)kernelWidth, method);
        offset.y = (NSInteger)CharonMPSNNOffset((long)sourceDescriptor.height, (long)strideY, (long)kernelHeight, method);
        offset.z = 0;
        [(MPSCNNKernel *)kernel setOffset:offset];
    }

    // Built field by field rather than with -[MPSImageDescriptor copy]. Measured: that method as
    // MPSImage13.m writes it is `[[[MPSImageDescriptor allocWithZone:] init] copy]`, which calls itself
    // and dies of stack exhaustion - it is reachable from any caller of -copy on a descriptor and this
    // file is not where that defect is fixed (MPSImage13.m carries the 13.0 API, another object's).
    // So the descriptor is written here, from the source's own fields, and both this and the
    // concatenation below stop depending on a method that does not answer.
    MPSImageDescriptor *destination = [MPSImageDescriptor new];
    destination.channelFormat = sourceDescriptor.channelFormat;
    destination.cpuCacheMode = sourceDescriptor.cpuCacheMode;
    destination.storageMode = sourceDescriptor.storageMode;
    destination.usage = sourceDescriptor.usage;
    destination.featureChannels = sourceDescriptor.featureChannels;
    destination.numberOfImages = sourceDescriptor.numberOfImages;
    destination.width = (NSUInteger)destinationWidth;
    destination.height = (NSUInteger)destinationHeight;
    return destination;
}

// NSSecureCoding, which MPSNNPadding's own base list names (MPSNeuralNetworkTypes.h:363). The key is this
// port's, exactly as MPSKernel9.m's `label` key is: the release's own archive keys for a padding policy
// are in no header, and an invented key means an archive this port can read and the release cannot, which
// is the tradeoff MPSKernel9.m:78-82 records and takes for the label. What is round-tripped is the one
// value that makes a policy a policy: the method whose bits the arithmetic above selects.
+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super init])) {
        NSNumber *method = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:@"paddingMethod"];
        _paddingMethod = method ? (MPSNNPaddingMethod)[method unsignedLongValue] : MPSNNPaddingMethodSizeValidOnly;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:@(_paddingMethod) forKey:@"paddingMethod"];
    if (_label)
        [aCoder encodeObject:_label forKey:@"label"];
}

@end

#pragma clang diagnostic pop


// The arithmetic nodes. Each stands for one of the four MPSImageArithmetic operations this package
// already carries (MPSImageArithmetic13.m), over the same two images and into the same destination, so
// the graph runs them through that kernel rather than repeating the operation here.
//
// Two methods of MPSNNBinaryArithmeticNode's own @interface (MPSNNGraphNodes.h:2136-2216) are not
// implemented here, and both are the training half: `-gradientClass` at :2158 and
// `-gradientFiltersWithSources:` at :2162, which carries MPS_AVAILABLE_STARTING ios(11.3) and returns
// MPSNNGradientFilterNode*. So is the pair on the class above. The list and the reason are the one beside
// MPSNNFilterNode's.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSNNBinaryArithmeticNode {
    MPSKernel *_kernel;
    float _primaryScale, _secondaryScale, _bias, _minimumValue, _maximumValue;
    NSUInteger _primaryStrideInPixelsX, _primaryStrideInPixelsY, _primaryStrideInFeatureChannels;
    NSUInteger _secondaryStrideInPixelsX, _secondaryStrideInPixelsY, _secondaryStrideInFeatureChannels;
}

@synthesize primaryScale = _primaryScale;
@synthesize secondaryScale = _secondaryScale;
@synthesize bias = _bias;
@synthesize minimumValue = _minimumValue;
@synthesize maximumValue = _maximumValue;
@synthesize primaryStrideInPixelsX = _primaryStrideInPixelsX;
@synthesize primaryStrideInPixelsY = _primaryStrideInPixelsY;
@synthesize primaryStrideInFeatureChannels = _primaryStrideInFeatureChannels;
@synthesize secondaryStrideInPixelsX = _secondaryStrideInPixelsX;
@synthesize secondaryStrideInPixelsY = _secondaryStrideInPixelsY;
@synthesize secondaryStrideInFeatureChannels = _secondaryStrideInFeatureChannels;

// The one line the four subclasses differ by, the same shape MPSImageArithmetic13.m uses for its own
// four: a class-level constant naming the operation, and one kernel object holding it.
+ (Class)charon_mps_kernelClass { return [MPSImageAdd class]; }

- (instancetype)initWithLeftSource:(MPSNNImageNode *)left rightSource:(MPSNNImageNode *)right
{
    if ((self = [super initWithDevice:nil])) {
        // THE HEADER'S DEFAULTS, and the third thing the differential caught. MPSImageMath.h:31-32: "The
        // default value for primaryScale and secondaryScale is 1.0f. The default value for bias is
        // 0.0f." MPSImageMath.h:34-37 applies all three: "result = ((primaryScale * x) + (secondaryScale
        // * y)) + bias". An Objective-C float ivar is zero, and a zero scale answers zero however
        // correct the kernel underneath is - which is what this node did until the differential compared
        // it with the same addition run without a graph and got 11 22 33 44 against 0 0 0 0.
        _primaryScale = 1.0f;
        _secondaryScale = 1.0f;
        _bias = 0.0f;
        _minimumValue = -FLT_MAX;
        _maximumValue = FLT_MAX;
        [self charon_mps_addSourceNode:left];
        [self charon_mps_addSourceNode:right];
    }
    return self;
}

+ (instancetype)nodeWithLeftSource:(MPSNNImageNode *)left rightSource:(MPSNNImageNode *)right
{
    return [[self alloc] initWithLeftSource:left rightSource:right];
}

// MPSNNGraphNodes.h:2150, the 11.0 initialiser of the class. "A valid NSArray containing two sources"
// (:2139) is what +nodeWithSources: below refuses against, and this is the same rule one level down: an
// arithmetic node with one operand has no meaning, and an API in this port says so in the log instead of
// answering with a guess. An earlier form of this file had only the +method and left the -initializer
// declared and undefined, so a caller who had the initializer and not the convenience method got an
// unrecognized selector.
- (instancetype)initWithSources:(NSArray<MPSNNImageNode *> *)sourceNodes
{
    if (sourceNodes.count != 2) {
        CharonMPSRefuse(@"%@: an arithmetic node needs exactly two sources and was given %lu, so none was made",
                        NSStringFromClass([self class]), (unsigned long)sourceNodes.count);
        return nil;
    }
    return [self initWithLeftSource:sourceNodes[0] rightSource:sourceNodes[1]];
}

+ (instancetype)nodeWithSources:(NSArray<MPSNNImageNode *> *)sourceNodes
{
    return [[self alloc] initWithSources:sourceNodes];
}

// The kernel, made once and kept, so that two runs of one graph share it and the node carries no second
// copy of the arithmetic. It is made against the node's own device, which the graph sets before the
// first encode; a node asked for its kernel before the graph has run gets one against the system default
// device, which is the one device this port has.
//
// NOT MPSGetPreferredDevice, and the reason is a band, not a preference: that function is defined in
// MPSCommandBuffer16.m, which is the 16.0 object, and a band that leaves a 16.0 file out of its library
// would leave this call without a definition - the trap AGENTS.md names under "A C function shared
// between backport files". MPSCommandBuffer16.m:9-16 answers MTLCreateSystemDefaultDevice() for every
// combination of MPSDeviceOptions anyway ("This port has one device and no removable or low-power choice
// among several, so the options have nothing to choose between"), so calling it here would be the same
// value by a route one band cannot take.
//
// The initialiser is sent to the CONCRETE class, whose own declaration it is: MPSImageMath.h:112/:132/
// :152/:172 declare -initWithDevice: on MPSImageAdd, MPSImageSubtract, MPSImageMultiply and
// MPSImageDivide, and MPSImageMath.h:92 marks only the BASE unavailable, to say it is never built
// directly. This is the same reach MPSImageArithmetic13.m uses to build its own four.
- (MPSKernel *)charon_mps_kernel
{
    if (!_kernel) {
        id<MTLDevice> device = [self charon_mps_device];
        if (!device)
            device = MTLCreateSystemDefaultDevice();
        _kernel = [[[self class] charon_mps_kernelClass] alloc];
        _kernel = [_kernel initWithDevice:device];
    }
    return _kernel;
}

// The whole class, MPSNNGraphNodes.h:144-145 (addition), :148-149 (difference) and :151-152 (product).
- (void)charon_mps_encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    MPSImage *primary = [self charon_mps_sourceImageAtIndex:0];
    MPSImage *secondary = [self charon_mps_sourceImageAtIndex:1];
    MPSImage *destination = [self charon_mps_destinationImage];
    if (!primary || !secondary || !destination) {
        CharonMPSRefuse(@"%@: an arithmetic node needs two sources and a destination and was not given all three",
                        NSStringFromClass([self class]));
        return;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    // The scales, the strides, the bias and the clamp are the kernel's own members, so they are handed
    // straight across and the operation runs where the rest of this package runs it - one walk, one
    // store, one place the arithmetic lives.
    // The kernel is made HERE, not in the initialiser: a node is built before the graph runs, and the
    // device the kernel is made against is the graph's, which does not exist yet at build time.
    [self charon_mps_kernel];
    MPSImageArithmetic *kernel = (MPSImageArithmetic *)_kernel;
    kernel.primaryScale = self.primaryScale;
    kernel.secondaryScale = self.secondaryScale;
    kernel.bias = self.bias;
    kernel.minimumValue = self.minimumValue;
    kernel.maximumValue = self.maximumValue;
    kernel.primaryStrideInPixels = MTLSizeMake(self.primaryStrideInPixelsX, self.primaryStrideInPixelsY,
                                               self.primaryStrideInFeatureChannels);
    kernel.secondaryStrideInPixels = MTLSizeMake(self.secondaryStrideInPixelsX, self.secondaryStrideInPixelsY,
                                                 self.secondaryStrideInFeatureChannels);
    [kernel encodeToCommandBuffer:commandBuffer
                     primaryImage:primary
                   secondaryImage:secondary
                destinationImage:destination];
    [self.resultImage charon_mps_setImage:destination];
}

@end

#pragma clang diagnostic pop

@implementation MPSNNAdditionNode
+ (Class)charon_mps_kernelClass { return [MPSImageAdd class]; }
@end

@implementation MPSNNSubtractionNode
+ (Class)charon_mps_kernelClass { return [MPSImageSubtract class]; }
@end

@implementation MPSNNMultiplicationNode
+ (Class)charon_mps_kernelClass { return [MPSImageMultiply class]; }
@end

@implementation MPSNNDivisionNode
+ (Class)charon_mps_kernelClass { return [MPSImageDivide class]; }
@end


// The concatenation node. MPSNNGraphNodes.h:2438-2449 states the rule exactly: given images with M, N
// and O feature channels, the result takes [0,M-1] from the first, [M,M+N-1] from the second and so on,
// and every source is padded out to a multiple of four feature channels, so M, N and O are multiples of
// four even when the MPSImages are not.
@implementation MPSNNConcatenationNode {
    MPSKernel *_kernel;
}

+ (instancetype)nodeWithSources:(NSArray<MPSNNImageNode *> *)sourceNodes
{
    return [[self alloc] initWithSources:sourceNodes];
}

- (instancetype)initWithSources:(NSArray<MPSNNImageNode *> *)sourceNodes
{
    if ((self = [super initWithDevice:nil]))
        for (MPSNNImageNode *node in sourceNodes)
            [self charon_mps_addSourceNode:node];
    return self;
}

- (MPSKernel *)charon_mps_kernel { return _kernel; }

- (MPSImageDescriptor *)charon_mps_destinationDescriptorForSource:(MPSImageDescriptor *)source
{
    // Every source contributes its own channels, each padded out to a multiple of four, and the sources
    // share the destination's height and width: a concatenation joins channels, not planes.
    //
    // THE SHAPE IS TAKEN FROM THE SOURCES AND NOT FROM `source`, which is the first finding the
    // concatenation case produced. `source` is the descriptor of whatever the node read FIRST, and a
    // concatenation node reads N images, so the walk's `first` is the first of them and its width and
    // height are the ones every source shares; taking the widest and tallest SOURCE rather than seeding
    // from `source` is what makes the answer independent of which source happened to be bound first.
    // Seeded from `source` it was already right, but only because `source` is that same first image -
    // and when no source was bound at all the seed was a zero descriptor, and the destination came back
    // 0x0 over eight channels with nothing in it. Measured, the case above.
    NSUInteger channels = 0, width = 0, height = 0;
    for (NSUInteger index = 0; index < self.charon_mps_sourceNodes.count; index++) {
        MPSImage *image = [self charon_mps_sourceImageAtIndex:index];
        MPSImageDescriptor *descriptor = [image charon_mps_descriptor];
        if (!descriptor)
            continue;
        channels += (descriptor.featureChannels + 3) & ~(NSUInteger)3;
        if (descriptor.width > width) width = descriptor.width;
        if (descriptor.height > height) height = descriptor.height;
    }
    // No source bound: nothing to join, and the graph says so at the walk rather than this answering
    // with a zero-sized image a caller would read as an empty result.
    if (!channels || !width || !height)
        return nil;

    // Field by field, for the reason given in -destinationImageDescriptorForSourceImages: above.
    MPSImageDescriptor *destination = [MPSImageDescriptor new];
    destination.channelFormat = source.channelFormat;
    destination.cpuCacheMode = source.cpuCacheMode;
    destination.storageMode = source.storageMode;
    destination.usage = source.usage;
    destination.numberOfImages = source.numberOfImages;
    destination.width = width;
    destination.height = height;
    destination.featureChannels = channels;
    return destination;
}

- (void)charon_mps_encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    MPSImage *destination = [self charon_mps_destinationImage];
    if (!destination || !self.charon_mps_sourceNodes.count) {
        CharonMPSRefuse(@"%@: a concatenation node needs at least one source and a destination",
                        NSStringFromClass([self class]));
        return;
    }
    // Each source lands in the destination in its own padded channel block, which is the rule the header
    // states. The block boundaries are what the descriptor above computed, so a source of three channels
    // occupies four and the fourth is padding.
    //
    // WHAT GOES IN THE PADDING IS MEASURED AGAINST THE RELEASE, and the measurement corrected the comment
    // this line used to carry. That comment said writing a value there "would be an answer the release does
    // not give" and left the destination as allocated. The release's own MPSNNConcatenationNode, run on
    // this host over 1x1 float images (tests/backports/host/mpsnn, case concat, and the five widths it
    // sweeps), answers:
    //
    //   1 channel + 1 channel  -> 1x1x8 : 1 0 0 1 5 0 0 1
    //   2 + 2                  -> 1x1x8 : 1 2 0 1 5 6 0 1
    //   4 + 4                  -> 1x1x8 : 1 2 3 4 5 6 7 8
    //   1 + 4                  -> 1x1x8 : 1 0 0 1 5 6 7 8
    //   3 + 1                  -> 1x1x8 : 1 2 3 0 5 0 0 1
    //
    // So the release does write there: zeros, and a 1 in the block's fourth channel for a source of one or
    // two channels - and, by the last row, a zero for a source of three. That is why the rule below is
    // stated as it is and not as "the image is RGBA and the alpha is 1": the three-channel row does not
    // agree with that, and MPSImage13.m holds one, two and four channels and refuses the rest, so this
    // object never sees a three-channel source. MPSNNGraphNodes.h:2443-2446 states the COUNT of the
    // padding and says nothing about its value; this is where the value came from.
    NSString *what = NSStringFromClass([self class]);
    NSUInteger offset = 0;
    for (NSUInteger index = 0; index < self.charon_mps_sourceNodes.count; index++) {
        MPSImage *source = [self charon_mps_sourceImageAtIndex:index];
        if (!source)
            continue;
        // Through the same region read and write every MPSImage kernel in this package uses
        // (CharonMPSImage.h:69-75), so a concatenation is the same walk the other kernels are.
        CharonMPSImageLayout inLayout = CharonMPSImageLayoutOf(source);
        CharonMPSImageLayout outLayout = CharonMPSImageLayoutOf(destination);

        // THE BUFFER IS THE DESTINATION'S SIZE, and that is not a detail: CharonMPSImageReadRegion
        // allocates width * height * sourceChannels elements, and the join writes a row of
        // width * destinationChannels into it at a channel offset. With a source of one channel and a
        // destination of four, the buffer is a quarter of the row the write needs and the join walks off
        // the end of it - measured, as a SIGSEGV inside objc_storeStrong on the case above. So the
        // source is read into a buffer of the destination's own row width, and the source's channels
        // are scattered into it from there.
        size_t rowElements = (size_t)destination.width * outLayout.channels;
        size_t bytes = rowElements * destination.height * outLayout.elementSize;
        if (!bytes || !outLayout.elementSize) {
            CharonMPSRefuse(@"%@: the destination's channel format names no element size, so nothing was joined", what);
            continue;
        }
        unsigned char *row = calloc(bytes, 1);
        if (!row) {
            CharonMPSRefuse(@"%@: no memory for a %lux%lux%lu join, so nothing was joined", what,
                            (unsigned long)destination.width, (unsigned long)destination.height,
                            (unsigned long)outLayout.channels);
            continue;
        }
        // The measured padding, written into the same buffer the join builds so that the destination is
        // written once with the source's channels and the block's padding together. It is in the one place
        // that knows the block's offset: the release's MPSNNConcatenationNode answers zeros there and a 1
        // in the block's fourth channel for a source of one or two channels - and, by the three-channel row
        // above, a zero for a source of three, which is why this is stated per source and not as "the image
        // is RGBA". outLayout.channels is the destination's own, so the value is placed at the block's
        // index through it and the row is the destination's width, not the source's.
        MPSImageDescriptor *descriptor = [source charon_mps_descriptor];
        NSUInteger channels = descriptor ? descriptor.featureChannels : 0;
        if (channels && channels < 4) {
            for (NSUInteger y = 0; y < destination.height; y++)
                for (NSUInteger x = 0; x < destination.width; x++) {
                    char *cell = (char *)row + ((size_t)y * rowElements + (size_t)x * outLayout.channels
                                                + offset + 3) * outLayout.elementSize;
                    memset(cell, 0, outLayout.elementSize);
                    if (outLayout.elementSize == sizeof(float))
                        *(float *)cell = 1.0f;
                }
        }
        void *sourceBytes = CharonMPSImageReadRegion(source, &inLayout, CharonMPSImageResolvedRegion(source, MPSRectNoClip), what);
        if (sourceBytes) {
            if (CharonMPSImageConcatRows(&inLayout, &outLayout, offset, sourceBytes, row))
                CharonMPSImageWriteRegion(destination, &outLayout, CharonMPSImageResolvedRegion(destination, MPSRectNoClip), row, what);
            else
                CharonMPSRefuse(@"%@: source %lu holds %lux%lux%lu and the destination %lux%lux%lu, so it was not joined",
                                what, (unsigned long)index,
                                (unsigned long)inLayout.width, (unsigned long)inLayout.height, (unsigned long)inLayout.channels,
                                (unsigned long)outLayout.width, (unsigned long)outLayout.height, (unsigned long)outLayout.channels);
            free(sourceBytes);
        }
        free(row);
        offset += (channels + 3) & ~(NSUInteger)3;
    }
    [self.resultImage charon_mps_setImage:destination];
}

@end


// The pooling nodes. Same shape as the arithmetic nodes above and for the same reason: each stands for a
// kernel this package already carries (MPSCNNPooling10.m), so the graph runs the kernel and the node
// carries the window the kernel walks. MPSCNNPooling.h's divisor is the window's AREA whatever of it
// lies outside the image, and facts/MetalPerformanceShaders/Cnn.md carries the measured table for that
// over a 3x3 source and a 2x2 window; this object does not restate that arithmetic, it hands the window
// to the kernel that has it.
//
// The node's own shape is what the header says it is: MPSCNNGraphNodes.h:1467-1471 calls
// MPSCNNPoolingNode an abstract base that "does not correspond with any particular MPSCNNKernel. Please
// make one of the MPSCNNPooling subclasses instead", and the two below are the 11.0 ones of those three
// subclasses (:1534 and :1546; the third, :1540 MPSCNNPoolingL2NormNode, carries MPS_AVAILABLE_STARTING
// ios(12.0) and belongs to another object's row). The kernelWidth/kernelHeight/strideInPixelsX/
// strideInPixelsY accessors the base declares at :1472-1475 are ios(12.0) as well and are NOT here -
// release-split reads band points, and a 12.0 name in an 11.0 object is the mistake that tool exists to
// find.
@implementation MPSCNNPoolingNode {
    // Typed as the CONCRETE class rather than MPSKernel, because the initialiser this node sends is
    // declared on MPSCNNPoolingAverage (:488) and MPSCNNPoolingMax (:758) and marked unavailable only on
    // the MPSCNNPooling base (:71). Naming the base here would name the unavailable one.
    MPSCNNPooling *_kernel;
    NSUInteger _kernelWidth, _kernelHeight, _strideX, _strideY;
}

+ (Class)charon_mps_kernelClass { return nil; }

- (instancetype)initWithSource:(MPSNNImageNode *)sourceNode
                  kernelWidth:(NSUInteger)kernelWidth
                 kernelHeight:(NSUInteger)kernelHeight
              strideInPixelsX:(NSUInteger)strideX
              strideInPixelsY:(NSUInteger)strideY
{
    if ((self = [super initWithDevice:nil])) {
        _kernelWidth = kernelWidth ? kernelWidth : 1;
        _kernelHeight = kernelHeight ? kernelHeight : 1;
        _strideX = strideX ? strideX : 1;
        _strideY = strideY ? strideY : 1;
        [self charon_mps_addSourceNode:sourceNode];
    }
    return self;
}

- (instancetype)initWithSource:(MPSNNImageNode *)sourceNode filterSize:(NSUInteger)size
{
    return [self initWithSource:sourceNode kernelWidth:size kernelHeight:size strideInPixelsX:size strideInPixelsY:size];
}

- (instancetype)initWithSource:(MPSNNImageNode *)sourceNode filterSize:(NSUInteger)size stride:(NSUInteger)stride
{
    return [self initWithSource:sourceNode kernelWidth:size kernelHeight:size strideInPixelsX:stride strideInPixelsY:stride];
}

+ (instancetype)nodeWithSource:(MPSNNImageNode *)sourceNode filterSize:(NSUInteger)size
{
    return [[self alloc] initWithSource:sourceNode filterSize:size];
}

+ (instancetype)nodeWithSource:(MPSNNImageNode *)sourceNode filterSize:(NSUInteger)size stride:(NSUInteger)stride
{
    return [[self alloc] initWithSource:sourceNode filterSize:size stride:stride];
}

- (MPSKernel *)charon_mps_kernel
{
    if (!_kernel) {
        Class kernelClass = [[self class] charon_mps_kernelClass];
        // The abstract base names no kernel, so a caller who built one gets the refusal and no image
        // rather than a window over nothing. MPSCNNPooling's own -initWithDevice: is unavailable for the
        // same reason the header gives at MPSCNNPooling.h: the base is not built directly.
        if (!kernelClass)
            return nil;
        id<MTLDevice> device = [self charon_mps_device];
        if (!device)
            device = MTLCreateSystemDefaultDevice();
        // The initialiser is sent to the CONCRETE class, whose own declaration it is:
        // MPSCNNPooling.h:488 declares it on MPSCNNPoolingAverage and :758 on MPSCNNPoolingMax as their
        // NS_DESIGNATED_INITIALIZER, and only the BASE at :71 marks it unavailable, to say the base is
        // never built directly. This is the same reach MPSImageArithmetic13.m and MPSImageWalk13.m use.
        _kernel = [kernelClass alloc];
        _kernel = [_kernel initWithDevice:device
                              kernelWidth:_kernelWidth
                             kernelHeight:_kernelHeight
                            strideInPixelsX:_strideX
                            strideInPixelsY:_strideY];
    }
    return _kernel;
}

- (void)charon_mps_encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    MPSImage *source = [self charon_mps_sourceImageAtIndex:0];
    MPSImage *destination = [self charon_mps_destinationImage];
    if (!source || !destination) {
        CharonMPSRefuse(@"%@: a pooling node needs a source and a destination and was not given both",
                        NSStringFromClass([self class]));
        return;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    MPSCNNPooling *kernel = (MPSCNNPooling *)[self charon_mps_kernel];
    if (!kernel) {
        CharonMPSRefuse(@"%@: no pooling kernel to run, so it was not run", NSStringFromClass([self class]));
        return;
    }
    // The window arithmetic is the kernel's own - MPSCNNPooling.h and the measured table in Cnn.md - so
    // the node passes its two images through and does not repeat a divisor here.
    [kernel encodeToCommandBuffer:commandBuffer sourceImage:source destinationImage:destination];
    [self.resultImage charon_mps_setImage:destination];
}

@end

@implementation MPSCNNPoolingAverageNode
+ (Class)charon_mps_kernelClass { return [MPSCNNPoolingAverage class]; }
@end

@implementation MPSCNNPoolingMaxNode
+ (Class)charon_mps_kernelClass { return [MPSCNNPoolingMax class]; }
@end


// The graph itself. MPSNNGraph walks backwards from the result node to find the nodes it needs, in the
// order the filters depend on each other, and -encodeToCommandBuffer: then walks them forwards.
//
// EIGHT METHODS OF ITS OWN @interface ARE NOT IMPLEMENTED HERE, and every one's date is in the list at
// the top of this file:
//   -readCountForSourceImageAtIndex:                        MPSNNGraph.h:363  ios(12.1)
//   -readCountForSourceStateAtIndex:                        MPSNNGraph.h:375  ios(12.1)
//   -initWithDevice:resultImages:resultsAreNeeded:          MPSNNGraph.h:98   ios(13.0)
//   +graphWithDevice:resultImages:resultsAreNeeded:         MPSNNGraph.h:103  ios(13.0)
//   -encodeBatchToCommandBuffer:sourceImages:sourceStates:intermediateImages:destinationStates:
//                                                          MPSNNGraph.h:264  ios(11.3)
//   -encodeBatchToCommandBuffer:sourceImages:sourceStates:  MPSNNGraph.h:299  no date of its own, and
//       its two arguments are NSArray<MPSImageBatch*>* and NSArray<MPSStateBatch*>*; MPSImageBatch and
//       MPSStateBatch are not in this object's surface and MPSImage's row records that they are not
//       carried at all.
//   -initWithDevice:resultImage:                             MPSNNGraph.h:112  ios(11.0, 11.3) DEPRECATED
//   +graphWithDevice:resultImage:                            MPSNNGraph.h:119  ios(11.0, 11.3) DEPRECATED
// The last two are the pre-11.3 spellings of the two initializers this object does implement, and
// MPSNNGraph.h:113 says to use those instead - "Without this information, too much or too little work may
// occur. Results may be undefined." - which is why the object implements the 11.3 spelling and not these.
//
// `-initWithCoder:device:` (MPSNNGraph.h:128, marked NS_DESIGNATED_INITIALIZER) is NOT overridden here.
// MPSKernel9.m:85 already implements it for every kernel in this package, and it is the right
// implementation for a graph: a graph decoded from an archive has no result node, so its -walkFrom: has
// nothing to start from and its -encodeToCommandBuffer: refuses with that one line rather than answering
// with an image nothing produced. An earlier form of this file overrode it to call the designated
// initializer with a nil result image, which is what -Wobjc-designated-initializers and -Wnonnull both
// objected to, and the override did nothing the inherited one does not.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSNNGraph {
    NSMutableArray<MPSNNFilterNode *> *_filters;
    NSMutableArray<MPSNNImageNode *> *_sources;
    NSMutableArray<MPSNNImageNode *> *_order;
    BOOL _outputStateIsTemporary;
    id<MPSImageAllocator> _destinationImageAllocator;
    MPSImageFeatureChannelFormat _format;
    BOOL _resultImageIsNeeded;
    BOOL _walked;
}

// The walk, MPSNNGraph.h:64-71: "The MPSNNGraph constructor will start with the indicated result image,
// and look to see what MPSNNFilterNode produced it, then look to its dependencies and so forth to
// reveal the subsection of the graph necessary to compute the image." Nodes not on the way back to a
// source are left out, which is MPSNNGraph.h:60-61: "Nodes which are not needed to calculate the result
// image node are ignored."
- (void)charon_mps_walkFrom:(MPSNNImageNode *)result
{
    [_filters removeAllObjects];
    [_sources removeAllObjects];
    [_order removeAllObjects];
    [self charon_mps_visit:result seen:[NSMutableSet set]];
    _walked = YES;
}

- (void)charon_mps_visit:(MPSNNImageNode *)node seen:(NSMutableSet *)seen
{
    // A node with no producing filter is a graph INPUT, which is what MPSNNGraphNodes.h:161-163 says the
    // caller's own image nodes are. It becomes a source in the order the walk first meets it, and that is
    // the order MPSNNGraph.sourceImageHandles reports and the order -encodeToCommandBuffer: expects the
    // caller's images in.
    if (!node || [seen containsObject:node])
        return;
    [seen addObject:node];
    // Which filter produced this node - the table, not the list being built, because the filter that
    // produced the node being visited is by definition not in that list yet.
    MPSNNFilterNode *producer = [CharonMPSNNProducers() objectForKey:node];
    if (!producer) {
        [_sources addObject:node];
        return;
    }
    // The dependencies first, so a filter is encoded after everything it reads. The visited set is what
    // makes a graph with a cycle terminate rather than recurse forever: MPSNNGraph.h:70-71 says the
    // result node may be interior to the graph, and a caller who wires one into a loop has built a graph
    // the release does not define, which this port refuses to walk rather than running forever.
    for (MPSNNImageNode *source in producer.charon_mps_sourceNodes)
        [self charon_mps_visit:source seen:seen];
    [_order addObject:node];
    [_filters addObject:producer];
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 resultImage:(MPSNNImageNode *)resultImage
         resultImageIsNeeded:(BOOL)resultIsNeeded
{
    if ((self = [super initWithDevice:device])) {
        _filters = [NSMutableArray array];
        _sources = [NSMutableArray array];
        _order = [NSMutableArray array];
        // MPSNNGraph.h:196: "Default: MPSImageFeatureChannelFormatFloat16", and :189 "Default: NO".
        _format = MPSImageFeatureChannelFormatFloat16;
        _outputStateIsTemporary = NO;
        _destinationImageAllocator = nil;
        _resultImageIsNeeded = resultIsNeeded;
        if (resultImage)
            [self charon_mps_walkFrom:resultImage];
    }
    return self;
}

+ (instancetype)graphWithDevice:(id<MTLDevice>)device
                    resultImage:(MPSNNImageNode *)resultImage
            resultImageIsNeeded:(BOOL)resultIsNeeded
{
    return [[self alloc] initWithDevice:device resultImage:resultImage resultImageIsNeeded:resultIsNeeded];
}

// MPSNNGraph.h:128 marks this NS_DESIGNATED_INITIALIZER of this class, and MPSKernel's own designated
// pair is -initWithDevice: (:117) and -initWithCoder:device: (:163), so -Wobjc-designated-initializers
// asks for it here and is right to. It reaches MPSKernel's, which decodes the label and sets the device,
// and it adds nothing of its own because there is nothing of its own to add: an archive written by
// MPSKernel9.m:97 carries a label and nothing else, and the release's own keys for a graph's nodes are in
// no header. So a graph decoded from an archive is a graph with no result node, its -walkFrom: has
// nothing to start from, and its -encodeToCommandBuffer: refuses in one line rather than answering with
// an image nothing produced. That is the whole of what this initializer says, and the comment at
// MPSNNGraph.h:120-127 says the same thing in the release's words: "since the file can't know which
// device your data is allocated on, we have to guess and may guess incorrectly."
- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (NSArray<id<MPSHandle>> *)sourceImageHandles
{
    NSMutableArray *handles = [NSMutableArray array];
    for (MPSNNImageNode *node in _sources) {
        id<MPSHandle> handle = node.handle;
        if (handle)
            [handles addObject:handle];
    }
    return handles;
}

// A graph of MPSNNFilterNodes over MPSImages produces no states of its own: MPSNNGraph.h:183-184 says the
// source states are the MPSState objects the caller passes in, and this port's nodes run kernels that
// take images, so there is nothing to report and nil is the honest answer rather than an empty array a
// caller would count.
- (NSArray<id<MPSHandle>> *)sourceStateHandles { return nil; }
- (NSArray<id<MPSHandle>> *)intermediateImageHandles { return nil; }
- (NSArray<id<MPSHandle>> *)resultStateHandles { return nil; }
- (id<MPSHandle>)resultHandle { return _order.lastObject.handle; }

@synthesize outputStateIsTemporary = _outputStateIsTemporary;
@synthesize destinationImageAllocator = _destinationImageAllocator;
@synthesize format = _format;
@synthesize resultImageIsNeeded = _resultImageIsNeeded;

// Every node with a data source is told to read it again, MPSNNGraph.h:213-217. A node with no data
// source does not answer the selector and is left as it is, which is what the header says at :217:
// "Most nodes do not have a data source and will not be modified."
- (void)reloadFromDataSources
{
    for (MPSNNFilterNode *filter in _filters)
        if ([filter respondsToSelector:@selector(reloadFromDataSource)])
            [(id)filter performSelector:@selector(reloadFromDataSource)];
}

- (MPSImage *)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                      sourceImages:(NSArray<MPSImage *> *)sourceImages
{
    if (!_walked) {
        CharonMPSRefuse(@"MPSNNGraph: the graph was built with no result image, so there is nothing to walk");
        return nil;
    }
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return nil;

    // Bind each graph input to the caller's image, in the order sourceImageHandles reports.
    for (NSUInteger index = 0; index < _sources.count && index < sourceImages.count; index++)
        [_sources[index] charon_mps_setImage:sourceImages[index]];

    // The walk, forwards. Each node's result image is allocated from the shape its padding policy gives
    // for the shape it reads, and each node runs its own kernel over it. A node with no kernel says so
    // once and the walk continues, so one abstract node in the middle does not take the graph with it.
    for (MPSNNFilterNode *filter in _filters) {
        [filter charon_mps_setDevice:self.device];
        NSMutableArray *bound = [NSMutableArray array];
        MPSImage *first = nil;
        for (MPSNNImageNode *sourceNode in filter.charon_mps_sourceNodes) {
            MPSImage *image = sourceNode.charon_mps_image;
            if (image)
                [bound addObject:image];
            if (!first)
                first = image;
        }
        [filter charon_mps_setSourceImages:bound];

        MPSImageDescriptor *sourceDescriptor = [first charon_mps_descriptor];
        if (!sourceDescriptor) {
            CharonMPSRefuse(@"%@: the node's source holds no image, so it was not run",
                            NSStringFromClass([filter class]));
            continue;
        }
        MPSImageDescriptor *destinationDescriptor = [filter charon_mps_destinationDescriptorForSource:sourceDescriptor];
        if (!destinationDescriptor) {
            CharonMPSRefuse(@"%@: the node has no shape to produce, so it was not run",
                            NSStringFromClass([filter class]));
            continue;
        }
        MPSImage *destination = [[MPSImage alloc] initWithDevice:self.device imageDescriptor:destinationDescriptor];
        [filter charon_mps_setDestinationImage:destination];
        [filter charon_mps_encodeToCommandBuffer:commandBuffer];
    }

    MPSNNImageNode *result = _order.lastObject;
    if (!_resultImageIsNeeded || !result)
        // "If resultIsNeeded is set to NO, nil will be returned from the left hand side of the -encode
        // call instead, and computation to produce the last image may be pruned away" (MPSNNGraph.h:72).
        return nil;
    return result.charon_mps_image;
}

- (MPSImage *)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                      sourceImages:(NSArray<MPSImage *> *)sourceImages
                      sourceStates:(NSArray<MPSState *> *)sourceStates
                intermediateImages:(NSMutableArray<MPSImage *> *)intermediateImages
                 destinationStates:(NSMutableArray<MPSState *> *)destinationStates
{
    MPSImage *image = [self encodeToCommandBuffer:commandBuffer sourceImages:sourceImages];
    // The exported intermediates, MPSNNGraph.h:239-243: only the nodes tagged exportFromGraph, and only
    // when the caller asked for the list to receive them.
    if (intermediateImages) {
        for (MPSNNImageNode *node in _order) {
            if (node.exportFromGraph && node.charon_mps_image)
                [intermediateImages addObject:node.charon_mps_image];
        }
    }
    // A graph of this package's nodes produces no states, so there are none to put in either list; a
    // caller that passed a non-nil destinationStates gets it left empty rather than nil, which is what
    // "optional NSMutableArray to receive" means for a graph that has nothing to receive.
    (void)sourceStates;
    (void)destinationStates;
    return image;
}

// "This function will synchronously encode the graph on a private command buffer, commit it to a MPS
// internal command queue and return... The work will be performed on the MTLDevice that hosts the source
// images" (MPSNNGraph.h:305-311).
//
// THE COMMAND BUFFER COMES OFF A QUEUE, and that is the only place one exists: MTLDevice.h:507-518
// declares -newCommandQueue and -newCommandQueueWithMaxCommandBufferCount: and nothing else, and
// -commandBuffer belongs to MTLCommandQueue. An earlier form of this file asked the DEVICE for one with
// `[self.device newCommandBuffer]`, which is not a selector MTLDevice declares, and which does not
// compile - it was hidden behind a file-wide pragma that silenced every warning in the file, and the
// object had therefore never been built for armv7. The route below is the framework's own order: the
// graph's device, then a queue from it, then a buffer from the queue. The queue is made per call because
// MPSNNGraph.h:305 calls the command queue "MPS internal", and this port's MPSKernel9.m and the host case
// both hold no queue of their own.
- (MPSImage *)executeAsyncWithSourceImages:(NSArray<MPSImage *> *)sourceImages
                         completionHandler:(MPSNNGraphCompletionHandler)handler
{
    id<MTLDevice> device = self.device ? self.device : MTLCreateSystemDefaultDevice();
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];
    if (!commandBuffer) {
        CharonMPSRefuse(@"MPSNNGraph: no command buffer could be made for the graph's device, so it was not run");
        if (handler)
            handler(nil, [NSError errorWithDomain:@"MPSNNGraph" code:1 userInfo:nil]);
        return nil;
    }
    MPSImage *image = [self encodeToCommandBuffer:commandBuffer sourceImages:sourceImages];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    // The port's own kernels are synchronous and a result is in the image when -encodeToCommandBuffer:
    // returns, so the commit and the wait are a formality here; they are made anyway, because the
    // header's contract is that the data is not valid until this method's completion handler is called
    // and a caller is entitled to that.
    if (handler)
        handler(image, commandBuffer.error);
    return image;
}

@end

#pragma clang diagnostic pop
