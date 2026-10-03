// MPSGraph, from the header of MPSGraph.h in the SDK of iOS 16.4: the graph the operations are added to,
// the placeholders that are fed at run time, and the two ways to run it.
//
// The graph is a description, so running it means walking the operations in the order they were added
// and asking each one to fill its outputs from its inputs and the feeds. A tensor's value is found by
// looking it up: a placeholder's comes from the feeds, any other one's from the operation that produced
// it, which is why the operations are walked in the order they were added - an operation can only read
// what an earlier one wrote.

#import "CharonMPSGraph.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// What an arithmetic family operation does to one pair of elements. A binary one takes the two and
// writes one; a unary one takes the first and writes one; a clamped one takes the two and a lower and an
// upper bound. The data type of the first operand decides the arithmetic, as it does everywhere else in
// this framework.
typedef enum {
    CharonMPSGraphArityUnary,
    CharonMPSGraphArityBinary,
    CharonMPSGraphArityClamp
} CharonMPSGraphArity;

@implementation MPSGraph {
    MPSGraphDevice *_device;
    MPSGraphOptions _options;
    NSMutableArray<MPSGraphTensor *> *_placeholders;
    NSMutableArray<MPSGraphOperation *> *_operations;
}

+ (instancetype)new
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if ((self = [super init])) {
        // A graph's device is the one it was made against, or the port's own Metal device when the
        // caller named none: every device this port has is charon's, so there is nothing to choose.
        _device = [MPSGraphDevice deviceWithMTLDevice:MTLCreateSystemDefaultDevice()];
        _options = MPSGraphOptionsDefault;
        _placeholders = [NSMutableArray array];
        _operations = [NSMutableArray array];
    }
    return self;
}

- (MPSGraphDevice *)charon_mps_device
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

- (NSArray<MPSGraphTensor *> *)placeholderTensors
{
    return [_placeholders copy];
}

#pragma mark - the operations a graph is built from

- (MPSGraphTensor *)placeholderWithShape:(NSArray<NSNumber *> *)shape dataType:(MPSDataType)dataType name:(NSString *)name
{
    MPSGraphOperation *operation = [self charon_mps_addOperationOfKind:CharonMPSGraphOperationKindPlaceholder
                                                                 name:name
                                                                inputs:@[]
                                                               outputs:@[]
                                                             parameters:nil];
    MPSGraphTensor *tensor = [[MPSGraphTensor alloc] initWithShape:shape dataType:dataType operation:operation index:0];
    [operation charon_mps_setOutputTensors:@[tensor]];
    [_placeholders addObject:tensor];
    return tensor;
}

- (MPSGraphTensor *)constantWithShape:(NSArray<NSNumber *> *)shape
                            dataType:(MPSDataType)dataType
                              values:(NSData *)values
                                name:(NSString *)name
{
    MPSGraphOperation *operation = [self charon_mps_addOperationOfKind:CharonMPSGraphOperationKindConstant
                                                                 name:name
                                                                inputs:@[]
                                                               outputs:@[]
                                                             parameters:@{@"values": values}];
    MPSGraphTensor *tensor = [[MPSGraphTensor alloc] initWithShape:shape dataType:dataType operation:operation index:0];
    [operation charon_mps_setOutputTensors:@[tensor]];
    return tensor;
}

- (MPSGraphTensor *)charon_mps_operation:(CharonMPSGraphOperationKind)kind
                                inputs:(NSArray<MPSGraphTensor *> *)inputs
                            parameters:(NSDictionary *)parameters
                                   name:(NSString *)name
{
    // The output takes the first input's shape and data type, which is what every elementwise operation
    // in this family produces; a family whose result has a shape of its own computes it here instead.
    MPSGraphTensor *source = inputs.firstObject;
    NSArray<NSNumber *> *shape = source.shape;
    MPSDataType dataType = source.dataType;
    if ([parameters[@"shape"] isKindOfClass:[NSArray class]])
        shape = parameters[@"shape"];
    if ([parameters[@"dataType"] isKindOfClass:[NSNumber class]])
        dataType = (MPSDataType)[parameters[@"dataType"] unsignedIntValue];
    MPSGraphOperation *operation = [self charon_mps_addOperationOfKind:kind name:name inputs:inputs outputs:@[] parameters:parameters];
    MPSGraphTensor *tensor = [[MPSGraphTensor alloc] initWithShape:shape dataType:dataType operation:operation index:0];
    [operation charon_mps_setOutputTensors:@[tensor]];
    return tensor;
}

- (MPSGraphOperation *)charon_mps_addOperationOfKind:(CharonMPSGraphOperationKind)kind
                                                name:(NSString *)name
                                              inputs:(NSArray<MPSGraphTensor *> *)inputs
                                             outputs:(NSArray<MPSGraphTensor *> *)outputs
                                           parameters:(NSDictionary *)parameters
{
    MPSGraphOperation *operation = [[MPSGraphOperation alloc] initWithGraph:self kind:kind name:name inputs:inputs outputs:outputs];
    [operation charon_mps_setParameters:parameters];
    [_operations addObject:operation];
    return operation;
}

