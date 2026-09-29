// CharonMPSGraph.h — what this framework's own files share.
//
// A graph is a description of work and a tensor is a description of a result; the arithmetic happens
// when the graph runs, over the host memory behind an MTLBuffer, exactly as the matrix kernels in
// ../MetalPerformanceShaders do (facts/MetalPerformanceShaders/Matrix.md). Nothing here needs a
// texture, so none of it waits on the pixel formats.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>

#include <math.h>
#include <string.h>

// The number of elements a tensor of a shape holds, and the byte offset of one element from the
// tensor's data. A shape is an array of dimensions, row major, which is the layout MPSGraph's own
// headers use and the one the results come back in.
static inline NSUInteger CharonMPSGraphElementCount(NSArray<NSNumber *> *shape)
{
    NSUInteger count = 1;
    for (NSNumber *dimension in shape)
        count *= (NSUInteger)MAX((NSInteger)1, dimension.integerValue);
    return count;
}

static inline size_t CharonMPSGraphElementSize(MPSDataType type)
{
    return MPSSizeofMPSDataType(type);
}

// An element read and written through the data type it is stored as: the matrix framework's own
// CharonMPS.h already defines that for the eight element types, and including it here means both
// families agree on what an MPSDataType means instead of saying it twice.
#import "../MetalPerformanceShaders/CharonMPS.h"
