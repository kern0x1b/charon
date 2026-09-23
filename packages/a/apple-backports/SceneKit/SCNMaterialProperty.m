#import "CharonSCN.h"

@implementation SCNMaterialProperty

- (instancetype)init
{
    if ((self = [super init])) {
        _intensity = 1;
        _minificationFilter = SCNFilterModeLinear;
        _magnificationFilter = SCNFilterModeLinear;
        _mipFilter = SCNFilterModeNone;
        _contentsTransform = SCNMatrix4Identity;
        _wrapS = SCNWrapModeClamp;
        _wrapT = SCNWrapModeClamp;
        _mappingChannel = 0;
    }
    return self;
}

+ (instancetype)materialPropertyWithContents:(id)contents
{
    SCNMaterialProperty *property = [[self alloc] init];
    property->_contents = contents;
    return property;
}

@synthesize contents = _contents;
@synthesize intensity = _intensity;
@synthesize minificationFilter = _minificationFilter;
@synthesize magnificationFilter = _magnificationFilter;
@synthesize mipFilter = _mipFilter;
@synthesize contentsTransform = _contentsTransform;
@synthesize wrapS = _wrapS;
@synthesize wrapT = _wrapT;
@synthesize mappingChannel = _mappingChannel;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        NSString *image = [CharonSCNCoding decodeFileReferenceName:coder forKey:@"image"];
        if (image) {
            _contents = image;
        }
        if ([coder containsValueForKey:@"intensity"]) {
            _intensity = [coder decodeDoubleForKey:@"intensity"];
        }
        if ([coder containsValueForKey:@"minificationFilter"]) {
            _minificationFilter = [coder decodeIntegerForKey:@"minificationFilter"];
        }
        if ([coder containsValueForKey:@"magnificationFilter"]) {
            _magnificationFilter = [coder decodeIntegerForKey:@"magnificationFilter"];
        }
        if ([coder containsValueForKey:@"mipFilter"]) {
            _mipFilter = [coder decodeIntegerForKey:@"mipFilter"];
        }
        if ([coder containsValueForKey:@"wrapS"]) {
            _wrapS = [coder decodeIntegerForKey:@"wrapS"];
        }
        if ([coder containsValueForKey:@"wrapT"]) {
            _wrapT = [coder decodeIntegerForKey:@"wrapT"];
        }
        _mappingChannel = [coder decodeIntegerForKey:@"mappingChannel"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_intensity forKey:@"intensity"];
    [coder encodeInteger:_minificationFilter forKey:@"minificationFilter"];
    [coder encodeInteger:_magnificationFilter forKey:@"magnificationFilter"];
    [coder encodeInteger:_mipFilter forKey:@"mipFilter"];
    [coder encodeInteger:_wrapS forKey:@"wrapS"];
    [coder encodeInteger:_wrapT forKey:@"wrapT"];
    [coder encodeInteger:_mappingChannel forKey:@"mappingChannel"];
}

- (id)copyWithZone:(NSZone *)zone
{
    SCNMaterialProperty *copy = [[SCNMaterialProperty allocWithZone:zone] init];
    copy->_contents = _contents;
    copy->_intensity = _intensity;
    copy->_minificationFilter = _minificationFilter;
    copy->_magnificationFilter = _magnificationFilter;
    copy->_mipFilter = _mipFilter;
    copy->_contentsTransform = _contentsTransform;
    copy->_wrapS = _wrapS;
    copy->_wrapT = _wrapT;
    copy->_mappingChannel = _mappingChannel;
    return copy;
}

@end