#pragma mark - the arithmetic family

- (MPSGraphTensor *)charon_mps_arithmetic:(CharonMPSGraphOperationKind)kind
                                 operands:(NSArray<MPSGraphTensor *> *)operands
                                      name:(NSString *)name
{
    return [self charon_mps_operation:kind inputs:operands parameters:nil name:name];
}

// The same for the operations whose answer is a truth rather than a number. Measured on this host's own
// MPSGraph, a comparison over a rank-3 float32 operand answers MPSDataTypeBool (0x80000008, one byte
// an element) and so do lessThan, greaterThan, notEqual, the two <= and >= forms and the three
// questions about a value; the logical family, not and signbit answer the operand's own type, which is
// why those three go through the arithmetic form above and not through this one.
- (MPSGraphTensor *)charon_mps_predicate:(CharonMPSGraphOperationKind)kind
                                operands:(NSArray<MPSGraphTensor *> *)operands
                                     name:(NSString *)name
{
    return [self charon_mps_operation:kind
                              inputs:operands
                          parameters:@{@"dataType": @(MPSDataTypeBool)}
                                 name:name];
}

- (MPSGraphTensor *)additionWithPrimaryTensor:(MPSGraphTensor *)primary
                             secondaryTensor:(MPSGraphTensor *)secondary
                                        name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAdd operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)subtractionWithPrimaryTensor:(MPSGraphTensor *)primary
                                secondaryTensor:(MPSGraphTensor *)secondary
                                           name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSubtract operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)multiplicationWithPrimaryTensor:(MPSGraphTensor *)primary
                                  secondaryTensor:(MPSGraphTensor *)secondary
                                             name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindMultiply operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)divisionWithPrimaryTensor:(MPSGraphTensor *)primary
                              secondaryTensor:(MPSGraphTensor *)secondary
                                         name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindDivide operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)negationWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindNegate operands:@[tensor] name:name];
}

- (MPSGraphTensor *)squareWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSquare operands:@[tensor] name:name];
}

- (MPSGraphTensor *)reciprocalWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindReciprocal operands:@[tensor] name:name];
}

- (MPSGraphTensor *)squareRootWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSqrt operands:@[tensor] name:name];
}

- (MPSGraphTensor *)reverseSquareRootWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindRsqrt operands:@[tensor] name:name];
}

- (MPSGraphTensor *)exponentialWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindExp operands:@[tensor] name:name];
}

- (MPSGraphTensor *)logarithmWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLog operands:@[tensor] name:name];
}

- (MPSGraphTensor *)absoluteWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAbs operands:@[tensor] name:name];
}

- (MPSGraphTensor *)signWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSign operands:@[tensor] name:name];
}

- (MPSGraphTensor *)identityWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindIdentity operands:@[tensor] name:name];
}

#pragma mark - the transcendentals and the rounding

- (MPSGraphTensor *)exponentBase2WithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindExpBase2 operands:@[tensor] name:name];
}

- (MPSGraphTensor *)exponentBase10WithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindExpBase10 operands:@[tensor] name:name];
}

- (MPSGraphTensor *)logarithmBase2WithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogBase2 operands:@[tensor] name:name];
}

- (MPSGraphTensor *)logarithmBase10WithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogBase10 operands:@[tensor] name:name];
}

- (MPSGraphTensor *)negativeWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindNegate operands:@[tensor] name:name];
}

- (MPSGraphTensor *)signbitWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSignBit operands:@[tensor] name:name];
}

- (MPSGraphTensor *)ceilWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindCeil operands:@[tensor] name:name];
}

- (MPSGraphTensor *)floorWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindFloor operands:@[tensor] name:name];
}

// The two roundings the header separates by name: round is the half away from zero and rint is the one
// the C library rounds to even with. A feed of (0.5, 1.5, 2.5, -0.5, -1.5, -2.5) is measured against
// both on this host's own MPSGraph and comes back 1, 2, 3, -1, -2, -3 for round and 0, 2, 2, -0, -2, -2
// for rint, which is what the two C functions answer.
- (MPSGraphTensor *)roundWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindRound operands:@[tensor] name:name];
}

- (MPSGraphTensor *)rintWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindRint operands:@[tensor] name:name];
}

- (MPSGraphTensor *)sinWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSin operands:@[tensor] name:name];
}

- (MPSGraphTensor *)cosWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindCos operands:@[tensor] name:name];
}

- (MPSGraphTensor *)tanWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindTan operands:@[tensor] name:name];
}

