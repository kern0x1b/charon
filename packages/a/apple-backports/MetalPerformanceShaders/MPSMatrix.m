// MPSMatrixDescriptor, MPSMatrix, MPSVectorDescriptor, MPSVector and their temporary forms.

#import "CharonMPS.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// The row stride the release recommends for a given number of columns and element type, measured on
// macOS 26.5's own MPSMatrixDescriptor (tests/backports/host/mpsmatrix/run.sh prints the table this
// rule reproduces): one column is one element, a floating point row is rounded up to a multiple of
// sixteen bytes and an integer row to a multiple of four elements. Zero columns have no row.
size_t CharonMPSRowBytesForColumns(NSUInteger columns, MPSDataType dataType)
{
    size_t elementSize = MPSSizeofMPSDataType(dataType);
    size_t alignment = CharonMPSDataTypeIsFloat(dataType) ? 16 : 4 * elementSize;
    if (columns == 0)
        return 0;
    if (columns == 1)
        return elementSize;
    return (columns * elementSize + alignment - 1) / alignment * alignment;
}

@implementation MPSMatrixDescriptor {
    NSUInteger _rows, _columns, _matrices, _rowBytes, _matrixBytes;
    MPSDataType _dataType;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _dataType = MPSDataTypeInvalid;
    }
    return self;
}

+ (instancetype)matrixDescriptorWithDimensions:(NSUInteger)rows columns:(NSUInteger)columns rowBytes:(NSUInteger)rowBytes dataType:(MPSDataType)dataType
{
    return [self matrixDescriptorWithRows:rows columns:columns rowBytes:rowBytes dataType:dataType];
}

+ (instancetype)matrixDescriptorWithRows:(NSUInteger)rows columns:(NSUInteger)columns rowBytes:(NSUInteger)rowBytes dataType:(MPSDataType)dataType
{
    MPSMatrixDescriptor *descriptor = [[self alloc] init];
    descriptor.rows = rows;
    descriptor.columns = columns;
    descriptor.rowBytes = rowBytes;
    descriptor.dataType = dataType;
    // One matrix, and its stride is the rows' own: the header says matrixBytes is a multiple of rowBytes
    // at least rows * rowBytes, and the release's own answer for a single matrix is exactly that. Both
    // are fixed here and are not worked out again when rows or the stride change afterwards, which is
    // what the release does too (measured, tests/backports/host/mpsmatrix/run.sh).
    descriptor->_matrices = 1;
    descriptor->_matrixBytes = rows * rowBytes;
    return descriptor;
}

+ (instancetype)matrixDescriptorWithRows:(NSUInteger)rows columns:(NSUInteger)columns matrices:(NSUInteger)matrices rowBytes:(NSUInteger)rowBytes matrixBytes:(NSUInteger)matrixBytes dataType:(MPSDataType)dataType
{
    MPSMatrixDescriptor *descriptor = [self matrixDescriptorWithRows:rows columns:columns rowBytes:rowBytes dataType:dataType];
    descriptor->_matrices = matrices;
    descriptor->_matrixBytes = matrixBytes;
    return descriptor;
}

+ (size_t)rowBytesFromColumns:(NSUInteger)columns dataType:(MPSDataType)dataType
{
    return CharonMPSRowBytesForColumns(columns, dataType);
}

+ (size_t)rowBytesForColumns:(NSUInteger)columns dataType:(MPSDataType)dataType
{
    return CharonMPSRowBytesForColumns(columns, dataType);
}

- (NSUInteger)rows
{
    return _rows;
}

- (void)setRows:(NSUInteger)rows
{
    _rows = rows;
}

- (NSUInteger)columns
{
    return _columns;
}

- (void)setColumns:(NSUInteger)columns
{
    _columns = columns;
}

- (NSUInteger)matrices
{
    return _matrices;
}

- (NSUInteger)rowBytes
{
    return _rowBytes;
}

- (void)setRowBytes:(NSUInteger)rowBytes
{
    _rowBytes = rowBytes;
}

- (NSUInteger)matrixBytes
{
    return _matrixBytes;
}

- (MPSDataType)dataType
{
    return _dataType;
}

- (void)setDataType:(MPSDataType)dataType
{
    _dataType = dataType;
}

@end

@implementation MPSVectorDescriptor {
    NSUInteger _length, _vectors, _vectorBytes;
    MPSDataType _dataType;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _dataType = MPSDataTypeInvalid;
    }
    return self;
}

+ (instancetype)vectorDescriptorWithLength:(NSUInteger)length dataType:(MPSDataType)dataType
{
    return [self vectorDescriptorWithLength:length vectors:1 vectorBytes:CharonMPSRowBytesForColumns(length, dataType) dataType:dataType];
}

