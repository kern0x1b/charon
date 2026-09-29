// MPSGraphExecutable, from the header of MPSGraphExecutable.h in the SDK of iOS 16.4: a compiled graph
// and the ways to run it. An executable of this port is the graph itself, because the work is a walk
// over the operations and there is nothing to compile ahead of time.

#import "CharonMPSGraph.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSGraphExecutable {
    MPSGraph *_graph;
    MPSGraphDevice *_device;
    NSDictionary *_feeds;
    NSArray<MPSGraphTensor *> *_targetTensors;
    NSArray<MPSGraphOperation *> *_targetOperations;
    MPSGraphExecutableExecutionDescriptor *_executionDescriptor;
    BOOL _append;
    MPSGraphOptions _options;
}

- (instancetype)initWithGraph:(MPSGraph *)graph
                        device:(MPSGraphDevice *)device
                        feeds:(NSDictionary *)feeds
                 targetTensors:(NSArray<MPSGraphTensor *> *)targetTensors
              targetOperations:(NSArray<MPSGraphOperation *> *)targetOperations
           executableDescriptor:(MPSGraphExecutableExecutionDescriptor *)executableDescriptor
{
    if ((self = [super init])) {
        _graph = graph;
        _device = device;
        _feeds = [feeds copy];
        _targetTensors = [targetTensors copy];
        _targetOperations = [targetOperations copy];
        _executionDescriptor = executableDescriptor;
        _append = NO;
        _options = MPSGraphOptionsDefault;
    }
    return self;
}

- (NSArray<MPSGraphTensor *> *)feedTensors
{
    return _feeds.allKeys;
}

- (NSArray<MPSGraphTensor *> *)targetTensors
{
    return _targetTensors;
}

- (MPSGraphDevice *)device
{
    return _device;
}

- (MPSGraphOptions)options
{
    return _options;
}

- (void)setOptions:(MPSGraphOptions)options
{
    _options = options;
}

- (BOOL)append
{
    return _append;
}

- (void)setAppend:(BOOL)append
{
    _append = append;
}

- (NSArray<MPSGraphTensorData *> *)runWithMTLCommandQueue:(id<MTLCommandQueue>)commandQueue
                                            inputsArray:(NSArray<MPSGraphTensorData *> *)inputsArray
                                           resultsArray:(NSArray<MPSGraphTensorData *> *)resultsArray
                                    executionDescriptor:(MPSGraphExecutableExecutionDescriptor *)executionDescriptor
{
    // The feeds are the graph's own, overlaid with the inputs given here, which is how a caller replaces
    // one placeholder's value between two runs of the same executable. The results are written into the
    // tensor data the caller allocated, so the answer is in a buffer the caller owns.
    NSMutableDictionary *feeds = [_feeds mutableCopy];
    // The inputs pair with the feed tensors in the order the placeholders were added to the graph, which
    // is the order the caller passed the inputs in. A dictionary's own key order is arbitrary, and
    // pairing by it gave the second operand to the first tensor, which every non-commutative
    // operation then read backwards.
    NSMutableArray<MPSGraphTensor *> *feedTensors = [NSMutableArray array];
    for (MPSGraphTensor *placeholder in _graph.placeholderTensors)
        if (_feeds[placeholder])
            [feedTensors addObject:placeholder];
    for (MPSGraphTensor *tensor in _feeds.allKeys)
        if (![feedTensors containsObject:tensor])
            [feedTensors addObject:tensor];
    for (NSUInteger i = 0; i < inputsArray.count && i < feedTensors.count; i++)
        feeds[feedTensors[i]] = inputsArray[i];
    NSDictionary *results = [_graph runWithFeeds:feeds
                                    targetTensors:_targetTensors
                                 targetOperations:_targetOperations];
    NSMutableArray *returned = [NSMutableArray array];
    for (NSUInteger i = 0; i < _targetTensors.count; i++) {
        MPSGraphTensorData *computed = results[_targetTensors[i]];
        MPSGraphTensorData *destination = i < resultsArray.count ? resultsArray[i] : computed;
        if (computed && destination && computed != destination) {
            void *to = [destination charon_mps_bytes];
            void *from = [computed charon_mps_bytes];
            size_t n = [computed charon_mps_elementCount] * MPSSizeofMPSDataType(computed.dataType);
            if (to && from)
                memcpy(to, from, n);
            else
                CharonMPSGraphRefuse(@"MPSGraph: a result could not be copied into the destination, so the destination is left as it was");
        }
        if (destination)
            [returned addObject:destination];
    }
    (void)commandQueue;
    (void)executionDescriptor;
    return returned;
}

@end