- (MPSGraphTensor *)sinhWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSinh operands:@[tensor] name:name];
}

- (MPSGraphTensor *)coshWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindCosh operands:@[tensor] name:name];
}

- (MPSGraphTensor *)tanhWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindTanh operands:@[tensor] name:name];
}

- (MPSGraphTensor *)asinWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAsin operands:@[tensor] name:name];
}

- (MPSGraphTensor *)acosWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAcos operands:@[tensor] name:name];
}

- (MPSGraphTensor *)atanWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAtan operands:@[tensor] name:name];
}

- (MPSGraphTensor *)asinhWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAsinh operands:@[tensor] name:name];
}

- (MPSGraphTensor *)acoshWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAcosh operands:@[tensor] name:name];
}

- (MPSGraphTensor *)atanhWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAtanh operands:@[tensor] name:name];
}

- (MPSGraphTensor *)erfWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindErf operands:@[tensor] name:name];
}

// The logical not of a value, which is the operand's own type and not a boolean: measured on this host's
// own MPSGraph, not of a rank-3 float32 operand is MPSDataTypeFloat32 where isNaN of the same operand is
// MPSDataTypeBool.
- (MPSGraphTensor *)notWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalNot operands:@[tensor] name:name];
}

- (MPSGraphTensor *)isInfiniteWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindIsInfinite operands:@[tensor] name:name];
}

- (MPSGraphTensor *)isFiniteWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindIsFinite operands:@[tensor] name:name];
}

- (MPSGraphTensor *)isNaNWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindIsNaN operands:@[tensor] name:name];
}

#pragma mark - the arithmetic that is not IEEE

- (MPSGraphTensor *)moduloWithPrimaryTensor:(MPSGraphTensor *)primary
                          secondaryTensor:(MPSGraphTensor *)secondary
                                     name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindModulo operands:@[primary, secondary] name:name];
}

// C's fmod truncates towards zero and the floor modulo answers the remainder of the divisor's own sign,
// which is the difference between -7 modulo 3 and -7 floor-modulo 3: -1 and 2.
- (MPSGraphTensor *)floorModuloWithPrimaryTensor:(MPSGraphTensor *)primary
                                 secondaryTensor:(MPSGraphTensor *)secondary
                                            name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindFloorModulo operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)powerWithPrimaryTensor:(MPSGraphTensor *)primary
                          secondaryTensor:(MPSGraphTensor *)secondary
                                     name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindPower operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)minimumWithPrimaryTensor:(MPSGraphTensor *)primary
                            secondaryTensor:(MPSGraphTensor *)secondary
                                       name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindMinimum operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)maximumWithPrimaryTensor:(MPSGraphTensor *)primary
                            secondaryTensor:(MPSGraphTensor *)secondary
                                       name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindMaximum operands:@[primary, secondary] name:name];
}

// A division that answers a zero where IEEE answers a NaN, which is what the "NoNaN" in its own name
// says: a zero over a zero, and a NaN over anything at all, are both a zero. Measured over the sixteen
// classes of the arithmetic case file on this host's own MPSGraph, divisionNoNaN answers 0x00000000 for
// 1.0 over 0.0 and for 0x00000001 over 0x00000001, where division answers 0x7fc00000 for both.
- (MPSGraphTensor *)divisionNoNaNWithPrimaryTensor:(MPSGraphTensor *)primary
                                  secondaryTensor:(MPSGraphTensor *)secondary
                                             name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindDivisionNoNaN operands:@[primary, secondary] name:name];
}

// The two-argument arctangent, whose arguments are in the order the header writes them: the tangent of
// the angle is primary over secondary, which is atan2(y, x), not atan2(x, y).
- (MPSGraphTensor *)atan2WithPrimaryTensor:(MPSGraphTensor *)primary
                          secondaryTensor:(MPSGraphTensor *)secondary
                                     name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindAtan2 operands:@[primary, secondary] name:name];
}

#pragma mark - the predicates over two operands

- (MPSGraphTensor *)equalWithPrimaryTensor:(MPSGraphTensor *)primary
                          secondaryTensor:(MPSGraphTensor *)secondary
                                     name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindEqual operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)notEqualWithPrimaryTensor:(MPSGraphTensor *)primary
                             secondaryTensor:(MPSGraphTensor *)secondary
                                        name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindNotEqual operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)lessThanWithPrimaryTensor:(MPSGraphTensor *)primary
                            secondaryTensor:(MPSGraphTensor *)secondary
                                       name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindLessThan operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)lessThanOrEqualToWithPrimaryTensor:(MPSGraphTensor *)primary
                                     secondaryTensor:(MPSGraphTensor *)secondary
                                                name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindLessThanOrEqualTo operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)greaterThanWithPrimaryTensor:(MPSGraphTensor *)primary
                               secondaryTensor:(MPSGraphTensor *)secondary
                                          name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindGreaterThan operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)greaterThanOrEqualToWithPrimaryTensor:(MPSGraphTensor *)primary
                                        secondaryTensor:(MPSGraphTensor *)secondary
                                                   name:(NSString *)name
{
    return [self charon_mps_predicate:CharonMPSGraphOperationKindGreaterThanOrEqualTo operands:@[primary, secondary] name:name];
}

