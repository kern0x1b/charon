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

@end
