// MPSGraphTensorShapeOps161.m - the two general forms of the space-to-depth family, which arrived with
// MPSGraph in 16.1: spaceToBatchTensor and batchToSpaceTensor, each over any number of spatial axes and a
// rectangular block. From the header MPSGraphTensorShapeOps.h in the SDK of iOS 16.4, which declares both
// with their own availability notes (ios(16.1)).
//
// One object per release: this one names two methods of 16.1 and nothing else. The work is 15.0's own chain
// of walks - a reshape that splits each spatial axis into its block rows and columns, the permutation
// transpose of 16.0, and the reshape back - reached through the seam
// -charon_mps_blockShuffle:spatial:batch:block:toBatch:shuffle:name: in MPSGraph14.m, and every measurement
// and every refusal of the family is there and in facts/MetalPerformanceShadersGraph/Core.md. What this
// object adds over 15.0's two-axis form is that the block is a LIST, one extent per spatial axis, and that
// the spatial axes are a LIST: the block's own coordinates are ordered with the LAST of them fastest, the
// result's spatial axes keep the OPERAND's order whichever order the list is written in, and the list of
// block dimensions is read in the order it is written - all three measured.
//
// The FED forms are the header's own and the release's answer to them is the same as everywhere else in this
// library's shape family: a CONSTANT of the values answers, and exactly what the written-down form answers,
// and a PLACEHOLDER - which is what a caller who wants the axes to arrive as data makes - takes the release
// down. refusals.m measures both.
#import "CharonMPSGraph.h"

@implementation MPSGraph (CharonMPSGraphTensorShape161)

// The SPACE-TO-BATCH, which is the generalisation 15.0's space-to-depth is a special case of: any number of
// spatial axes and a rectangular block instead of two axes and a square one.
//
// MEASURED on this host's own MPSGraph over a [2, 4, 8] of 1 to 64 with the spatial axes @[@1, @2], the batch
// axis @0 and the block @[@2, @4]: the result is a [16, 2, 2], and with the spatial axes written the other
// way round and the block @[@4, @2] it is the same shape and DIFFERENT bytes - which is what says the block
// list is read in the order it is written. With ONE spatial axis it is 15.0's form without the 2D names, and
// with THREE of them the last varies fastest of all.
- (MPSGraphTensor *)spaceToBatchTensor:(MPSGraphTensor *)tensor
                          spatialAxes:(NSArray<NSNumber *> *)spatialAxes
                            batchAxis:(NSInteger)batchAxis
                      blockDimensions:(NSArray<NSNumber *> *)blockDimensions
                 usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                 name:(NSString *)name
{
    return [self charon_mps_blockShuffle:tensor
                                  spatial:spatialAxes ?: @[]
                                    batch:batchAxis
                                    block:blockDimensions ?: @[]
                                  toBatch:YES
                                  shuffle:usePixelShuffleOrder
                                      name:name];
}

// The BATCH-TO-SPACE, which is the inverse of the space-to-batch with the same flag - measured, a
// space-to-batch over a [3, 4, 6] and then the batch-to-space of what it built answers 1 to 72 in the
// operand's own order, for both flags, and the same for the 2D pair. Its own rule the header names and the
// release refuses: the batch axis must not be one of the spatial axes ("`batch_axis` = 0 must be unique
// from `spatial_axes`"), every spatial axis has to be an axis of its own, the block needs one extent per
// spatial axis, and each extent has to divide the axis it is a block of.
- (MPSGraphTensor *)batchToSpaceTensor:(MPSGraphTensor *)tensor
                          spatialAxes:(NSArray<NSNumber *> *)spatialAxes
                            batchAxis:(NSInteger)batchAxis
                      blockDimensions:(NSArray<NSNumber *> *)blockDimensions
                 usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                 name:(NSString *)name
{
    return [self charon_mps_blockShuffle:tensor
                                  spatial:spatialAxes ?: @[]
                                    batch:batchAxis
                                    block:blockDimensions ?: @[]
                                  toBatch:NO
                                  shuffle:usePixelShuffleOrder
                                      name:name];
}

// The FED forms of the two above, where the spatial axes, the batch axis and the block dimensions each
// arrive as a tensor. The port reads a fed parameter the graph HOLDS - a constant - when the graph is built,
// which is the only fed form the release answers (measured: int32 constants of the same values answer
// exactly what the written-down axes answer, over the same operand), and refuses a placeholder there, because
// the release takes the process down over one: the split family measured the same rule for a split's sizes,
// and this is the same header's fed shape.
- (MPSGraphTensor *)spaceToBatchTensor:(MPSGraphTensor *)tensor
                    spatialAxesTensor:(MPSGraphTensor *)spatialAxesTensor
                      batchAxisTensor:(MPSGraphTensor *)batchAxisTensor
                blockDimensionsTensor:(MPSGraphTensor *)blockDimensionsTensor
                 usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                 name:(NSString *)name
{
    return [self charon_mps_fedBlockShuffle:tensor
                                     spatial:spatialAxesTensor
                                       batch:batchAxisTensor
                                       block:blockDimensionsTensor
                                     toBatch:YES
                                     shuffle:usePixelShuffleOrder
                                         name:name];
}

- (MPSGraphTensor *)batchToSpaceTensor:(MPSGraphTensor *)tensor
                    spatialAxesTensor:(MPSGraphTensor *)spatialAxesTensor
                      batchAxisTensor:(MPSGraphTensor *)batchAxisTensor
                blockDimensionsTensor:(MPSGraphTensor *)blockDimensionsTensor
                 usePixelShuffleOrder:(BOOL)usePixelShuffleOrder
                                 name:(NSString *)name
{
    return [self charon_mps_fedBlockShuffle:tensor
                                     spatial:spatialAxesTensor
                                       batch:batchAxisTensor
                                       block:blockDimensionsTensor
                                     toBatch:NO
                                     shuffle:usePixelShuffleOrder
                                         name:name];
}

@end