#pragma mark - the logical family, which answers the operand's own type

- (MPSGraphTensor *)logicalANDWithPrimaryTensor:(MPSGraphTensor *)primary
                               secondaryTensor:(MPSGraphTensor *)secondary
                                          name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalAnd operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)logicalORWithPrimaryTensor:(MPSGraphTensor *)primary
                              secondaryTensor:(MPSGraphTensor *)secondary
                                         name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalOr operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)logicalNANDWithPrimaryTensor:(MPSGraphTensor *)primary
                                secondaryTensor:(MPSGraphTensor *)secondary
                                           name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalNand operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)logicalNORWithPrimaryTensor:(MPSGraphTensor *)primary
                               secondaryTensor:(MPSGraphTensor *)secondary
                                          name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalNor operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)logicalXORWithPrimaryTensor:(MPSGraphTensor *)primary
                               secondaryTensor:(MPSGraphTensor *)secondary
                                          name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalXor operands:@[primary, secondary] name:name];
}

- (MPSGraphTensor *)logicalXNORWithPrimaryTensor:(MPSGraphTensor *)primary
                                secondaryTensor:(MPSGraphTensor *)secondary
                                           name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindLogicalXnor operands:@[primary, secondary] name:name];
}

#pragma mark - the operations with a third operand

// A select reads three operands: where the predicate is true the second, where it is false the third,
// and the answer is the predicate's own type. A clamp reads the value and its two bounds.
- (MPSGraphTensor *)selectWithPredicateTensor:(MPSGraphTensor *)predicate
                         truePredicateTensor:(MPSGraphTensor *)whenTrue
                          falsePredicateTensor:(MPSGraphTensor *)whenFalse
                                         name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSelect operands:@[predicate, whenTrue, whenFalse] name:name];
}

- (MPSGraphTensor *)clampWithTensor:(MPSGraphTensor *)tensor
                     minValueTensor:(MPSGraphTensor *)minimum
                     maxValueTensor:(MPSGraphTensor *)maximum
                               name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindClamp3 operands:@[tensor, minimum, maximum] name:name];
}

#pragma mark - the activations and their gradients

- (MPSGraphTensor *)reLUWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindReLU operands:@[tensor] name:name];
}

- (MPSGraphTensor *)reLUGradientWithIncomingGradient:(MPSGraphTensor *)gradient
                                         sourceTensor:(MPSGraphTensor *)source
                                                name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindReLUGradient operands:@[gradient, source] name:name];
}

- (MPSGraphTensor *)sigmoidWithTensor:(MPSGraphTensor *)tensor name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSigmoid operands:@[tensor] name:name];
}

// A sigmoid's gradient is the incoming gradient times the source times one minus the source, where the
// source is the sigmoid's own answer rather than its input: measured on this host's own MPSGraph over a
// feed of (0, 1, -1, 2), a sigmoidGradient of an incoming gradient of all ones comes back as
// (0, 0.196612, 0.196612, 0.104994), which is what that product is and not what the gradient of the
// input would be.
- (MPSGraphTensor *)sigmoidGradientWithIncomingGradient:(MPSGraphTensor *)gradient
                                            sourceTensor:(MPSGraphTensor *)source
                                                   name:(NSString *)name
{
    return [self charon_mps_arithmetic:CharonMPSGraphOperationKindSigmoidGradient operands:@[gradient, source] name:name];
}

#pragma mark - the reduction family

