// MPSGraphExecutionDescriptor and MPSGraphExecutableExecutionDescriptor, from the headers of
// MPSGraphExecutionDescriptor.h and MPSGraphExecutable.h in the SDK of iOS 16.4. Both are plain
// descriptors: they keep what they are given and the run methods above read them, which is the whole of
// what a descriptor can be asked for.

#import "CharonMPSGraph.h"

@implementation MPSGraphExecutionDescriptor {
    MPSGraphOptions _options;
    NSUInteger _maximumCommandsPerBuffer;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _options = MPSGraphOptionsDefault;
        _maximumCommandsPerBuffer = 0;
    }
    return self;
}

- (MPSGraphOptions)options
{
    return _options;
}

- (void)setOptions:(MPSGraphOptions)options
{
    _options = options;
}

- (NSUInteger)maximumCommandsPerBuffer
{
    return _maximumCommandsPerBuffer;
}

- (void)setMaximumCommandsPerBuffer:(NSUInteger)maximumCommandsPerBuffer
{
    _maximumCommandsPerBuffer = maximumCommandsPerBuffer;
}

@end

@implementation MPSGraphExecutableExecutionDescriptor {
    MPSGraphExecutionDescriptor *_executionDescriptor;
    BOOL _waitForCompilationCompletion;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _executionDescriptor = [[MPSGraphExecutionDescriptor alloc] init];
        _waitForCompilationCompletion = NO;
    }
    return self;
}

- (MPSGraphExecutionDescriptor *)executionDescriptor
{
    return _executionDescriptor;
}

- (void)setExecutionDescriptor:(MPSGraphExecutionDescriptor *)executionDescriptor
{
    _executionDescriptor = executionDescriptor;
}

- (id)copyWithZone:(NSZone *)zone
{
    // The header's own class declaration says `NSObject<NSCopying>`, and this is the method that answers it.
    // A copy is ANOTHER descriptor carrying the same two values and not this object: both of them are
    // readwrite properties, so a caller that changes the copy's must not change this one's - which is the
    // difference from MPSGraphTensor's own -copyWithZone:, where `self` is right because a tensor's shape and
    // data type are never written after it is made.
    MPSGraphExecutableExecutionDescriptor *copy = [[[self class] allocWithZone:zone] init];
    copy.executionDescriptor = _executionDescriptor;
    copy.waitForCompilationCompletion = _waitForCompilationCompletion;
    return copy;
}

- (BOOL)waitForCompilationCompletion
{
    return _waitForCompilationCompletion;
}

- (void)setWaitForCompilationCompletion:(BOOL)waitForCompilationCompletion
{
    _waitForCompilationCompletion = waitForCompilationCompletion;
}

@end
