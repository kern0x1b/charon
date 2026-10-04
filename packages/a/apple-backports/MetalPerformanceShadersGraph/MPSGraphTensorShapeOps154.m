// MPSGraphTensorShapeOps154.m - the eight shape operations that arrived with MPSGraph in 15.4: the four
// squeezes, the three expanded dimensions and the stack. From the header MPSGraphTensorShapeOps.h in the SDK
// of iOS 16.4, which declares all eight, each with its own availability note (ios(15.4)).
//
// One object per release: this one names eight methods of 15.4 and nothing of any other release. The seven
// about axes are one walk in MPSGraphInterpreter14.m with the axes left alone - measured, every one of them
// answers the operand's own bytes in the operand's own order - so what is here is each method's own rule
// about which axes the result keeps, which is measured as well:
//
//   - a squeeze with no axes drops every axis of extent one and leaves the rest: a 1x2x4 is a 2x4 of the same
//     eight bytes, and a 2x4 with no unit axis is itself.
//   - a squeeze of one axis drops that axis and keeps the rest, in order.
//   - a squeeze of a set of axes drops those of them and keeps the rest, in order.
//   - an expanded dimension at an axis adds an axis of extent one there: axis 0 of a 2x4 is a 1x2x4 of the
//     same bytes, axis 2 and axis -1 are a 2x4x1, and a negative axis is counted from the end and may be the
//     rank itself, which is the trailing unit axis.
//   - an expanded dimension of a set of axes adds one there for each of them: axes @[@0, @2] of a 2x4 is a
//     1x2x1x4.
//
// The one the release refuses is a squeeze of an axis that is not of extent one: measured, it writes
// "squeezed axis must have length 1, input.shape[1] == 2" and then "LLVM ERROR: Failed to infer result
// type(s)" takes the process down, so the port raises NSInvalidArgumentException instead - the refusal the
// reduction family's axis is, and the one an axis outside the rank is. The stack's own two refusals - an axis
// outside the result's rank, and operands whose shapes differ at all - are above its own method.

#import "CharonMPSGraph.h"

@implementation MPSGraph (CharonMPSGraphTensorShape154)

// The STACK, which is the concatenation family of 14.0 with one axis ADDED rather than one axis filled: the
// result's axis of extent as many operands as the caller wrote down says which operand an element came from,
// and the axes around it are the operands' own. So it is that family's one walk, reached through its seam,
// with the axis the caller named counted from the end of the RESULT's rank - one more than the operands' -
// which is what the header's own range says (`-rank + 1 <= dimension < rank + 1`).
//
// Measured on this host's own MPSGraph, over a 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40) beside one of
// (5, 6, 7, 8 | 50, 60, 70, 80) and one of (9, 10, 11, 12 | 90, 100, 110, 120):
//   - axis 1 of two is a 2x2x4 of (1, 2, 3, 4, 5, 6, 7, 8 | 10, 20, 30, 40, 50, 60, 70, 80) and axis 2 a
//     2x4x2 of (1, 5, 2, 6, 3, 7, 4, 8 | 10, 50, 20, 60, 30, 70, 40, 80), so the operands are laid along
//     that axis in the order the caller wrote them - which is the concatenation with no interleave and an
//     extent of one each.
//   - a NEGATIVE axis is counted from the end of the result's rank, so axes -3, -2 and -1 answer what axes
//     0, 1 and 2 answer, and an axis outside -3 to 2 is refused by the release's own compiler - "invalid
//     axis: 3, axis must be in range -|rank| <= axis < |rank|" (MPSGraphUtilities.mm:3237), over an operation
//     of its own: the release builds this as an expanded dimension per operand and then a concatenation.
//   - ONE operand answers the operand itself with the new axis of extent one: measured, a stack of one 2x4
//     is a 1x2x4 of its own eight values.
//   - every operand has to have the SAME shape, which the header calls "broadcast compatible" and the
//     release does not take: measured, a 2x4 and a 2x4 beside a 1x4 stacked at axis 1 are refused by its own
//     compiler with "'mps.concat' op invalid input tensor shapes, all input shapes must match except at axis"
//     (MPSGraphUtilities.mm:748), and so are a 1x4 and a 2x4 stacked at axis 0. The port raises there.
- (MPSGraphTensor *)stackTensors:(NSArray<MPSGraphTensor *> *)inputTensors
                            axis:(NSInteger)axis
                            name:(NSString *)name
{
    return [self charon_mps_concat:CharonMPSGraphOperationKindStack
                            tensors:inputTensors ?: @[]
                               axis:axis
                         interleave:NO
                              name:name];
}