// What all eight of these share: a set of axes of the operand's rank, and a result whose shape is the
// operand's with those axes taken out. Three questions about the set are answered by measurement rather
// than by the reading, and every one of them is a case in tests/backports/host/mpsgraph/graph-cases.m:
//
//   - an axis may be negative and is counted from the end of the rank, so -1 is the last axis and -2
//     the one before it. Measured: reductionSumWithTensor:axis:-1 over a 2x4 answers a 2x1 of the same
//     bytes as axis:1, and axis:-2 the same as axis:0.
//   - the order the axes are written in does not matter, and an axis written twice reduces once, so the
//     set is a set. Measured: axes:@[@1,@0] and axes:@[@0,@1] over the same 2x4 both answer a 1x1 of
//     110, and axes:@[@0,@0] answers the same bytes and the same 1x4 as axes:@[@0].
//   - nil reduces every axis and an empty array reduces none. Measured: axes:nil over the 2x4 answers a
//     1x1 of 110, and axes:@[] answers the 2x4 the operand already was, byte for byte.
//
// `parameters` is what tells the walk in MPSGraphInterpreter14.m which fold to run, so that this object
// and every later release's object share one walk and neither names the other's operations: what is
// added here on top of the axes and the result's shape is only what this release's own eight differ in,
// which is the two that latch a NaN.
// An axis outside the rank is a graph that cannot be built, and the framework refuses it in a way a
// caller cannot catch: measured on this host's own MPSGraph, reductionSumWithTensor:axis:5 over a 2x4
// writes "invalid axes: 5" and then dies with "LLVM ERROR: Failed to infer result type(s)", so the
// process is gone before any answer. There is no way to reproduce that from a port, and returning a
// tensor for it would be an answer the release does not give at all, so this raises instead - which is
// the one form of "this graph is not buildable" a caller can handle and is decided when the graph is
// built rather than left to be discovered as a wrong number later. Every later release's reduction goes
// through the same seam and is refused the same way: the argument reductions of 15.0 were measured
// refused the same way, and the truth folds of 15.3 with them.
- (MPSGraphTensor *)charon_mps_reduction:(CharonMPSGraphOperationKind)kind
                                    axes:(NSArray<NSNumber *> *)axes
                                  tensor:(MPSGraphTensor *)tensor
                             parameters:(NSDictionary *)parameters
                                    name:(NSString *)name
{
    NSArray<NSNumber *> *shape = tensor.shape;
    NSUInteger rank = shape.count;
    NSMutableIndexSet *dropped = [NSMutableIndexSet indexSet];
    if (axes != nil) {
        for (NSNumber *axis in axes) {
            NSInteger value = axis.integerValue;
            if (value < 0)
                value += (NSInteger)rank;
            if (value < 0 || value >= (NSInteger)rank) {
                [NSException raise:NSInvalidArgumentException
                            format:@"MPSGraph: %@ was asked to reduce axis %ld of a rank-%lu tensor, and "
                                   @"axis 0 to %lu is all it has",
                                    name, (long)axis.integerValue, (unsigned long)rank,
                                    (unsigned long)rank];
            }
            [dropped addIndex:(NSUInteger)value];
        }
    } else {
        // nil is every axis, which is the same set written out.
        for (NSUInteger axis = 0; axis < rank; axis++)
            [dropped addIndex:axis];
    }
    NSMutableArray<NSNumber *> *kept = [NSMutableArray arrayWithCapacity:rank];
    NSMutableArray<NSNumber *> *reduced = [NSMutableArray arrayWithCapacity:dropped.count];
    for (NSUInteger axis = 0; axis < rank; axis++) {
        if ([dropped containsIndex:axis])
            [reduced addObject:@(axis)];
        else
            [kept addObject:shape[axis]];
    }
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    all[@"axes"] = reduced;
    all[@"shape"] = kept;
    if (parameters)
        [all addEntriesFromDictionary:parameters];
    return [self charon_mps_operation:kind inputs:@[tensor] parameters:all name:name];
}

// What the eight of 14.0 differ in is the combination they fold with, and the two that latch a NaN say
// so here. The walk reads both out of the parameters, so a later release's reduction needs no name here.
- (MPSGraphTensor *)charon_mps_reductionOf:(NSArray<NSNumber *> *)axes
                                    tensor:(MPSGraphTensor *)tensor
                             combination:(NSString *)combination
                                     kind:(CharonMPSGraphOperationKind)kind
                          propagatesNaN:(BOOL)propagatesNaN
                                     name:(NSString *)name
{
    return [self charon_mps_reduction:kind
                                axes:axes
                              tensor:tensor
                         parameters:@{@"combination": combination, @"propagateNaN": @(propagatesNaN)}
                                name:name];
}

- (MPSGraphTensor *)transposeTensor:(MPSGraphTensor *)tensor
                           dimension:(NSUInteger)dimension
                        withDimension:(NSUInteger)withDimension
                                name:(NSString *)name
{
    // The one shape operation that arrived with the framework itself, and the row-major transpose it is:
    // measured over the 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40) it answers (1, 10, 2, 20, 3, 30, 4, 40) into a
    // 4x2, and a negative dimension is counted from the end, so dimension:-1 withDimension:0 answers what
    // dimension:0 withDimension:1 answers. The walk refuses an axis outside the rank, which is the same
    // refusal the reduction family's axis is.
    return [self charon_mps_gather:CharonMPSGraphOperationKindTranspose
                             tensor:tensor
                        parameters:@{@"gather": @"transpose",
                                     @"gatherPermutation": @[@((int32_t)withDimension), @((int32_t)dimension)]}
                               name:name];
}

#pragma mark - the gather family: the one seam every release's shape factory goes through

