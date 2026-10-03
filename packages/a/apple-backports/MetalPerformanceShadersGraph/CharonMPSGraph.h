// CharonMPSGraph.h — what this framework's own files share.
//
// The guard is not decoration: the host harness includes this header twice over, once through a
// source's own import and once through its prefixed declarations, and a header that declares classes
// has to survive that.
//
// A graph is a description of work and a tensor is a description of a result; the arithmetic happens
// when the graph runs, over the host memory behind an MTLBuffer, exactly as the matrix kernels in
// ../MetalPerformanceShaders do (facts/MetalPerformanceShaders/Matrix.md). Nothing here needs a
// texture, so none of it waits on the pixel formats.
//
// The interpreter is a table: an operation records what it is and what its operands are, and
// -[MPSGraph runWithFeeds:targetTensors:targetOperations:] walks the operations in the order they were
// added, asking each one to fill its outputs. A tensor's value is found by looking it up: a
// placeholder's comes from the feeds, any other one's from the operation that produced it.

#ifndef MPSGRAPH_CHARON_H
#define MPSGRAPH_CHARON_H

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>

// The matrix framework's own header already says what an MPSDataType means and how an element is read
// and written, so including it here means one definition rather than two.
#import "../MetalPerformanceShaders/CharonMPS.h"

// A graph that cannot run says so once, in the log, naming what it could not do, and writes nothing:
// an operation the release would have faulted on leaves its output alone here rather than filling it
// with something of another kind's meaning.
#define CharonMPSGraphRefuse(...) NSLog(__VA_ARGS__)

// The number of elements a tensor of a shape holds. A dimension below one is taken as one, which is
// what a scalar's empty shape and a degenerate extent both come to.
static inline NSUInteger CharonMPSGraphElementCount(NSArray<NSNumber *> *shape)
{
    NSUInteger count = 1;
    for (NSNumber *dimension in shape) {
        NSInteger extent = dimension.integerValue;
        count *= (NSUInteger)(extent > 1 ? extent : 1);
    }
    return count;
}