// The squeeze and the expanded dimension are one walk in MPSGraphInterpreter14.m with the axes left alone -
// measured, every one of the seven methods here answers the operand's own bytes in the operand's own order -
// so what is left in this object is each method's own answer to one question: which axes are dropped, which
// are added, and whether the caller wrote them down or fed them. The walk turns that into the result's
// shape and into which axis of the operand each axis of the result reads, and it is the walk that refuses
// what the release cannot build.

// A squeeze with no axes drops every axis of extent one and leaves the rest: measured, a 1x2x4 is a 2x4 of
// the same eight bytes and a 2x4 with no unit axis is itself.
- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    NSMutableArray<NSNumber *> *unit = [NSMutableArray array];
    NSUInteger rank = tensor.shape.count;
    for (NSUInteger axis = 0; axis < rank; axis++)
        if (tensor.shape[axis].integerValue == 1)
            [unit addObject:@(axis)];
    return [self charon_mps_gather:CharonMPSGraphOperationKindSqueeze
                             tensor:tensor
                        parameters:@{@"gather": @"squeeze", @"gatherDrop": unit}
                               name:name];
}

- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor
                              axis:(NSInteger)axis
                              name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindSqueeze
                             tensor:tensor
                        parameters:@{@"gather": @"squeeze", @"gatherDrop": @[@(axis)]}
                               name:name];
}

- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor
                              axes:(NSArray<NSNumber *> *)axes
                              name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindSqueeze
                             tensor:tensor
                        parameters:@{@"gather": @"squeeze", @"gatherDrop": axes ?: @[]}
                               name:name];
}

- (MPSGraphTensor *)squeezeTensor:(MPSGraphTensor *)tensor
                        axesTensor:(MPSGraphTensor *)axesTensor
                              name:(NSString *)name
{
    // The axes are fed, so which of them they are is not known until the graph runs: the walk reads them out
    // of the operation's second input, which is why nothing but the transformation's own name is written
    // down here.
    return [self charon_mps_gather:CharonMPSGraphOperationKindSqueeze
                             tensor:tensor
                      fedParameter:axesTensor
                        parameters:@{@"gather": @"squeeze", @"gatherOperand": @"axes"}
                               name:name];
}

// An expanded dimension at an axis adds an axis of extent one there: measured, axis 0 of a 2x4 is a 1x2x4 of
// the same bytes, axis 2 and axis -1 are a 2x4x1 - and a negative axis is counted from the end and may be the
// rank itself, which is the trailing unit axis.
- (MPSGraphTensor *)expandDimsOfTensor:(MPSGraphTensor *)tensor
                                  axis:(NSInteger)axis
                                  name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindExpandDims
                             tensor:tensor
                        parameters:@{@"gather": @"expand", @"gatherAdd": @[@(axis)]}
                               name:name];
}

- (MPSGraphTensor *)expandDimsOfTensor:(MPSGraphTensor *)tensor
                                  axes:(NSArray<NSNumber *> *)axes
                                  name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindExpandDims
                             tensor:tensor
                        parameters:@{@"gather": @"expand", @"gatherAdd": axes ?: @[]}
                               name:name];
}

- (MPSGraphTensor *)expandDimsOfTensor:(MPSGraphTensor *)tensor
                            axesTensor:(MPSGraphTensor *)axesTensor
                                  name:(NSString *)name
{
    return [self charon_mps_gather:CharonMPSGraphOperationKindExpandDims
                             tensor:tensor
                      fedParameter:axesTensor
                        parameters:@{@"gather": @"expand", @"gatherOperand": @"axes"}
                               name:name];
}

@end