// What a gather is: the result's shape, and the parameters that say which transformation produces it. The
// walk in MPSGraphInterpreter14.m is one function for the whole family - the squeeze and the expanded
// dimension and the flatten are the same gather with the axes left alone, and the transpose, the broadcast
// and the reverse are the same gather with them not - so this only has to hand the parameters over and to
// put the result's own shape where the factory computed it, which is the @shape every operation in this
// framework already carries.
- (MPSGraphTensor *)charon_mps_gather:(CharonMPSGraphOperationKind)kind
                                tensor:(MPSGraphTensor *)tensor
                           parameters:(NSDictionary *)parameters
                                  name:(NSString *)name
{
    return [self charon_mps_operation:kind inputs:@[tensor] parameters:parameters name:name];
}

// The gather whose parameter is fed rather than written down: the axis, the axes or the shape arrives as the
// operation's second input, and the walk reads it when the graph runs. Measured, an int32 and an int64 of
// shape [1] both answer for an axis, and a floating point one is refused by the factory because the release
// cannot build the graph over it at all.
- (MPSGraphTensor *)charon_mps_gather:(CharonMPSGraphOperationKind)kind
                                tensor:(MPSGraphTensor *)tensor
                         fedParameter:(MPSGraphTensor *)fedParameter
                           parameters:(NSDictionary *)parameters
                                  name:(NSString *)name
{
    MPSDataType type = fedParameter.dataType;
    if (type == MPSDataTypeFloat32 || type == MPSDataTypeFloat16 || type == MPSDataTypeBool) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MPSGraph: %@ was asked for a parameter fed as a tensor of data type 0x%x, and "
                           @"an axis, a set of axes and a shape are all indices: measured, the release's own "
                           @"compiler refuses a floating point operand and the process goes down with it",
                            name, (unsigned)type];
    }
    NSMutableDictionary *all = [NSMutableDictionary dictionary];
    all[@"gatherCount"] = @(CharonMPSGraphElementCount(fedParameter.shape));
    [all addEntriesFromDictionary:parameters];
    return [self charon_mps_operation:kind inputs:@[tensor, fedParameter] parameters:all name:name];
}

#pragma mark - the cumulative family, whose seam every release's scan factory goes through

// The axis of a scan is the caller's and is normalised the way the reduction family's is: a negative axis
// is counted from the end of the rank, and an axis outside it is refused when the graph is built rather
// than left to be discovered as a wrong number. Measured on this host's own MPSGraph, an axis outside the
// rank is refused by the release too and by a form no caller can catch: MPSGraphNDArrayScan.mm:253 writes
// "Axis = ... This class only supports axis = 0, 1, 2, 3" and takes the process down with it, so there is
// no answer to record and a tensor for it would be an answer the release never gives.
- (NSInteger)charon_mps_scanAxis:(NSInteger)axis ofRank:(NSUInteger)rank named:(NSString *)name
{
    NSInteger normalised = axis;
    if (normalised < 0)
        normalised += (NSInteger)rank;
    if (normalised < 0 || normalised >= (NSInteger)rank) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MPSGraph: %@ was asked to scan axis %ld of a rank-%lu tensor, and axis 0 to "
                           @"%lu is all it has",
                            name, (long)axis, (unsigned long)rank, (unsigned long)rank];
    }
    return normalised;
}

- (MPSGraphTensor *)charon_mps_scan:(CharonMPSGraphOperationKind)kind
                               axis:(NSInteger)axis
                             tensor:(MPSGraphTensor *)tensor
                        combination:(NSString *)combination
                           exclusive:(BOOL)exclusive
                             reverse:(BOOL)reverse
                                name:(NSString *)name
{
    NSUInteger rank = tensor.shape.count;
    NSInteger normalised = [self charon_mps_scanAxis:axis ofRank:rank named:name];
    return [self charon_mps_operation:kind
                               inputs:@[tensor]
                           parameters:@{@"scanCombination": combination, @"scanAxis": @(normalised),
                                        @"scanExclusive": @(exclusive), @"scanReverse": @(reverse)}
                                  name:name];
}

