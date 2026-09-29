// MPSKernel, from the header of the SDK of iOS 16.4. One object per release: the band machinery keeps an
// object whole or drops it whole, so a file here carries the API of exactly one release.

#import "CharonMPS.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation MPSKernel {
    id<MTLDevice> _device;
    MPSKernelOptions _options;
    NSString *_label;
}

@synthesize label;

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
    if ((self = [super init])) {
        _device = device;
        _options = MPSKernelOptionsNone;
    }
    return self;
}

- (id<MTLDevice>)device
{
    return _device;
}

- (MPSKernelOptions)options
{
    return _options;
}

- (void)setOptions:(MPSKernelOptions)options
{
    _options = options;
}

- (NSString *)label
{
    return _label;
}

- (void)setLabel:(NSString *)name
{
    _label = [name copy];
}

- (instancetype)copyWithZone:(NSZone *)zone device:(id<MTLDevice>)device
{
    MPSKernel *copy = [[[self class] allocWithZone:zone] initWithDevice:device ? device : _device];
    copy->_options = _options;
    copy->_label = _label;
    return copy;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [self copyWithZone:zone device:nil];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    // A kernel of this port is a description of work, not a compiled pipeline: its device, its
    // options and its label are everything the base class carries, and a subclass's own state is
    // encoded by the subclass. The release decodes the same three keys here, so an archive written
    // by an application and read by this port and the other way round both name the same fields.
    return [self initWithCoder:aDecoder device:MTLCreateSystemDefaultDevice()];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder device:(id<MTLDevice>)device
{
    if ((self = [super init])) {
        _device = device;
        _options = MPSKernelOptionsNone;
        NSString *name = [aDecoder decodeObjectOfClass:[NSString class] forKey:@"label"];
        if (name)
            _label = [name copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    if (_label)
        [aCoder encodeObject:_label forKey:@"label"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