// What an operation is, which is how the interpreter knows what to run. One case per family, so a
// family lands by adding a case and a function rather than by touching every other one.
typedef NS_ENUM(NSInteger, CharonMPSGraphOperationKind) {
    CharonMPSGraphOperationKindNone = 0,
    CharonMPSGraphOperationKindPlaceholder,
    CharonMPSGraphOperationKindConstant,
    CharonMPSGraphOperationKindAdd,
    CharonMPSGraphOperationKindSubtract,
    CharonMPSGraphOperationKindMultiply,
    CharonMPSGraphOperationKindDivide,
    CharonMPSGraphOperationKindNegate,
    CharonMPSGraphOperationKindSquare,
    CharonMPSGraphOperationKindReciprocal,
    CharonMPSGraphOperationKindRsqrt,
    CharonMPSGraphOperationKindSqrt,
    CharonMPSGraphOperationKindExp,
    CharonMPSGraphOperationKindLog,
    CharonMPSGraphOperationKindAbs,
    CharonMPSGraphOperationKindSign,
    CharonMPSGraphOperationKindMinimum,
    CharonMPSGraphOperationKindMaximum,
    CharonMPSGraphOperationKindClamp,
    CharonMPSGraphOperationKindIdentity,
    // The transcendentals and the rounding of the 14.0 arithmetic family. Each is the C function of
    // that name and nothing else: what the release answers for a zero, a negative and an infinity is
    // measured per case in tests/backports/host/mpsgraph, and what it answers that IEEE does not is in
    // facts/MetalPerformanceShadersGraph/Core.md.
    CharonMPSGraphOperationKindExpBase2,
    CharonMPSGraphOperationKindExpBase10,
    CharonMPSGraphOperationKindLogBase2,
    CharonMPSGraphOperationKindLogBase10,
    CharonMPSGraphOperationKindSin,
    CharonMPSGraphOperationKindCos,
    CharonMPSGraphOperationKindTan,
    CharonMPSGraphOperationKindSinh,
    CharonMPSGraphOperationKindCosh,
    CharonMPSGraphOperationKindTanh,
    CharonMPSGraphOperationKindAsin,
    CharonMPSGraphOperationKindAcos,
    CharonMPSGraphOperationKindAtan,
    CharonMPSGraphOperationKindAsinh,
    CharonMPSGraphOperationKindAcosh,
    CharonMPSGraphOperationKindAtanh,
    CharonMPSGraphOperationKindErf,
    CharonMPSGraphOperationKindSignBit,
    CharonMPSGraphOperationKindFloor,
    CharonMPSGraphOperationKindCeil,
    CharonMPSGraphOperationKindRound,
    CharonMPSGraphOperationKindRint,
    // The three questions about a value that are not arithmetic, and the three that are a predicate:
    // isNaN, isFinite and isInfinite are the three of them, and they are the three whose result is a
    // boolean rather than a number. Measured on this host's own MPSGraph over a rank-3 float32
    // operand: a comparison, a less-than and isNaN answer MPSDataTypeBool (0x80000008, one byte an
    // element), and logicalAND, not and signbit answer the operand's own type. Both are in
    // facts/MetalPerformanceShadersGraph/Core.md.
    CharonMPSGraphOperationKindIsNaN,
    CharonMPSGraphOperationKindIsFinite,
    CharonMPSGraphOperationKindIsInfinite,
    CharonMPSGraphOperationKindLogicalNot,
    // The predicates over two operands. The same measurement as the three above: all six are a
    // boolean.
    CharonMPSGraphOperationKindEqual,
    CharonMPSGraphOperationKindNotEqual,
    CharonMPSGraphOperationKindLessThan,
    CharonMPSGraphOperationKindLessThanOrEqualTo,
    CharonMPSGraphOperationKindGreaterThan,
    CharonMPSGraphOperationKindGreaterThanOrEqualTo,
    // The logical family over two operands, which answers the operand's own type and not a boolean -
    // the same measurement as logicalAND above.
    CharonMPSGraphOperationKindLogicalAnd,
    CharonMPSGraphOperationKindLogicalOr,
    CharonMPSGraphOperationKindLogicalNand,
    CharonMPSGraphOperationKindLogicalNor,
    CharonMPSGraphOperationKindLogicalXor,
    CharonMPSGraphOperationKindLogicalXnor,
    // The two arithmetic operations that are not IEEE, and the three that take a third operand.
    CharonMPSGraphOperationKindModulo,
    CharonMPSGraphOperationKindFloorModulo,
    CharonMPSGraphOperationKindPower,
    CharonMPSGraphOperationKindAtan2,
    CharonMPSGraphOperationKindDivisionNoNaN,
    CharonMPSGraphOperationKindSelect,
    CharonMPSGraphOperationKindClamp3,
    // The activations, and the two of the four that are their own gradient: a ReLU gradient reads the
    // source as well as the incoming gradient, and so does a sigmoid's.
    CharonMPSGraphOperationKindReLU,
    CharonMPSGraphOperationKindReLUGradient,
    CharonMPSGraphOperationKindSigmoid,
    CharonMPSGraphOperationKindSigmoidGradient,
    // The reduction family, which is walked by its own function rather than element by element: a
    // reduction writes one element from many, so the loop is over the operand and not over the result.
    // These eight arrived with the framework in 14.0; the two that arrived in 15.0 and the four that
    // arrived in 15.3 are in the objects of those releases.
    CharonMPSGraphOperationKindReductionSum,
    CharonMPSGraphOperationKindReductionProduct,
    CharonMPSGraphOperationKindReductionMaximum,
    CharonMPSGraphOperationKindReductionMinimum,
    CharonMPSGraphOperationKindReductionMaximumPropagateNaN,
    CharonMPSGraphOperationKindReductionMinimumPropagateNaN,
    CharonMPSGraphOperationKindReductionMean,
    CharonMPSGraphOperationKindReductionVariance,
    // The two argument reductions of 15.0 and the two truth folds of 15.3. An argument reduction is the
    // maximum or the minimum that answers its index rather than its value, and a truth fold answers
    // whether any element of the reduced set is nonzero, or whether every one of them is. The walk over
    // all four is the walk over the family above, and it is told which one it is by the operation's own
    // parameters rather than by which of these it is - see the seam on MPSGraph below.
    CharonMPSGraphOperationKindReductionArgMaximum,
    CharonMPSGraphOperationKindReductionArgMinimum,
    CharonMPSGraphOperationKindReductionAnd,
    CharonMPSGraphOperationKindReductionOr,
    // The cumulative family of 16.0, which is the fold above walked along an axis instead of across a set:
    // the result is the operand's own shape, and each element holds the fold of everything before it or
    // everything after it, in one direction or the other. Which of the four it is, which direction, and
    // whether the element at a position is in its own answer are all parameters of the operation, for the
    // same reason the reduction family's are.
    CharonMPSGraphOperationKindTranspose,
    CharonMPSGraphOperationKindSqueeze,
    CharonMPSGraphOperationKindExpandDims,
    CharonMPSGraphOperationKindFlatten2D,
    CharonMPSGraphOperationKindBroadcast,
    CharonMPSGraphOperationKindReverse,
    CharonMPSGraphOperationKindCumulativeSum,
    CharonMPSGraphOperationKindCumulativeProduct,
    CharonMPSGraphOperationKindCumulativeMaximum,
    CharonMPSGraphOperationKindCumulativeMinimum
};

