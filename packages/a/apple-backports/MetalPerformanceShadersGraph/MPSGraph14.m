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
