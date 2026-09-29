// MPSMatrixCopyDescriptor and MPSMatrixCopy, the neuron kernels, the softmax kernels, MPSMatrixFindTopK
// and MPSMatrixSum: the pointwise and reduction side of the matrix framework.

#import "CharonMPS.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSMatrixCopyDescriptor {
    NSMutableArray *_sources;
    NSMutableArray *_destinations;
    NSMutableArray *_offsets;
    NSUInteger _count;
    MPSVector *_offsetVector;
    NSUInteger _offset;
}

- (instancetype)init
{
    NSLog(@"MPSMatrixCopyDescriptor: -init makes a copy of nothing; use +descriptorWithSourceMatrix:destinationMatrix:offsets: or -initWithSourceMatrices:destinationMatrices:offsetVector:offset:");
    return nil;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device count:(NSUInteger)count
{
    if ((self = [super init])) {
        _sources = [NSMutableArray array];
        _destinations = [NSMutableArray array];
        _offsets = [NSMutableArray array];
        _count = count;
        (void)device;
    }
    return self;
}

+ (instancetype)descriptorWithSourceMatrix:(MPSMatrix *)sourceMatrix destinationMatrix:(MPSMatrix *)destinationMatrix offsets:(MPSMatrixCopyOffsets)offsets
{
    MPSMatrixCopyDescriptor *descriptor = [[self alloc] initWithDevice:nil count:1];
    [descriptor setCopyOperationAtIndex:0 sourceMatrix:sourceMatrix destinationMatrix:destinationMatrix offsets:offsets];
    return descriptor;
}

- (void)setCopyOperationAtIndex:(NSUInteger)index sourceMatrix:(MPSMatrix *)sourceMatrix destinationMatrix:(MPSMatrix *)destinationMatrix offsets:(MPSMatrixCopyOffsets)offsets
{
    if (index >= _count) {
        CharonMPSRefuse(@"MPSMatrixCopy: a copy descriptor of %lu operations has no operation %lu", (unsigned long)_count, (unsigned long)index);
        return;
    }
    while (_sources.count <= index) {
        [_sources addObject:[NSNull null]];
        [_destinations addObject:[NSNull null]];
        MPSMatrixCopyOffsets none = {0, 0, 0, 0};
        [_offsets addObject:[NSValue valueWithBytes:&none objCType:@encode(MPSMatrixCopyOffsets)]];
    }
    [_sources replaceObjectAtIndex:index withObject:sourceMatrix];
    [_destinations replaceObjectAtIndex:index withObject:destinationMatrix];
    [_offsets replaceObjectAtIndex:index withObject:[NSValue valueWithBytes:&offsets objCType:@encode(MPSMatrixCopyOffsets)]];
}

- (instancetype)initWithSourceMatrices:(NSArray<MPSMatrix *> *)sourceMatrices
                   destinationMatrices:(NSArray<MPSMatrix *> *)destinationMatrices
                          offsetVector:(MPSVector *)offsets
                                offset:(NSUInteger)byteOffset
{
    NSUInteger count = sourceMatrices.count < destinationMatrices.count ? sourceMatrices.count : destinationMatrices.count;
    if (!(self = [self initWithDevice:nil count:count]))
        return nil;
    _offsetVector = offsets;
    _offset = byteOffset;
    for (NSUInteger index = 0; index < count; index++) {
        MPSMatrixCopyOffsets zero = {0, 0, 0, 0};
        if (offsets) {
            // A packed array of MPSMatrixOffset, one per copy, whose elements the header says begin at
            // the vector's own offset plus the byte offset given here.
            const MPSMatrixOffset *packed = (const MPSMatrixOffset *)((const char *)[offsets.data contents] + offsets.offset + byteOffset) + index;
            zero.sourceRowOffset = packed->rowOffset;
            zero.sourceColumnOffset = packed->columnOffset;
        }
        [self setCopyOperationAtIndex:index sourceMatrix:sourceMatrices[index] destinationMatrix:destinationMatrices[index] offsets:zero];
    }
    return self;
}

- (NSUInteger)charon_mps_count
{
    return _count;
}

- (MPSMatrix *)charon_mps_sourceAtIndex:(NSUInteger)index
{
    return _sources[index];
}

- (MPSMatrix *)charon_mps_destinationAtIndex:(NSUInteger)index
{
    return _destinations[index];
}

- (MPSMatrixCopyOffsets)charon_mps_offsetsAtIndex:(NSUInteger)index
{
    MPSMatrixCopyOffsets offsets = {0, 0, 0, 0};
    [_offsets[index] getValue:&offsets];
    return offsets;
}

@end

@implementation MPSMatrixCopy {
    NSUInteger _copyRows, _copyColumns;
    BOOL _sourcesAreTransposed, _destinationsAreTransposed;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSMatrixCopy: -initWithDevice: names no region; use -initWithDevice:copyRows:copyColumns:sourcesAreTransposed:destinationsAreTransposed:");
    return nil;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device copyRows:(NSUInteger)copyRows copyColumns:(NSUInteger)copyColumns sourcesAreTransposed:(BOOL)sourcesAreTransposed destinationsAreTransposed:(BOOL)destinationsAreTransposed
{
    if ((self = [super initWithDevice:device])) {
        _copyRows = copyRows;
        _copyColumns = copyColumns;
        _sourcesAreTransposed = sourcesAreTransposed;
        _destinationsAreTransposed = destinationsAreTransposed;
    }
    return self;
}

- (NSUInteger)copyRows
{
    return _copyRows;
}

- (NSUInteger)copyColumns
{
    return _copyColumns;
}

- (BOOL)sourcesAreTransposed
{
    return _sourcesAreTransposed;
}

- (BOOL)destinationsAreTransposed
{
    return _destinationsAreTransposed;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer copyDescriptor:(MPSMatrixCopyDescriptor *)copyDescriptor
{
    [self encodeToCommandBuffer:commandBuffer copyDescriptor:copyDescriptor rowPermuteIndices:nil rowPermuteOffset:0 columnPermuteIndices:nil columnPermuteOffset:0];
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
               copyDescriptor:(MPSMatrixCopyDescriptor *)copyDescriptor
            rowPermuteIndices:(MPSVector *)rowPermuteIndices
             rowPermuteOffset:(NSUInteger)rowPermuteOffset
         columnPermuteIndices:(MPSVector *)columnPermuteIndices
          columnPermuteOffset:(NSUInteger)columnPermuteOffset
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    // The copy moves a copyRows x copyColumns window from each source into its destination, transposing
    // on the way in or out as the kernel's two flags say, from the offsets the descriptor holds. The
    // per-column and per-row permute vectors reorder the columns and rows of the result; a permute
    // index names the source position of the destination column or row.
    for (NSUInteger index = 0; index < [copyDescriptor charon_mps_count]; index++) {
        MPSMatrix *source = [copyDescriptor charon_mps_sourceAtIndex:index];
        MPSMatrix *destination = [copyDescriptor charon_mps_destinationAtIndex:index];
        MPSMatrixCopyOffsets offsets = [copyDescriptor charon_mps_offsetsAtIndex:index];
        if (!source || !destination) {
            CharonMPSRefuse(@"MPSMatrixCopy: copy operation %lu names no source or no destination", (unsigned long)index);
            continue;
        }
        CharonMPSMatrixView from = CharonMPSMatrixViewOf(source), to = CharonMPSMatrixViewOf(destination);
        if (!CharonMPSDataTypeIsElement(from.dataType) || !CharonMPSDataTypeIsElement(to.dataType)) {
            CharonMPSRefuse(@"MPSMatrixCopy: a matrix of a data type that is not one of the eight element types was given");
            continue;
        }
        NSUInteger sourceRows = _sourcesAreTransposed ? _copyColumns : _copyRows;
        NSUInteger sourceColumns = _sourcesAreTransposed ? _copyRows : _copyColumns;
        NSUInteger destinationRows = _destinationsAreTransposed ? _copyColumns : _copyRows;
        NSUInteger destinationColumns = _destinationsAreTransposed ? _copyRows : _copyColumns;
        if (!CharonMPSMatrixHolds(&from, 0, offsets.sourceRowOffset, offsets.sourceColumnOffset, sourceRows, sourceColumns) ||
            !CharonMPSMatrixHolds(&to, 0, offsets.destinationRowOffset, offsets.destinationColumnOffset, destinationRows, destinationColumns)) {
            CharonMPSRefuse(@"MPSMatrixCopy: copy operation %lu names a %lux%lu region a matrix does not hold", (unsigned long)index, (unsigned long)_copyRows, (unsigned long)_copyColumns);
            continue;
        }
        for (NSUInteger row = 0; row < _copyRows; row++) {
            for (NSUInteger column = 0; column < _copyColumns; column++) {
                NSUInteger sourceRow = _sourcesAreTransposed ? column : row;
                NSUInteger sourceColumn = _sourcesAreTransposed ? row : column;
                NSUInteger destinationRow = _destinationsAreTransposed ? column : row;
                NSUInteger destinationColumn = _destinationsAreTransposed ? row : column;
                if (rowPermuteIndices) {
                    NSUInteger permuted = (NSUInteger)CharonMPSLoad((const char *)[[rowPermuteIndices data] contents] + rowPermuteOffset + row * 4, MPSDataTypeUInt32, 0);
                    if (permuted >= _copyRows) {
                        CharonMPSRefuse(@"MPSMatrixCopy: row permute index %lu names no row of %lu", (unsigned long)permuted, (unsigned long)_copyRows);
                        return;
                    }
                    sourceRow = permuted;
                }
                if (columnPermuteIndices) {
                    NSUInteger permuted = (NSUInteger)CharonMPSLoad((const char *)[[columnPermuteIndices data] contents] + columnPermuteOffset + column * 4, MPSDataTypeUInt32, 0);
                    if (permuted >= _copyColumns) {
                        CharonMPSRefuse(@"MPSMatrixCopy: column permute index %lu names no column of %lu", (unsigned long)permuted, (unsigned long)_copyColumns);
                        return;
                    }
                    sourceColumn = permuted;
                }
                double value = CharonMPSLoad(CharonMPSMatrixElement(&from, 0, offsets.sourceRowOffset + sourceRow, offsets.sourceColumnOffset + sourceColumn), from.dataType, 0);
                CharonMPSStore(CharonMPSMatrixElement(&to, 0, offsets.destinationRowOffset + destinationRow, offsets.destinationColumnOffset + destinationColumn), to.dataType, 0, value);
            }
        }
        CharonMPSConsumeReadCount(source);
    }
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    if ((self = [super initWithCoder:aDecoder device:device])) {
        _copyRows = 0;
        _copyColumns = 0;
    }
    return self;
}

@end

@implementation MPSMatrixSoftMax {
    NSUInteger _sourceRows, _sourceColumns;
    MTLOrigin _sourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
    BOOL _logarithmic;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        // NSUIntegerMax is the header's "take the shape from the matrix": a row count of that size
        // never fits, so a sourceRows of it means the rows of the matrix as it is.
        _sourceRows = NSUIntegerMax;
        _sourceColumns = NSUIntegerMax;
        _sourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

- (NSUInteger)sourceRows
{
    return _sourceRows;
}

- (void)setSourceRows:(NSUInteger)rows
{
    _sourceRows = rows;
}

- (NSUInteger)sourceColumns
{
    return _sourceColumns;
}

- (void)setSourceColumns:(NSUInteger)columns
{
    _sourceColumns = columns;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer inputMatrix:(MPSMatrix *)inputMatrix resultMatrix:(MPSMatrix *)resultMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView in = CharonMPSMatrixViewOf(inputMatrix), out = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixSoftMax: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // Softmax normalises each row: every element becomes its own value over the sum of the exponentials
    // of its row, and the log form subtracts the row's largest value first, which is what keeps the
    // exponentials from overflowing and cancels in the ratio. The row is sourceColumns wide, taken
    // from the matrix's own shape when sourceColumns is the header's "as the matrix is".
    NSUInteger rows = _sourceRows == NSUIntegerMax ? in.rows : _sourceRows;
    NSUInteger columns = _sourceColumns == NSUIntegerMax ? in.columns : _sourceColumns;
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = 0; b < count; b++) {
        if (!CharonMPSMatrixHolds(&in, b, _sourceMatrixOrigin.x, _sourceMatrixOrigin.y, rows, columns) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, rows, columns)) {
            CharonMPSRefuse(@"MPSMatrixSoftMax: a matrix of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)rows, (unsigned long)columns);
            return;
        }
    }
    for (NSUInteger b = 0; b < count; b++) {
        for (NSUInteger row = 0; row < rows; row++) {
            double largest = -INFINITY, sum = 0.0;
            for (NSUInteger column = 0; column < columns; column++) {
                double v = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                if (v > largest)
                    largest = v;
            }
            for (NSUInteger column = 0; column < columns; column++) {
                double v = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                sum += _logarithmic ? exp(v - largest) : exp(v);
            }
            for (NSUInteger column = 0; column < columns; column++) {
                double v = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                double e = _logarithmic ? exp(v - largest) : exp(v);
                double result = _logarithmic ? (v - largest) - log(sum) : e / sum;
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, result);
            }
        }
    }
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixSoftMax *copy = [super copyWithZone:zone device:device];
    copy->_sourceRows = _sourceRows;
    copy->_sourceColumns = _sourceColumns;
    copy->_sourceMatrixOrigin = _sourceMatrixOrigin;
    copy->_resultMatrixOrigin = _resultMatrixOrigin;
    copy->_batchStart = _batchStart;
    copy->_batchSize = _batchSize;
    copy->_logarithmic = _logarithmic;
    return copy;
}

// A log softmax's own flag, which its subclass sets. -logSoftMax is the same kernel with the row's
// exponentials taken in logarithms, so the flag is the only difference between the two classes.
- (void)charon_mps_setLogarithmic:(BOOL)logarithmic
{
    _logarithmic = logarithmic;
}

@end

@implementation MPSMatrixLogSoftMax

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device]))
        [self charon_mps_setLogarithmic:YES];
    return self;
}