@class MPSGraph;
@class MPSGraphTensor;
@class MPSGraphOperation;
@class MPSGraphDevice;
@class MPSGraphExecutable;
@class MPSGraphExecutableExecutionDescriptor;

// Four names of the 26.2 surface are in no 16.4 header - MPSGraphObject among them - and they are
// transcribed in ../MetalPerformanceShaders/CharonMPS26.h, which is where the whole set lives now, so
// they are not declared a second time here. That header leaves them out on a host whose own SDK
// already declares them, and keeps them where the SDK the port builds against does not.

#import "../MetalPerformanceShaders/CharonMPS26.h"

@interface MPSGraphObject (CharonMPSGraph)
@end

@interface MPSGraphExecutable (CharonMPSGraph)
- (instancetype)initWithGraph:(MPSGraph *)graph
                        device:(MPSGraphDevice *)device
                        feeds:(NSDictionary *)feeds
                 targetTensors:(NSArray<MPSGraphTensor *> *)targetTensors
              targetOperations:(NSArray<MPSGraphOperation *> *)targetOperations
           executableDescriptor:(MPSGraphExecutableExecutionDescriptor *)executableDescriptor;
- (MPSGraphDevice *)device;
@end

@interface MPSGraphShapedType (CharonMPSGraph)
- (NSUInteger)rank;
- (NSUInteger)elementCount;
- (NSUInteger)offset;
- (BOOL)isEmpty;
@end

@interface MPSGraphTensorData (CharonMPSGraph)
- (instancetype)initWithDevice:(MPSGraphDevice *)device
                   elementCount:(NSUInteger)elementCount
                          shape:(NSArray<NSNumber *> *)shape
                       dataType:(MPSDataType)dataType;
- (id<MTLBuffer>)charon_mps_buffer;
- (void *)charon_mps_bytes;
- (NSUInteger)charon_mps_elementCount;
@end

@interface MPSGraphTensor (CharonMPSGraph)
- (NSUInteger)charon_mps_index;
- (void)charon_mps_setShape:(NSArray<NSNumber *> *)shape;
- (NSUInteger)charon_mps_elementCount;
- (BOOL)isEqualToTensor:(MPSGraphTensor *)tensor;
- (instancetype)initWithShape:(NSArray<NSNumber *> *)shape
                    dataType:(MPSDataType)dataType
                   operation:(MPSGraphOperation *)operation
                       index:(NSUInteger)index;
@end

@interface MPSGraphOperation (CharonMPSGraph)
- (instancetype)initWithGraph:(MPSGraph *)graph
                         kind:(CharonMPSGraphOperationKind)kind
                         name:(NSString *)name
                        inputs:(NSArray<MPSGraphTensor *> *)inputs
                       outputs:(NSArray<MPSGraphTensor *> *)outputs;
- (CharonMPSGraphOperationKind)charon_mps_kind;
- (NSDictionary *)charon_mps_parameters;
- (void)charon_mps_setParameters:(NSDictionary *)parameters;
@end

@interface MPSGraphOperation (CharonMPSGraphWiring)
// The output tensors and the parameters are set by the graph as it builds an operation, because they are
// its business rather than a caller's: an operation is made with its inputs and grows its outputs.
- (void)charon_mps_setOutputTensors:(NSArray<MPSGraphTensor *> *)outputs;
@end

@interface MPSGraph (CharonMPSGraph)
// The operation of a kind over the given operands, which is what every factory method in the family
// headers ends up calling.
- (MPSGraphTensor *)charon_mps_operation:(CharonMPSGraphOperationKind)kind
                                inputs:(NSArray<MPSGraphTensor *> *)inputs
                            parameters:(NSDictionary *)parameters
                                   name:(NSString *)name;
