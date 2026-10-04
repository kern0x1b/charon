// MPSGraphTensorShapeOps150.m - the six shape and axis operations that arrived with MPSGraph in 15.0: the
// two flattens, the two broadcasts and the three reverses. From the headers MPSGraphTensorShapeOps.h and
// MPSGraphTensorShapeOps.h's reshape header in the SDK of iOS 16.4, which declare all six, each with its own
// availability note (ios(15.0)).
//
// One object per release: this one names six methods of 15.0 and nothing of any other release. All six are
// one walk in MPSGraphInterpreter14.m - the result is the operand's elements in some other order or extent,
// and which axis of the result each axis of the operand feeds is the whole of the difference - so what is
// here is each method's own rule, and each of those is measured (facts/MetalPerformanceShadersGraph/Core.md):
//
//   - a flatten collapses every axis from the one named on into a single axis: axis 0 of a 2x4 is a 1x8 of the
//     operand's own bytes, axis 1 of a 2x4 is the 2x4 itself, and axis 0 of a 2x3x4 is a 1x24.
//   - a broadcast aligns the operand to the RIGHT of the shape given and wraps each axis that the shape makes
//     wider: a 2x4 into a 4x4 answers each of its rows twice, and into a 2x2x4 answers the 2x4 twice.
//   - a reverse flips the axes it is given and nothing else: axis 1 of a 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40)
//     answers (4, 3, 2, 1 | 40, 30, 20, 10), axis 0 answers the two rows the other way round, and no axes at
//     all reverses every axis.

#import "CharonMPSGraph.h"

@implementation MPSGraph (CharonMPSGraphTensorShape150)

// The fed form of the reshape, which arrived with 15.0: the shape is a 1D tensor of int32 or int64, so the
// result's own shape is not known until the graph runs and the walk reads it out of the operation's second
// input. Measured, an int32 and an int64 of shape [1] both answer.
- (MPSGraphTensor *)reshapeTensor:(MPSGraphTensor *)tensor
                  withShapeTensor:(MPSGraphTensor *)shapeTensor
                             name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindReshape
                             tensor:tensor
                      fedParameter:shapeTensor
                        parameters:@{@"gather": @"reshape", @"gatherOperand": @"shape"}
                               name:name];
}

// The axis is the caller's and is normalised by the walk: negative counted from the end of the rank, and an
// axis outside it refused there, because the release destroys the process over one.
- (MPSGraphTensor *)flatten2DTensor:(MPSGraphTensor *)tensor
                                axis:(NSInteger)axis
                                name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindFlatten2D
                             tensor:tensor
                        parameters:@{@"gather": @"flatten", @"gatherAxis": @(axis)}
                               name:name];
}

- (MPSGraphTensor *)flatten2DTensor:(MPSGraphTensor *)tensor
                          axisTensor:(MPSGraphTensor *)axisTensor
                                name:(NSString *)name
{
    // The shape here is the widest the family can produce: every axis collapsed into one, which the walk
    // narrows by the axis it reads when the graph runs. Measured, an int32 and an int64 axis of shape [1]
    // both answer.
    NSMutableArray<NSNumber *> *collapsed = [NSMutableArray array];
    [collapsed addObject:@(CharonMPSGraphElementCount(tensor.shape))];
    return [self charon_mps_gather:CharonMPSGraphOperationKindFlatten2D
                             tensor:tensor
                      fedParameter:axisTensor
                        parameters:@{@"gather": @"flatten", @"gatherOperand": @"axis"}
                               name:name];
}

- (MPSGraphTensor *)broadcastTensor:(MPSGraphTensor *)tensor
                            toShape:(NSArray<NSNumber *> *)toShape
                               name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindBroadcast
                             tensor:tensor
                        parameters:@{@"gather": @"broadcast", @"gatherShape": toShape}
                               name:name];
}

- (MPSGraphTensor *)broadcastTensor:(MPSGraphTensor *)tensor
                      toShapeTensor:(MPSGraphTensor *)toShapeTensor
                               name:(NSString *)name
{
    // The shape is fed, so the result's own shape is not known until the graph runs: the walk reads it out of
    // the operand it was given, which is why nothing but the transformation's own name is written down here.
    return [self charon_mps_gather:CharonMPSGraphOperationKindBroadcast
                             tensor:tensor
                      fedParameter:toShapeTensor
                        parameters:@{@"gather": @"broadcast", @"gatherOperand": @"shape"}
                               name:name];
}