@end

@implementation MPSMatrixSoftMaxGradient {
    NSUInteger _sourceRows, _sourceColumns;
    MTLOrigin _primarySourceMatrixOrigin, _secondarySourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super initWithDevice:device])) {
        _sourceRows = NSUIntegerMax;
        _sourceColumns = NSUIntegerMax;
        _primarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _secondarySourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

- (NSUInteger)sourceRows
{
    return _sourceRows;
}

- (void)setSourceRows:(NSUInteger)rows
{
    _sourceRows = rows;
}

- (NSUInteger)sourceColumns
{
    return _sourceColumns;
}

- (void)setSourceColumns:(NSUInteger)columns
{
    _sourceColumns = columns;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                gradientMatrix:(MPSMatrix *)gradientMatrix
           forwardOutputMatrix:(MPSMatrix *)forwardOutputMatrix
                  resultMatrix:(MPSMatrix *)resultMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView gradient = CharonMPSMatrixViewOf(gradientMatrix), forward = CharonMPSMatrixViewOf(forwardOutputMatrix), out = CharonMPSMatrixViewOf(resultMatrix);
    if (!CharonMPSDataTypeIsElement(gradient.dataType) || !CharonMPSDataTypeIsElement(forward.dataType) || !CharonMPSDataTypeIsElement(out.dataType)) {
        CharonMPSRefuse(@"MPSMatrixSoftMaxGradient: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // The gradient of a softmax row, in the formula MPSMatrixSoftMax.h gives for it:
    //     dL_dX_ij = Y_ij * (dL_dY_ij - sum_k(dL_dY_ik * Y_ik))
    // where Y is the forward kernel's output and dL_dY the incoming gradient.
    NSUInteger rows = _sourceRows == NSUIntegerMax ? forward.rows : _sourceRows;
    NSUInteger columns = _sourceColumns == NSUIntegerMax ? forward.columns : _sourceColumns;
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, forward.matrices, &start, &count);
    count = count < gradient.matrices ? count : gradient.matrices;
    count = count < out.matrices ? count : out.matrices;
    for (NSUInteger b = start; b < start + count; b++) {
        if (!CharonMPSMatrixHolds(&gradient, b, _primarySourceMatrixOrigin.x, _primarySourceMatrixOrigin.y, rows, columns) ||
            !CharonMPSMatrixHolds(&forward, b, _secondarySourceMatrixOrigin.x, _secondarySourceMatrixOrigin.y, rows, columns) ||
            !CharonMPSMatrixHolds(&out, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, rows, columns)) {
            CharonMPSRefuse(@"MPSMatrixSoftMaxGradient: a matrix of the batch [%lu, %lu) does not hold the %lux%lu region its origin names", (unsigned long)start, (unsigned long)(start + count), (unsigned long)rows, (unsigned long)columns);
            return;
        }
    }
    for (NSUInteger b = start; b < start + count; b++) {
        for (NSUInteger row = 0; row < rows; row++) {
            double total = 0.0;
            for (NSUInteger column = 0; column < columns; column++) {
                double g = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                double y = CharonMPSLoad(CharonMPSMatrixElement(&forward, b, _secondarySourceMatrixOrigin.x + row, _secondarySourceMatrixOrigin.y + column), forward.dataType, 0);
                total += g * y;
            }
            for (NSUInteger column = 0; column < columns; column++) {
                double g = CharonMPSLoad(CharonMPSMatrixElement(&gradient, b, _primarySourceMatrixOrigin.x + row, _primarySourceMatrixOrigin.y + column), gradient.dataType, 0);
                double y = CharonMPSLoad(CharonMPSMatrixElement(&forward, b, _secondarySourceMatrixOrigin.x + row, _secondarySourceMatrixOrigin.y + column), forward.dataType, 0);
                CharonMPSStore(CharonMPSMatrixElement(&out, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + column), out.dataType, 0, y * (g - total));
            }
        }
    }
    CharonMPSConsumeReadCount(gradientMatrix);
    CharonMPSConsumeReadCount(forwardOutputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixSoftMaxGradient *copy = [super copyWithZone:zone device:device];
    copy->_sourceRows = _sourceRows;
    copy->_sourceColumns = _sourceColumns;
    return copy;
}

@end

// The log softmax is the same kernel with the row's exponentials taken in logarithms, so the subclass
// carries no state of its own and only the flag that separates the two answers.
@implementation MPSMatrixLogSoftMaxGradient

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    return [super initWithDevice:device];
}

@end

@implementation MPSMatrixFindTopK {
    NSUInteger _sourceRows, _sourceColumns, _indexOffset, _numberOfTopKValues;
    MTLOrigin _sourceMatrixOrigin, _resultMatrixOrigin;
    NSUInteger _batchStart, _batchSize;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    NSLog(@"MPSMatrixFindTopK: -initWithDevice: names no count; use -initWithDevice:numberOfTopKValues:");
    return nil;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device numberOfTopKValues:(NSUInteger)numberOfTopKValues
{
    if ((self = [super initWithDevice:device])) {
        _numberOfTopKValues = numberOfTopKValues;
        _indexOffset = 0;
        _sourceRows = NSUIntegerMax;
        _sourceColumns = NSUIntegerMax;
        _sourceMatrixOrigin = MTLOriginMake(0, 0, 0);
        _resultMatrixOrigin = MTLOriginMake(0, 0, 0);
    }
    return self;
}

- (NSUInteger)sourceRows
{
    return _sourceRows;
}

- (void)setSourceRows:(NSUInteger)rows
{
    _sourceRows = rows;
}

- (NSUInteger)sourceColumns
{
    return _sourceColumns;
}

- (void)setSourceColumns:(NSUInteger)columns
{
    _sourceColumns = columns;
}

- (NSUInteger)indexOffset
{
    return _indexOffset;
}

- (void)setIndexOffset:(NSUInteger)offset
{
    _indexOffset = offset;
}

- (NSUInteger)numberOfTopKValues
{
    return _numberOfTopKValues;
}

- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>)commandBuffer inputMatrix:(MPSMatrix *)inputMatrix resultIndexMatrix:(MPSMatrix *)resultIndexMatrix resultValueMatrix:(MPSMatrix *)resultValueMatrix
{
    if (!CharonMPSCommandBufferPermits(commandBuffer))
        return;
    CharonMPSMatrixView in = CharonMPSMatrixViewOf(inputMatrix), indices = CharonMPSMatrixViewOf(resultIndexMatrix), values = CharonMPSMatrixViewOf(resultValueMatrix);
    if (!CharonMPSDataTypeIsElement(in.dataType) || !CharonMPSDataTypeIsElement(indices.dataType) || !CharonMPSDataTypeIsElement(values.dataType)) {
        CharonMPSRefuse(@"MPSMatrixFindTopK: a matrix of a data type that is not one of the eight element types was given");
        return;
    }
    // The k largest values of each row, largest first. The index matrix holds the column each value
    // came from, counted from indexOffset, and the value matrix the values themselves. A row narrower
    // than k gives the whole row.
    NSUInteger rows = _sourceRows == NSUIntegerMax ? in.rows : _sourceRows;
    NSUInteger columns = _sourceColumns == NSUIntegerMax ? in.columns : _sourceColumns;
    NSUInteger wanted = _numberOfTopKValues < columns ? _numberOfTopKValues : columns;
    NSUInteger start, count;
    CharonMPSBatch(_batchStart, _batchSize, in.matrices, &start, &count);
    count = count < indices.matrices ? count : indices.matrices;
    count = count < values.matrices ? count : values.matrices;
    for (NSUInteger b = 0; b < count; b++) {
        if (!CharonMPSMatrixHolds(&in, b, _sourceMatrixOrigin.x, _sourceMatrixOrigin.y, rows, columns) ||
            !CharonMPSMatrixHolds(&indices, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, rows, wanted) ||
            !CharonMPSMatrixHolds(&values, b, _resultMatrixOrigin.x, _resultMatrixOrigin.y, rows, wanted)) {
            CharonMPSRefuse(@"MPSMatrixFindTopK: a matrix of the batch [%lu, %lu) does not hold the region its origin names", (unsigned long)start, (unsigned long)(start + count));
            return;
        }
    }
    for (NSUInteger b = 0; b < count; b++) {
        for (NSUInteger row = 0; row < rows; row++) {
            // A selection over the row's columns, keeping the k largest in order. Insertion keeps the
            // order exact, which a partial sort of equal values would not.
            NSUInteger *order = (NSUInteger *)calloc(columns ? columns : 1, sizeof(NSUInteger));
            double *best = (double *)calloc(wanted ? wanted : 1, sizeof(double));
            NSUInteger filled = 0;
            for (NSUInteger column = 0; column < columns; column++) {
                double v = CharonMPSLoad(CharonMPSMatrixElement(&in, b, _sourceMatrixOrigin.x + row, _sourceMatrixOrigin.y + column), in.dataType, 0);
                NSUInteger place = filled;
                while (place > 0 && best[place - 1] < v) {
                    if (place < wanted) {
                        best[place] = best[place - 1];
                        order[place] = order[place - 1];
                    }
                    place--;
                }
                if (filled < wanted || place < wanted) {
                    if (place >= wanted)
                        continue;
                    best[place] = v;
                    order[place] = column;
                    if (filled < wanted)
                        filled++;
                }
            }
            for (NSUInteger place = 0; place < filled; place++) {
                CharonMPSStore(CharonMPSMatrixElement(&indices, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + place), indices.dataType, 0, (double)(order[place] + _indexOffset));
                CharonMPSStore(CharonMPSMatrixElement(&values, b, _resultMatrixOrigin.x + row, _resultMatrixOrigin.y + place), values.dataType, 0, best[place]);
            }
            free(order);
            free(best);
        }
    }
    CharonMPSConsumeReadCount(inputMatrix);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    return [super initWithCoder:aDecoder device:device];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSMatrixFindTopK *copy = [super copyWithZone:zone device:device];
    copy->_sourceRows = _sourceRows;
    copy->_sourceColumns = _sourceColumns;
    copy->_indexOffset = _indexOffset;
    copy->_numberOfTopKValues = _numberOfTopKValues;
    return copy;
}

@end