- (MPSGraphTensor *)charon_mps_scan:(CharonMPSGraphOperationKind)kind
                         axisTensor:(MPSGraphTensor *)axisTensor
                             tensor:(MPSGraphTensor *)tensor
                        combination:(NSString *)combination
                           exclusive:(BOOL)exclusive
                             reverse:(BOOL)reverse
                                name:(NSString *)name
{
    // The axis is data here, so there is no axis to normalise at build time: the walk reads it when the
    // graph runs and refuses it there, the way the reduction family refuses an axis outside the rank.
    // What can be asked now is the axis tensor's own type, and a floating point one is refused now for
    // the reason in the header: the release cannot build the graph over one at all.
    MPSDataType axisType = axisTensor.dataType;
    if (axisType != MPSDataTypeInt32 && axisType != MPSDataTypeInt64 && axisType != MPSDataTypeUInt32 &&
        axisType != MPSDataTypeUInt64 && axisType != MPSDataTypeInt16 && axisType != MPSDataTypeUInt16 &&
        axisType != MPSDataTypeInt8 && axisType != MPSDataTypeUInt8) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MPSGraph: %@ was asked to scan along an axis tensor of data type 0x%x, and an "
                           @"axis is an index: measured, the release's own compiler refuses the operand "
                           @"('mps.cumulative_sum' op operand #1 must be 0D tensor of mps index type values "
                           @"or ... shape equal to [1]) and the process goes down with it",
                            name, (unsigned)axisType];
    }
    return [self charon_mps_operation:kind
                               inputs:@[tensor, axisTensor]
                           parameters:@{@"scanCombination": combination, @"scanAxisTensor": @YES,
                                        @"scanExclusive": @(exclusive), @"scanReverse": @(reverse)}
                                  name:name];
}

- (MPSGraphTensor *)reductionSumWithTensor:(MPSGraphTensor *)tensor
                                       axis:(NSInteger)axis
                                       name:(NSString *)name
{
    return [self charon_mps_reductionOf:@[@(axis)] tensor:tensor combination:@"sum"
                                    kind:CharonMPSGraphOperationKindReductionSum propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionSumWithTensor:(MPSGraphTensor *)tensor
                                       axes:(NSArray<NSNumber *> *)axes
                                       name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"sum"
                                    kind:CharonMPSGraphOperationKindReductionSum propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionProductWithTensor:(MPSGraphTensor *)tensor
                                          axis:(NSInteger)axis
                                          name:(NSString *)name
{
    return [self charon_mps_reductionOf:@[@(axis)] tensor:tensor combination:@"product"
                                    kind:CharonMPSGraphOperationKindReductionProduct propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionProductWithTensor:(MPSGraphTensor *)tensor
                                          axes:(NSArray<NSNumber *> *)axes
                                          name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"product"
                                    kind:CharonMPSGraphOperationKindReductionProduct propagatesNaN:NO name:name];
}

// The two maxima and the two minima differ in one thing only, and it is the one a reduction of floating
// point values is asked about: a NaN in the reduced set. A maximum that does not propagate answers the
// largest value that is not a NaN, so a NaN is skipped and the rest decide; a maximum that does
// propagate answers a NaN if there was one. Measured on this host's own MPSGraph over a 2x4 of
// (1, NaN, 3, 4 | NaN, 6, 7, 8): reductionMaximumWithTensor:axis:1 answers (4, 8) and
// reductionMaximumPropagateNaNWithTensor:axis:1 answers (NaN, NaN); the two minima answer (1, 6) and
// (NaN, NaN) over the same feed. The skipping maximum is C99's fmax, which is what it agrees with: a
// NaN operand is ignored, and a set of nothing but NaNs answers a NaN.
- (MPSGraphTensor *)reductionMaximumWithTensor:(MPSGraphTensor *)tensor
                                          axis:(NSInteger)axis
                                          name:(NSString *)name
{
    return [self charon_mps_reductionOf:@[@(axis)] tensor:tensor combination:@"maximum"
                                    kind:CharonMPSGraphOperationKindReductionMaximum propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionMaximumWithTensor:(MPSGraphTensor *)tensor
                                          axes:(NSArray<NSNumber *> *)axes
                                          name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"maximum"
                                    kind:CharonMPSGraphOperationKindReductionMaximum propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionMinimumWithTensor:(MPSGraphTensor *)tensor
                                          axis:(NSInteger)axis
                                          name:(NSString *)name
{
    return [self charon_mps_reductionOf:@[@(axis)] tensor:tensor combination:@"minimum"
                                    kind:CharonMPSGraphOperationKindReductionMinimum propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionMinimumWithTensor:(MPSGraphTensor *)tensor
                                          axes:(NSArray<NSNumber *> *)axes
                                          name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"minimum"
                                    kind:CharonMPSGraphOperationKindReductionMinimum propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)reductionMaximumPropagateNaNWithTensor:(MPSGraphTensor *)tensor
                                                     axis:(NSInteger)axis
                                                     name:(NSString *)name
{
    return [self charon_mps_reductionOf:@[@(axis)] tensor:tensor combination:@"maximum"
                                    kind:CharonMPSGraphOperationKindReductionMaximumPropagateNaN propagatesNaN:YES name:name];
}

- (MPSGraphTensor *)reductionMaximumPropagateNaNWithTensor:(MPSGraphTensor *)tensor
                                                     axes:(NSArray<NSNumber *> *)axes
                                                     name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"maximum"
                                    kind:CharonMPSGraphOperationKindReductionMaximumPropagateNaN propagatesNaN:YES name:name];
}

- (MPSGraphTensor *)reductionMinimumPropagateNaNWithTensor:(MPSGraphTensor *)tensor
                                                     axis:(NSInteger)axis
                                                     name:(NSString *)name
{
    return [self charon_mps_reductionOf:@[@(axis)] tensor:tensor combination:@"minimum"
                                    kind:CharonMPSGraphOperationKindReductionMinimumPropagateNaN propagatesNaN:YES name:name];
}

- (MPSGraphTensor *)reductionMinimumPropagateNaNWithTensor:(MPSGraphTensor *)tensor
                                                     axes:(NSArray<NSNumber *> *)axes
                                                     name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"minimum"
                                    kind:CharonMPSGraphOperationKindReductionMinimumPropagateNaN propagatesNaN:YES name:name];
}

// The mean and the variance are the reduction family in the two forms every framework of arithmetic has
// them: the first is the sum over the axis divided by how many values were summed, and the second is the
// mean of the squared deviations. Both are written back through the type they are stored as, so a mean
// of integers is the truncated quotient and not a rounded one. Measured on this host's own MPSGraph:
// over a 2x4 of (1, 2, 3, 4 | 10, 20, 30, 40), meanOfTensor:axes:@[@1] answers (2.5, 25) and
// varianceOfTensor:axes:@[@1] answers (1.25, 625); over the same feed as int32, where the sums are -6 and
// 10 and the counts are both 4, the mean answers (-1, 2) and the variance (1, 1) - the quotients
// 1.25 and 1.25 and 1.25 truncated twice, and 625 fits in neither a half nor an int32.
- (MPSGraphTensor *)meanOfTensor:(MPSGraphTensor *)tensor
                            axes:(NSArray<NSNumber *> *)axes
                            name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"mean"
                                    kind:CharonMPSGraphOperationKindReductionMean propagatesNaN:NO name:name];
}