// A reduction over a set of axes of one operand: the result's shape is the operand's with those axes
// taken out, which is what every member of the family produces. This is the seam every release's
// reduction factory goes through, and it is deliberately the only one: the 14.0 object that defines it
// names no operation of any later release, because everything the walk needs to know comes in
// `parameters` - the combination to fold with, whether a NaN latches, whether the answer is an index
// rather than a value, and the data type the result is stored as. A release's own factory fills those
// in and names only its own methods.
- (MPSGraphTensor *)charon_mps_reduction:(CharonMPSGraphOperationKind)kind
                                    axes:(NSArray<NSNumber *> *)axes
                                  tensor:(MPSGraphTensor *)tensor
                             parameters:(NSDictionary *)parameters
                                    name:(NSString *)name;
// A GATHER: an operation whose result is the operand's elements in some other order or extent, and whose
// whole behaviour is which source axis each result axis comes from and whether that axis is reversed or
// wrapped. That is the walk over a reshape, a squeeze, an expanded dimension, a flatten, a broadcast, a
// reverse and a transpose, and it is asked of the operation's own parameters - which transformation
// (@"gather"), the parameter of it the caller wrote down (@"gatherAxis", @"gatherAxes",
// @"gatherPermutation") or which of the operation's inputs carries it instead (@"gatherOperand"), and the
// result's shape (@"shape") - so every release's factory of the family fills those in and names only its own
// methods, and the result's shape is derived by the walk and put on the output tensor before anything is
// allocated for it - which is what lets a shape the caller FEEDS be one of them.
// A squeeze and an expanded dimension and a flatten are the same gather with the axes left alone:
// measured on this host's own MPSGraph, all three answer the operand's own bytes in the operand's own order.
- (MPSGraphTensor *)charon_mps_gather:(CharonMPSGraphOperationKind)kind
                                tensor:(MPSGraphTensor *)tensor
                           parameters:(NSDictionary *)parameters
                                  name:(NSString *)name;
// The same over a parameter the caller feeds at run time rather than writing down - an axis, a set of axes
// or a shape - which becomes the operation's second input and is read by the walk when the graph runs.
- (MPSGraphTensor *)charon_mps_gather:(CharonMPSGraphOperationKind)kind
                                tensor:(MPSGraphTensor *)tensor
                         fedParameter:(MPSGraphTensor *)fedParameter
                           parameters:(NSDictionary *)parameters
                                  name:(NSString *)name;
// A cumulative operation along one axis of one operand: the result is the operand's own shape, and each
// element holds a fold of the elements on one side of it. The axis is the caller's, so it is normalised
// here - negative counted from the end of the rank, and an axis outside it refused the way the reduction
// family's is - and everything else the walk needs comes in `parameters`: which fold (@"scanCombination",
// one of the four the reduction table already holds), whether an element is in its own answer
// (@"scanExclusive") and which way the walk goes (@"scanReverse"). A 16.0 factory fills those in and names
// only its own methods.
- (MPSGraphTensor *)charon_mps_scan:(CharonMPSGraphOperationKind)kind
                               axis:(NSInteger)axis
                             tensor:(MPSGraphTensor *)tensor
                        combination:(NSString *)combination
                           exclusive:(BOOL)exclusive
                             reverse:(BOOL)reverse
                                name:(NSString *)name;
// The same over an axis the caller feeds at run time rather than writing down, which is the other half of
// every one of the four operations of 16.0. The axis tensor is the operation's second input, and the walk
// reads its one element; a floating point axis is refused here, because the release cannot build the graph
// at all over one (measured: its own compiler refuses the operand and the process goes down with
// "failed assertion", MPSGraphExecutable.mm:4419) and there is no answer to reproduce.
- (MPSGraphTensor *)charon_mps_scan:(CharonMPSGraphOperationKind)kind
                         axisTensor:(MPSGraphTensor *)axisTensor
                             tensor:(MPSGraphTensor *)tensor
                        combination:(NSString *)combination
                           exclusive:(BOOL)exclusive
                             reverse:(BOOL)reverse
                                name:(NSString *)name;
// The operation that fills a tensor's value, called by the interpreter for each in turn.
- (void)charon_mps_runOperation:(MPSGraphOperation *)operation
                          values:(NSMutableDictionary *)values;
- (MPSGraphDevice *)charon_mps_device;
- (MPSGraphOperation *)charon_mps_addOperationOfKind:(CharonMPSGraphOperationKind)kind
                                                name:(NSString *)name
                                              inputs:(NSArray<MPSGraphTensor *> *)inputs
                                             outputs:(NSArray<MPSGraphTensor *> *)outputs
                                           parameters:(NSDictionary *)parameters;
@end

#endif /* MPSGRAPH_CHARON_H */