- (MPSGraphTensor *)reverseTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindReverse
                             tensor:tensor
                        parameters:@{@"gather": @"reverse"}
                               name:name];
}

- (MPSGraphTensor *)reverseTensor:(MPSGraphTensor *)tensor
                              axes:(NSArray<NSNumber *> *)axes
                              name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindReverse
                             tensor:tensor
                        parameters:@{@"gather": @"reverse", @"gatherAxes": axes ?: @[]}
                               name:name];
}

- (MPSGraphTensor *)reverseTensor:(MPSGraphTensor *)tensor
                       axesTensor:(MPSGraphTensor *)axesTensor
                              name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindReverse
                             tensor:tensor
                      fedParameter:axesTensor
                        parameters:@{@"gather": @"reverse", @"gatherOperand": @"axes"}
                               name:name];
}

#pragma mark - the space-to-depth family of 15.0: two axes of a block and the axis the blocks go to

// The SPACE-TO-DEPTH of 15.0, which is the general form of 16.1 with two spatial axes and one block size
// for both of them, and every measurement of this family is in
// -charon_mps_blockShuffle:spatial:batch:block:toBatch:shuffle:name: and in
// facts/MetalPerformanceShadersGraph/Core.md. What is here is the 2D form's own rule about ITS two axes:
// widthAxis is the fastest-running dimension WITHIN the block and heightAxis the second, so the general form's
// spatialAxes list is (heightAxis, widthAxis) - measured, the two forms over the same operand and the same
// block answer byte for byte the same values - and the depth axis is where the blocks go.
//
// Measured over a [2, 2, 4] of (1, 2, 3, 4 | 5, 6, 7, 8 | 9, 10, 11, 12 | 13, 14, 15, 16) with widthAxis 2,
// heightAxis 1, depthAxis 0 and a block of 2: the result is an 8x1x2, and with usePixelShuffleOrder=NO it is
// (1, 3 | 9, 11 | 2, 4 | 10, 12 | 5, 7 | 13, 15 | 6, 8 | 14, 16) - the operand's batch coordinate varying
// fastest inside the result's depth axis - and with YES (1, 3 | 2, 4 | 5, 7 | 6, 8 | 9, 11 | 10, 12 | 13, 15 |
// 14, 16), the block's own two values contiguous in it. A block of ONE is the identity (a 2x2x4 of the same
// sixteen values), and the 2D form's refusals are the release's own: an axis outside the rank with the axis's
// name in the sentence ("invalid width_axis (3) for shape of rank 3"), the depth axis among the two spatial
// ones, and a block that does not divide the extent it is a block of ("block_size (4) must be multiple of
// height 2").
- (MPSGraphTensor *)spaceToDepth2DTensor:(MPSGraphTensor *)tensor
                              widthAxis:(NSUInteger)widthAxis
                             heightAxis:(NSUInteger)heightAxis
                              depthAxis:(NSUInteger)depthAxis
                              blockSize:(NSUInteger)blockSize
                   usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                   name:(NSString *)name
{
    return [self charon_mps_blockShuffle:tensor
                                  spatial:@[@(heightAxis), @(widthAxis)]
                                    batch:(NSInteger)depthAxis
                                    block:@[@(blockSize), @(blockSize)]
                                  toBatch:YES
                                  shuffle:usePixelShuffleOrder
                                      name:name];
}

