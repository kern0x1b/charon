// What the port's MLCompute is made of, and what only it needs.
//
// The declarations an application compiles against are Apple's own, read from the SDK this port builds
// with: <MLCompute/MLCompute.h> gives the fifty-five classes, their selectors, their properties and the
// values of their enumerations exactly as the newest SDK spells them, and nothing here repeats them. A
// backport that retyped them would be a second, drifting copy of an interface Apple can change.
//
// What this header adds is the storage the implementations keep and the few helpers more than one of
// them needs. Everything in it is named Charon*, which is what tells the gate that a symbol is the port's
// own and neither an API it carries nor a class the release has (modules/apple/backports.lua,
// internal_symbol), so the registry is never asked about it and no stub is written for it.

#import <Foundation/Foundation.h>
#import <MLCompute/MLCompute.h>

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// The number of dimensions a tensor of this port has, and the number MLCompute reports for
// +[MLCTensorDescriptor maxTensorDimensions] (measured on the host, facts/MLCompute/Values.md).
#define CHARON_MLC_MAX_DIMENSIONS 4

// The width in bytes of one element of a data type, or 0 for a data type this port has no storage for.
// The table is the host's own, read by asking for a descriptor of each type and looking at the size it
// answers (measured: 4, 2, 1, 8, 4, 1, 1 bytes for float32, float16, boolean, int64, int32, int8, uint8;
// nil for MLCDataTypeInvalid, for 2 and for MLCDataTypeCount, and one byte for the two values between
// the enumerated ones that are neither). A data type with no size has no tensor: the factories answer nil
// where the host answers nil, and the engine refuses to compute with one.
NSUInteger CharonMLCWidthOfDataType(MLCDataType dataType);

// The number of elements a shape holds, 0 for a shape with a zero or a nil in it.
NSUInteger CharonMLCElementCount(NSArray<NSNumber *> *shape);

// The shape array of a tensor of this shape, in the order MLCompute reports: the batch dimension first
// and the width last, each one the fastest-varying of the one before it reversed (measured: a descriptor
// made with +descriptorWithWidth:height:featureChannelCount:batchSize: of 5, 6, 7 and 8 answers
// 8, 7, 6, 5). The stride is in bytes and is the width of a data type times the product of the
// dimensions to its right.
NSArray<NSNumber *> *CharonMLCStrideOfShape(NSArray<NSNumber *> *shape, MLCDataType dataType);

// The number every created tensor and layer counts on, in the order the host counts: the first MLCTensor
// and the first MLCLayer of a process are 0 and every later one is one higher (measured).
NSUInteger CharonMLCNextTensorID(void);
NSUInteger CharonMLCNextLayerID(void);