+ (instancetype)vectorDescriptorWithLength:(NSUInteger)length vectors:(NSUInteger)vectors vectorBytes:(NSUInteger)vectorBytes dataType:(MPSDataType)dataType
{
    MPSVectorDescriptor *descriptor = [[self alloc] init];
    descriptor.length = length;
    descriptor.dataType = dataType;
    descriptor->_vectors = vectors;
    descriptor->_vectorBytes = vectorBytes;
    return descriptor;
}

+ (size_t)vectorBytesForLength:(NSUInteger)length dataType:(MPSDataType)dataType
{
    return CharonMPSRowBytesForColumns(length, dataType);
}

- (NSUInteger)length
{
    return _length;
}

- (void)setLength:(NSUInteger)length
{
    _length = length;
}

- (NSUInteger)vectors
{
    return _vectors;
}

- (NSUInteger)vectorBytes
{
    return _vectorBytes;
}

- (MPSDataType)dataType
{
    return _dataType;
}

- (void)setDataType:(MPSDataType)dataType
{
    _dataType = dataType;
}

@end

// The two containers are the same object with a different second dimension, and the header says so:
// a matrix is an array of rows of columns, a vector an array of components. Both address their data
// the same three strides, so the storage each holds is set up once here.
@implementation MPSMatrix {
    id<MTLBuffer> _buffer;
    MPSMatrixDescriptor *_descriptor;
    NSUInteger _offset;
    id<MTLDevice> _device;
}

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer descriptor:(MPSMatrixDescriptor *)descriptor
{
    if ((self = [super init])) {
        _buffer = buffer;
        _descriptor = descriptor;
        _device = [buffer device];
    }
    return self;
}

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset descriptor:(MPSMatrixDescriptor *)descriptor
{
    if ((self = [super init])) {
        _buffer = buffer;
        _descriptor = descriptor;
        _offset = offset;
        _device = [buffer device];
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MPSMatrixDescriptor *)descriptor
{
    if ((self = [super init])) {
        _descriptor = descriptor;
        _device = device;
    }
    return self;
}

- (instancetype)init
{
    NSLog(@"MPSMatrix: -init makes a matrix of no shape; use -initWithBuffer:descriptor: or -initWithDevice:descriptor:");
    return nil;
}

- (id<MTLBuffer>)data
{
    if (!_buffer) {
        // The release makes the backing store when -data is first asked for, so that a matrix's
        // -resourceSize can be asked before anything is allocated. The storage it then makes is the
        // (matrices - 1) * matrixBytes + (rows - 1) * rowBytes + columns * elementSize bytes its own
        // header specifies.
        size_t elementSize = MPSSizeofMPSDataType(_descriptor.dataType);
        size_t bytes = (_descriptor.matrices - 1) * _descriptor.matrixBytes + (_descriptor.rows - 1) * _descriptor.rowBytes + _descriptor.columns * elementSize;
        _buffer = [_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    }
    return _buffer;
}

- (id<MTLDevice>)device
{
    return _device;
}

- (NSUInteger)rows
{
    return _descriptor.rows;
}

- (NSUInteger)columns
{
    return _descriptor.columns;
}

- (NSUInteger)matrices
{
    return _descriptor.matrices;
}

- (MPSDataType)dataType
{
    return _descriptor.dataType;
}

- (NSUInteger)rowBytes
{
    return _descriptor.rowBytes;
}

- (NSUInteger)matrixBytes
{
    return _descriptor.matrixBytes;
}

- (NSUInteger)offset
{
    return _offset;
}

- (void)synchronizeOnCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    (void)commandBuffer;
}

- (NSUInteger)resourceSize
{
    if (_buffer)
        return _buffer.length;
    if (!_descriptor)
        return 0;
    size_t elementSize = MPSSizeofMPSDataType(_descriptor.dataType);
    return (_descriptor.matrices - 1) * _descriptor.matrixBytes + (_descriptor.rows - 1) * _descriptor.rowBytes + _descriptor.columns * elementSize;
}

@end

@implementation MPSTemporaryMatrix {
    NSUInteger _readCount;
}

- (instancetype)charon_mps_withReadCount:(NSUInteger)readCount
{
    _readCount = readCount;
    return self;
}

+ (instancetype)temporaryMatrixWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer matrixDescriptor:(MPSMatrixDescriptor *)matrixDescriptor
{
    id<MTLDevice> device = [commandBuffer respondsToSelector:@selector(device)] ? [commandBuffer device] : MTLCreateSystemDefaultDevice();
    if (!device)
        device = MTLCreateSystemDefaultDevice();
    // A read count starts at one: a temporary matrix may be written any number of times and read once.
    return [[[self alloc] initWithDevice:device descriptor:matrixDescriptor] charon_mps_withReadCount:1];
}

+ (void)prefetchStorageWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer matrixDescriptorList:(NSArray<MPSMatrixDescriptor *> *)descriptorList
{
    // Every temporary matrix's storage is its own device buffer, made when its -data is asked for, so
    // there is no cache of free stores for a list of descriptors to be poured into ahead of time. The
    // descriptors are still walked, so a nil in the list is caught here rather than at the kernel
    // that would have used it.
    (void)commandBuffer;
    for (MPSMatrixDescriptor *descriptor in descriptorList) {
        if (!descriptor) {
            NSLog(@"MPSMatrix: a temporary storage list holds no descriptor");
            return;
        }
    }
}

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer descriptor:(MPSMatrixDescriptor *)descriptor
{
    // The header marks this unavailable for a temporary matrix: a temporary one takes its storage from
    // the release's heap, so a caller that hands it a buffer of its own has asked for something the
    // release would not do either.
    (void)buffer;
    (void)descriptor;
    NSLog(@"MPSTemporaryMatrix: -initWithBuffer:descriptor: makes no temporary matrix; use +temporaryMatrixWithCommandBuffer:matrixDescriptor:");
    return nil;
}

- (NSUInteger)readCount
{
    return _readCount;
}

- (void)setReadCount:(NSUInteger)readCount
{
    _readCount = readCount;
}

@end

@implementation MPSVector {
    id<MTLBuffer> _buffer;
    MPSVectorDescriptor *_descriptor;
    NSUInteger _offset;
    id<MTLDevice> _device;
}

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer descriptor:(MPSVectorDescriptor *)descriptor
{
    if ((self = [super init])) {
        _buffer = buffer;
        _descriptor = descriptor;
        _device = [buffer device];
    }
    return self;
}

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset descriptor:(MPSVectorDescriptor *)descriptor
{
    if ((self = [super init])) {
        _buffer = buffer;
        _descriptor = descriptor;
        _offset = offset;
        _device = [buffer device];
    }
    return self;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MPSVectorDescriptor *)descriptor
{
    if ((self = [super init])) {
        _descriptor = descriptor;
        _device = device;
    }
    return self;
}

- (instancetype)init
{
    NSLog(@"MPSVector: -init makes a vector of no length; use -initWithBuffer:descriptor: or -initWithDevice:descriptor:");
    return nil;
}

- (id<MTLBuffer>)data
{
    if (!_buffer) {
        size_t elementSize = MPSSizeofMPSDataType(_descriptor.dataType);
        size_t bytes = (_descriptor.vectors - 1) * _descriptor.vectorBytes + _descriptor.length * elementSize;
        _buffer = [_device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    }
    return _buffer;
}

- (id<MTLDevice>)device
{
    return _device;
}

- (NSUInteger)length
{
    return _descriptor.length;
}

- (NSUInteger)vectors
{
    return _descriptor.vectors;
}

- (MPSDataType)dataType
{
    return _descriptor.dataType;
}

- (NSUInteger)vectorBytes
{
    return _descriptor.vectorBytes;
}

- (NSUInteger)offset
{
    return _offset;
}

- (void)synchronizeOnCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
{
    (void)commandBuffer;
}

- (NSUInteger)resourceSize
{
    if (_buffer)
        return _buffer.length;
    if (!_descriptor)
        return 0;
    return (_descriptor.vectors - 1) * _descriptor.vectorBytes + _descriptor.length * MPSSizeofMPSDataType(_descriptor.dataType);
}

@end

@implementation MPSTemporaryVector {
    NSUInteger _readCount;
}

- (instancetype)charon_mps_withReadCount:(NSUInteger)readCount
{
    _readCount = readCount;
    return self;
}

+ (instancetype)temporaryVectorWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer descriptor:(MPSVectorDescriptor *)descriptor
{
    id<MTLDevice> device = [commandBuffer respondsToSelector:@selector(device)] ? [commandBuffer device] : MTLCreateSystemDefaultDevice();
    if (!device)
        device = MTLCreateSystemDefaultDevice();
    return [[[self alloc] initWithDevice:device descriptor:descriptor] charon_mps_withReadCount:1];
}

+ (void)prefetchStorageWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer descriptorList:(NSArray<MPSVectorDescriptor *> *)descriptorList
{
    (void)commandBuffer;
    for (MPSVectorDescriptor *descriptor in descriptorList) {
        if (!descriptor) {
            NSLog(@"MPSVector: a temporary storage list holds no descriptor");
            return;
        }
    }
}

- (instancetype)initWithBuffer:(id<MTLBuffer>)buffer descriptor:(MPSVectorDescriptor *)descriptor
{
    (void)buffer;
    (void)descriptor;
    NSLog(@"MPSTemporaryVector: -initWithBuffer:descriptor: makes no temporary vector; use +temporaryVectorWithCommandBuffer:descriptor:");
    return nil;
}

- (NSUInteger)readCount
{
    return _readCount;
}

- (void)setReadCount:(NSUInteger)readCount
{
    _readCount = readCount;
}

@end