// The DEPTH-TO-SPACE of 15.0, which is the inverse of the space-to-depth above with the same flag: measured,
// a space-to-depth over a [3, 4, 6] and then the depth-to-space of what it built answers 1 to 72 in the
// operand's own order, for both flags.
- (MPSGraphTensor *)depthToSpace2DTensor:(MPSGraphTensor *)tensor
                              widthAxis:(NSUInteger)widthAxis
                             heightAxis:(NSUInteger)heightAxis
                              depthAxis:(NSUInteger)depthAxis
                              blockSize:(NSUInteger)blockSize
                   usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                   name:(NSString *)name
{
    // THE BLOCK RULE IN THE WORDS OF THIS OPERATION, which is not the general form's words for the same
    // rule. Moving the blocks OUT of the batch axis makes the block SQUARED divide the depth axis, and the
    // release says so where it says "Invalid prod(`block_dimensions`)" for the general form: measured over a
    // [12, 2, 3] with a block of 3, it builds the result as a 1x6x9 and refuses when the graph is COMPILED
    // with "'mps.depth_to_space_2d' op block_size (3) squared (9) must be multiple of depth 12". The
    // general form's own sentence is in the seam; this one is the 2D form's, and it lives here with the
    // method of 15.0 that answers with it.
    NSArray<NSNumber *> *operandShape = tensor.shape;
    long long depth = operandShape.count > 0 ? operandShape[(NSUInteger)depthAxis].longLongValue : 0;
    long long square = (long long)blockSize * (long long)blockSize;
    if (blockSize == 0 || (depth % square) != 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MPSGraph: %@ was given a block of %lu, whose square is %lld, for a depth axis of "
                           @"%lld elements, and this direction makes the block squared divide the depth axis: "
                           @"measured, the release's own compiler refuses it with \"'mps.depth_to_space_2d' op "
                           @"block_size (%lu) squared (%lld) must be multiple of depth %lld\"",
                      name, (unsigned long)blockSize, square, depth, (unsigned long)blockSize, square, depth];
    }
    return [self charon_mps_blockShuffle:tensor
                                  spatial:@[@(heightAxis), @(widthAxis)]
                                    batch:(NSInteger)depthAxis
                                    block:@[@(blockSize), @(blockSize)]
                                  toBatch:NO
                                  shuffle:usePixelShuffleOrder
                                      name:name];
}

// The FED pair of 15.0, the two methods above with their THREE axes arriving as tensors and the block size
// still written down - which is what the header declares:
//   spaceToDepth2DTensor:widthAxisTensor:heightAxisTensor:depthAxisTensor:blockSize:usePixelShuffleOrder:name:
//   depthToSpace2DTensor:widthAxisTensor:heightAxisTensor:depthAxisTensor:blockSize:usePixelShuffleOrder:name:
// MEASURED on this host's own MPSGraph over the same [3, 4, 6] of 1 to 72 the written-down forms use, and
// with the same three axes of 2, 1 and 0 and the same block of 2:
//
//   - AN INT32 CONSTANT OF SHAPE [1] ANSWERS EXACTLY WHAT THE WRITTEN-DOWN FORM ANSWERS, byte for byte, in
//     both directions and under both flags - which is the whole of what a caller is asking when it makes
//     these three parameters tensors. An int64 of shape [1] answers the same, so the release takes a shape
//     of four or of eight bytes, as it does for every other fed shape of this library.
//   - A CONSTANT OF NO RANK IS NOT CONSTRUCTIBLE: the release's own +constantWithData:shape:dataType: takes
//     the process down with "failed assertion `shape.count > 0 failed, a constant must be passed a ranked
//     shape'" (exit 134), so the axis tensor has to be written with a rank at all.
//   - A CONSTANT OF MORE THAN ONE NUMBER answers NOTHING: the graph builds and the result carries no shape
//     at all, so there is nothing to read or to run into.
//   - A PLACEHOLDER answers NOTHING EITHER, and unlike the 16.1 fed forms it does not take the process
//     down: the graph builds, the result carries no shape, and -compileWithDevice: still hands back an
//     executable (measured, both directions, exit 0). The rule for the port is the rule the rest of this
//     library's fed parameters already follow: read the value where the graph is built when the graph HOLDS
//     it, and refuse it there when the caller FEEDS it, because a parameter that arrives as data is not a
//     parameter this port can build the chain over.
//   - THE REFUSALS ARE THE TWO FORMS' OWN, over a constant as much as over a written-down axis: an axis
//     outside the rank is refused where the graph is built ("invalid width_axis (3) for shape of rank 3",
//     with the result's shape nil and the graph's own "Failed to infer result type(s)" behind it), while the
//     depth axis among the two spatial ones and a block that does not divide are refused where the graph is
//     COMPILED ("'mps.space_to_depth_2d' op Invalid degenerate axes: depth_axis (1) height_axis (1) for
//     shape of rank 3", "'mps.space_to_depth_2d' op block_size (3) must be multiple of height 4", and
//     "'mps.depth_to_space_2d' op block_size (3) squared (9) must be multiple of depth 12"). The port asks
//     each of them where the graph is built, which is this library's rule everywhere and which the two rows
//     of this pair say in their own words.
static NSInteger CharonMPSGraphBlockAxis(MPSGraph *graph, MPSGraphTensor *tensor, NSString *axisName,
                                         NSString *name)
{
    NSArray<NSNumber *> *one = [graph charon_mps_constantShapeOfTensor:tensor];
    if (one == nil) {
        MPSDataType type = tensor.dataType;
        if (type == MPSDataTypeFloat32 || type == MPSDataTypeFloat16 || type == MPSDataTypeBool) {
            [NSException raise:NSInvalidArgumentException
                        format:@"MPSGraph: %@ was given its %@ as a tensor of data type 0x%x, and an axis is "
                               @"an index: measured, the release builds a graph whose result carries no shape "
                               @"at all over one, for both of this pair's directions", name, axisName,
                              (unsigned)type];
        }
        [NSException raise:NSInvalidArgumentException
                    format:@"MPSGraph: %@ was given its %@ as a tensor the caller feeds, and an axis that "
                           "arrives as data is not an axis this port can build the chain over: measured, the "
                           "release builds the graph with the result carrying no shape and hands back an "
                           "executable, for both of this pair's directions", name, axisName];
    }
    if (one.count != 1) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MPSGraph: %@ was given %lu numbers as its %@, and an axis is one of them: measured, "
                           "the release takes an axis as a 0D tensor or one of shape [1], and over anything else "
                           "it builds a result that carries no shape", name, (unsigned long)one.count, axisName];
    }
    return one.firstObject.integerValue;
}

