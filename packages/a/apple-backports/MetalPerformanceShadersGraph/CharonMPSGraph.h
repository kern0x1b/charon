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
    CharonMPSGraphOperationKindIdentity
};

@class MPSGraph;
@class MPSGraphTensor;
@class MPSGraphOperation;
@class MPSGraphDevice;
@class MPSGraphExecutable;
@class MPSGraphExecutableExecutionDescriptor;

// The SDK this package compiles against is the iPhoneOS 16.4 one, whose MetalPerformanceShadersGraph
// headers predate four names of the 26.2 surface: MPSGraphObject, which arrived in iOS 17 and which
// every class of that surface descends from there while 16.4 has them descending from NSObject, and
// MPSGraphFFTDescriptor, MPSGraphImToColOpDescriptor and MPSGraphExecutableSerializationDescriptor.
// They are declared here and implemented in this library, so a graph's objects have the root the 26.2
// headers give them rather than the one the older SDK names; see
// facts/MetalPerformanceShadersGraph/Core.md.
//
// The declarations are for an SDK that lacks them, which is what the package builds against, and are
// left out on a host whose own SDK already has them - where redeclaring would be a duplicate, and
// where the host's own classes are the ones a comparison must be against.
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 260000
@interface MPSGraphObject : NSObject
@end

@interface MPSGraphFFTDescriptor : NSObject
@end

@interface MPSGraphImToColOpDescriptor : NSObject
@end

@interface MPSGraphExecutableSerializationDescriptor : NSObject
@end
#endif

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