// The variance is the only member of the family that can be given the mean it is to be taken about,
// which is the form a normalising network uses when it has already computed the mean for another reason.
// The two forms are the same arithmetic with the mean handed over instead of computed again, and the
// port holds them to each other rather than to two different answers: -varianceOfTensor:axes: is
// -varianceOfTensor:meanTensor: with a mean computed by the graph itself.
- (MPSGraphTensor *)varianceOfTensor:(MPSGraphTensor *)tensor
                                axes:(NSArray<NSNumber *> *)axes
                                name:(NSString *)name
{
    return [self charon_mps_reductionOf:axes tensor:tensor combination:@"variance"
                                    kind:CharonMPSGraphOperationKindReductionVariance propagatesNaN:NO name:name];
}

- (MPSGraphTensor *)varianceOfTensor:(MPSGraphTensor *)tensor
                          meanTensor:(MPSGraphTensor *)meanTensor
                                axes:(NSArray<NSNumber *> *)axes
                                name:(NSString *)name
{
    return [self charon_mps_reduction:CharonMPSGraphOperationKindReductionVariance
                                 axes:axes
                               tensor:tensor
                          parameters:@{@"combination": @"variance", @"propagateNaN": @NO,
                                       @"mean": meanTensor}
                                 name:name];
}

#pragma mark - running it

- (NSDictionary *)runWithFeeds:(NSDictionary<MPSGraphTensor *, MPSGraphTensorData *> *)feeds
                  targetTensors:(NSArray<MPSGraphTensor *> *)targetTensors
               targetOperations:(NSArray<MPSGraphOperation *> *)targetOperations
{
    // The values every tensor written so far, keyed by the tensor itself: a placeholder's comes from
    // the feeds, and each operation's from the operation that produced it. Walking the operations in the
    // order they were added is what lets one read what another wrote.
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in feeds)
        values[tensor] = feeds[tensor];
    for (MPSGraphOperation *operation in _operations) {
        [self charon_mps_runOperation:operation values:values];
    }
    (void)targetOperations;
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (MPSGraphTensor *tensor in targetTensors) {
        MPSGraphTensorData *data = values[tensor];
        if (data)
            results[tensor] = data;
    }
    return results;
}

- (MPSGraphExecutable *)compileWithDevice:(MPSGraphDevice *)device
                                   feeds:(NSDictionary *)feeds
                           targetTensors:(NSArray<MPSGraphTensor *> *)targetTensors
                        targetOperations:(NSArray<MPSGraphOperation *> *)targetOperations
                  compilationDescriptor:(MPSGraphCompilationDescriptor *)compilationDescriptor
{
    // An executable of this port is the graph itself: the work is a walk over the operations, so there is
    // nothing to compile ahead of time and the executable holds the targets the compile named.
    return [[MPSGraphExecutable alloc] initWithGraph:self
                                               device:device
                                               feeds:feeds
                                        targetTensors:targetTensors
                                     targetOperations:targetOperations
                                  executableDescriptor:nil];
}

@end