- (MPSGraphTensor *)spaceToDepth2DTensor:(MPSGraphTensor *)tensor
                        widthAxisTensor:(MPSGraphTensor *)widthAxisTensor
                       heightAxisTensor:(MPSGraphTensor *)heightAxisTensor
                        depthAxisTensor:(MPSGraphTensor *)depthAxisTensor
                              blockSize:(NSUInteger)blockSize
                   usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                   name:(NSString *)name
{
    NSUInteger width = (NSUInteger)CharonMPSGraphBlockAxis(self, widthAxisTensor, @"width axis", name);
    NSUInteger height = (NSUInteger)CharonMPSGraphBlockAxis(self, heightAxisTensor, @"height axis", name);
    NSUInteger depth = (NSUInteger)CharonMPSGraphBlockAxis(self, depthAxisTensor, @"depth axis", name);
    return [self spaceToDepth2DTensor:tensor
                            widthAxis:width
                           heightAxis:height
                            depthAxis:depth
                            blockSize:blockSize
                 usePixelShuffleOrder:usePixelShuffleOrder
                                 name:name];
}

- (MPSGraphTensor *)depthToSpace2DTensor:(MPSGraphTensor *)tensor
                        widthAxisTensor:(MPSGraphTensor *)widthAxisTensor
                       heightAxisTensor:(MPSGraphTensor *)heightAxisTensor
                        depthAxisTensor:(MPSGraphTensor *)depthAxisTensor
                              blockSize:(NSUInteger)blockSize
                   usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                   name:(NSString *)name
{
    NSUInteger width = (NSUInteger)CharonMPSGraphBlockAxis(self, widthAxisTensor, @"width axis", name);
    NSUInteger height = (NSUInteger)CharonMPSGraphBlockAxis(self, heightAxisTensor, @"height axis", name);
    NSUInteger depth = (NSUInteger)CharonMPSGraphBlockAxis(self, depthAxisTensor, @"depth axis", name);
    return [self depthToSpace2DTensor:tensor
                            widthAxis:width
                           heightAxis:height
                            depthAxis:depth
                            blockSize:blockSize
                 usePixelShuffleOrder:usePixelShuffleOrder
                                 name:name];
}

@end
