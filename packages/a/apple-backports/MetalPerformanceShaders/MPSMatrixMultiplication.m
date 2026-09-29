// The two origins-and-batch base classes MPSMatrixTypes.h declares, and the two multiplication
// kernels MPSMatrixMultiplication.h declares.

#import "CharonMPS.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSMatrixUnaryKernel {
    MTLOrigin _sourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _sourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
        _batchStart = 0;
        _batchSize = 0;
    }
    return self;
}

- (MTLOrigin)sourceMatrixOrigin
{
    return _sourceMatrixOrigin;
}

- (void)setSourceMatrixOrigin:(MTLOrigin)origin
{
    _sourceMatrixOrigin = origin;
}

- (MTLOrigin)resultMatrixOrigin
{
    return _resultMatrixOrigin;
}

- (void)setResultMatrixOrigin:(MTLOrigin)origin
{
    _resultMatrixOrigin = origin;
}

- (NSUInteger)batchStart
{
    return _batchStart;
}

- (void)setBatchStart:(NSUInteger)batchStart
{
    _batchStart = batchStart;
}

- (NSUInteger)batchSize
{
    return _batchSize;
}

- (void)setBatchSize:(NSUInteger)batchSize
{
    _batchSize = batchSize;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    if ((self = [super initWithCoder:aDecoder device:device])) {
        _sourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

@end

@implementation MPSMatrixBinaryKernel {
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _primarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _secondarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
        _batchStart = 0;
        _batchSize = 0;
    }
    return self;
}

- (MTLOrigin)primarySourceMatrixOrigin
{
    return _primarySourceMatrixOrigin;
}

- (void)setPrimarySourceMatrixOrigin:(MTLOrigin)origin
{
    _primarySourceMatrixOrigin = origin;
}

- (MTLOrigin)secondarySourceMatrixOrigin
{
    return _secondarySourceMatrixOrigin;
}

- (void)setSecondarySourceMatrixOrigin:(MTLOrigin)origin
{
    _secondarySourceMatrixOrigin = origin;
}

- (MTLOrigin)resultMatrixOrigin
{
    return _resultMatrixOrigin;
}

- (void)setResultMatrixOrigin:(MTLOrigin)origin
{
    _resultMatrixOrigin = origin;
}

- (NSUInteger)batchStart
{
    return _batchStart;
}

- (void)setBatchStart:(NSUInteger)batchStart
{
    _batchStart = batchStart;
}

- (NSUInteger)batchSize
{
    return _batchSize;
}

- (void)setBatchSize:(NSUInteger)batchSize
{
    _batchSize = batchSize;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    if ((self = [super initWithCoder:aDecoder device:device])) {
        _primarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _secondarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

@end

@implementation MPSMatrixMultiplication {
    NSUInteger _resultRows, _resultColumns, _interiorColumns;
    BOOL _transposeLeft, _transposeRight;
    double _alpha, _beta;
    MTLOrigin _leftMatrixOrigin, _rightMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSMatrixMultiplication: -initWithDevice: names no shape; use -initWithDevice:resultRows:resultColumns:interiorColumns: or the initialiser that takes the transpositions and the scales");
    return nil;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
               transposeLeft:(BOOL)transposeLeft
              transposeRight:(BOOL)transposeRight
                  resultRows:(NSUInteger)resultRows
               resultColumns:(NSUInteger)resultColumns
             interiorColumns:(NSUInteger)interiorColumns
                       alpha:(double)alpha
                        beta:(double)beta
{
    if ((self = [super initWithDevice:device])) {
        _transposeLeft = transposeLeft;
        _transposeRight = transposeRight;
        _resultRows = resultRows;
        _resultColumns = resultColumns;
        _interiorColumns = interiorColumns;
        _alpha = alpha;
        _beta = beta;
        _leftMatrixOrigin = MTLOriginMake(0, 0, 0);
        _rightMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
        _batchStart = 0;
        _batchSize = 0;
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device resultRows:(NSUInteger)resultRows resultColumns:(NSUInteger)resultColumns interiorColumns:(NSUInteger)interiorColumns
{
    return [self initWithDevice:device transposeLeft:NO transposeRight:NO resultRows:resultRows resultColumns:resultColumns interiorColumns:interiorColumns alpha:1.0 beta:0.0];
}

- (MTLOrigin)leftMatrixOrigin
{
    return _leftMatrixOrigin;
}

- (void)setLeftMatrixOrigin:(MTLOrigin)origin
{
    _leftMatrixOrigin = origin;
}

- (MTLOrigin)rightMatrixOrigin
{
    return _rightMatrixOrigin;
}

- (void)setRightMatrixOrigin:(MTLOrigin)origin
{
    _rightMatrixOrigin = origin;
}

- (MTLOrigin)resultMatrixOrigin
{
    return _resultMatrixOrigin;
}

- (void)setResultMatrixOrigin:(MTLOrigin)origin
{
    _resultMatrixOrigin = origin;
}

- (NSUInteger)batchStart
{
    return _batchStart;
}

- (void)setBatchStart:(NSUInteger)batchStart
{
    _batchStart = batchStart;
}

- (NSUInteger)batchSize
{
    return _batchSize;
}

- (void)setBatchSize:(NSUInteger)batchSize
{
    _batchSize = batchSize;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                   leftMatrix:(MPSMatrix *)leftMatrix
                  rightMatrix:(MPSMatrix *)rightMatrix
                 resultMatrix:(MPSMatrix *)resultMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView left = CharonMPSMatrixViewOf(leftMatrix), right = CharonMPSMatrixViewOf(rightMatrix), result = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(left.dataType) || !CharonMPSDataTypeIsElement(right.dataType) || !CharonMPSDataTypeIsElement(result.dataType)) {
        CharonMPSRefuse(@"MPSMatrixMultiplication: a matrix of data type %u, %u or %u is not one of the eight element types", (unsigned)left.dataType, (unsigned)right.dataType, (unsigned)result.dataType);
        return;
    }
    // The left matrix holds op(A) as resultRows x interiorColumns, the right one op(B) as
    // interiorColumns x resultColumns, and the result resultRows x resultColumns, each from its own
    // origin, and each may be transposed on the way in. A matrix that does not hold the region is
    // refused rather than read past its end.
    NSUInteger leftRows = _transposeLeft ? _interiorColumns : _resultRows;
    NSUInteger leftColumns = _transposeLeft ? _resultRows : _interiorColumns;
    NSUInteger rightRows = _transposeRight ? _resultColumns : _interiorColumns;
    NSUInteger rightColumns = _transposeRight ? _interiorColumns : _resultColumns;
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, result.matrices, &start, &count);
    count = count < left.matrices ? count : left.matrices;
    count = count < right.matrices ? count : right.matrices;
    BOOL whole = YES;
    for (NSUInteger b = 0; b < count; b++) {
        if (!CharonMPSMatrixHolds(&left, b, _leftMatrixOrigin.x, _leftMatrixOrigin.y, leftRows, leftColumns) ||
            !CharonMPSMatrixHolds(&right, b, _rightMatrixOrigin.x, _rightMatrixOrigin.y, rightRows, rightColumns) ||
            !CharonMPSMatrixHolds(&result, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, _resultRows, _resultColumns)) {
            whole = NO;
            break;
        }
    }
    if (!whole) {
        CharonMPSRefuse(@"MPSMatrixMultiplication: a matrix of the batch [%lu, %lu) does not hold the %lux%lu, %lux%lu, %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)leftRows, (unsigned long)leftColumns, (unsigned long)rightRows, (unsigned long)rightColumns, (unsigned long)_resultRows, (unsigned long)_resultColumns);
        return;
    }
    for (NSUInteger b = 0; b < count; b++) {
        for (NSUInteger row = 0; row < _resultRows; row++) {
            for (NSUInteger column = 0; column < _resultColumns; column++) {
                double sum = 0.0;
                for (NSUInteger k = 0; k < _interiorColumns; k++) {
                    NSUInteger lr = _transposeLeft ? k : row, lc = _transposeLeft ? row : k;
                    NSUInteger rr = _transposeRight ? column : k, rc = _transposeRight ? k : column;
                    double a = CharonMPSLoad(CharonMPSMatrixElement(&left, b, _leftMatrixOrigin.x + lr, _leftMatrixOrigin.y + lc), left.dataType, 0);
                    double c = CharonMPSLoad(CharonMPSMatrixElement(&right, b, _rightMatrixOrigin.x + rr, _rightMatrixOrigin.y + rc), right.dataType, 0);
                    sum += a * c;
                }
                void *element = CharonMPSMatrixElement(&result, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column);
                double value = CharonMPSLoad(element, result.dataType, 0);
                CharonMPSStore(element, result.dataType, 0, _alpha * sum + _beta * value);
            }
        }
    }
    CharonMPSConsumeReadCount(leftMatrix);
    CharonMPSConsumeReadCount(rightMatrix);
}

@end

@implementation MPSMatrixVectorMultiplication {
    NSUInteger _rows, _columns;
    BOOL _transpose;
    double _alpha, _beta;
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSMatrixVectorMultiplication: -initWithDevice: names no shape; use -initWithDevice:rows:columns: or the initialiser that takes the transposition and the scales");
    return nil;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device transpose:(BOOL)transpose rows:(NSUInteger)rows columns:(NSUInteger)columns alpha:(double)alpha beta:(double)beta
{
    if ((self = [super initWithDevice:device])) {
        _transpose = transpose;
        _rows = rows;
        _columns = columns;
        _alpha = alpha;
        _beta = beta;
        _primarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _secondarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device rows:(NSUInteger)rows columns:(NSUInteger)columns
{
    return [self initWithDevice:device transpose:NO rows:rows columns:columns alpha:1.0 beta:0.0];
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                  inputMatrix:(MPSMatrix *)inputMatrix
                  inputVector:(MPSVector *)inputVector
                 resultVector:(MPSVector *)resultVector
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView matrix = CharonMPSMatrixViewOf(inputMatrix);
    CharonMPSVectorView x = CharonMPSVectorViewOf(inputVector), y = CharonMPSVectorViewOf(resultVector);
    if (!CharonMPSDataTypeIsElement(matrix.dataType) || !CharonMPSDataTypeIsElement(x.dataType) || !CharonMPSDataTypeIsElement(y.dataType)) {
        CharonMPSRefuse(@"MPSMatrixVectorMultiplication: a matrix or vector of a data type that is not one of the eight element types was given");
        return;
    }
    // op(A) is _rows x _columns, x holds its _columns components and y the result's _rows, and the
    // batch is the matrices and vectors the origins and the batch range name together.
    NSUInteger matrixRows = _transpose ? _columns : _rows;
    NSUInteger matrixColumns = _transpose ? _rows : _columns;
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, matrix.matrices, &start, &count);
    count = count < x.vectors ? count : x.vectors;
    count = count < y.vectors ? count : y.vectors;
    BOOL whole = YES;
    for (NSUInteger b = 0; b < count; b++) {
        if (!CharonMPSMatrixHolds(&matrix, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, matrixRows, matrixColumns) ||
            !CharonMPSVectorHolds(&x, b, _columns) || !CharonMPSVectorHolds(&y, b, _rows)) {
            whole = NO;
            break;
        }
    }
    if (!whole) {
        CharonMPSRefuse(@"MPSMatrixVectorMultiplication: the matrix or a vector of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)matrixRows, (unsigned long)matrixColumns);
        return;
    }
    for (NSUInteger b = 0; b < count; b++) {
        for (NSUInteger row = 0; row < _rows; row++) {
            double sum = 0.0;
            for (NSUInteger column = 0; column < _columns; column++) {
                NSUInteger mr = _transpose ? column : row, mc = _transpose ? row : column;
                double a = CharonMPSLoad(CharonMPSMatrixElement(&matrix, b, _primarySourceMatrixOrigin.x + mr, _primarySourceMatrixOrigin.y + mc), matrix.dataType, 0);
                double v = CharonMPSLoad(CharonMPSVectorElement(&x, b, column), x.dataType, 0);
                sum += a * v;
            }
            void *element = CharonMPSVectorElement(&y, b, row);
            double value = CharonMPSLoad(element, y.dataType, 0);
            CharonMPSStore(element, y.dataType, 0, _alpha * sum + _beta * value);
        }
    }
    CharonMPSConsumeReadCount(inputMatrix);
    CharonMPSConsumeReadCount(inputVector);
}

@end
