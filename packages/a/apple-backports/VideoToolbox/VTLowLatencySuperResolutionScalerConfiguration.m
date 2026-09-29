#import "CharonVideoToolbox.h"
#import "VideoToolboxValueStore.h"


// A file-local spelling for the types the property macros cannot take. Each of these carries a
// comma, and the preprocessor counts arguments rather than template parameters, so the macro
// would be handed three arguments for one type. The declaration in CharonVideoToolbox.h keeps
// the SDK's own spelling: this is the same type, named once so the macro has one argument.
typedef NSDictionary<NSString *, id> CharonVTFrameAttributes;

CHARON_VIDEO_TOOLBOX_VALUE_STORE(VTLowLatencySuperResolutionScalerConfiguration)

@implementation VTLowLatencySuperResolutionScalerConfiguration

#pragma mark - The protocol's own properties, implemented for this class

+ (BOOL)isSupported
{
    return (BOOL)[CharonValueStoreOfClass([self class])[@"supported"] longLongValue];
}

CHARON_VALUE_PROPERTY(NSArray<NSNumber *> *, frameSupportedPixelFormats)

CHARON_VALUE_PROPERTY(CharonVTFrameAttributes *, sourcePixelBufferAttributes)

CHARON_VALUE_PROPERTY(CharonVTFrameAttributes *, destinationPixelBufferAttributes)

CHARON_SCALAR_PROPERTY(NSInteger, nextFrameCount)

CHARON_SCALAR_PROPERTY(NSInteger, previousFrameCount)

+ (CMVideoDimensions)maximumDimensions
{
    CMVideoDimensions value = {0};
    NSValue *boxed = CharonValueStoreOfClass([self class])[@"maximumDimensions"];
    if (boxed)
        [boxed getValue:&value];
    return value;
}

+ (CMVideoDimensions)minimumDimensions
{
    CMVideoDimensions value = {0};
    NSValue *boxed = CharonValueStoreOfClass([self class])[@"minimumDimensions"];
    if (boxed)
        [boxed getValue:&value];
    return value;
}


#pragma mark - This class's own properties

CHARON_SCALAR_PROPERTY(NSInteger, frameWidth)

CHARON_SCALAR_PROPERTY(NSInteger, frameHeight)

CHARON_DOUBLE_PROPERTY(float, scaleFactor)


#pragma mark - The SDK's designated initialisers

- (instancetype)initWithFrameWidth:(NSInteger)frameWidth
                        frameHeight:(NSInteger)frameHeight
                        scaleFactor:(float)scaleFactor
{
    self = [super init];
    CharonValueSet(self, @(frameWidth), @"frameWidth");
    CharonValueSet(self, @(frameHeight), @"frameHeight");
    CharonValueSet(self, @(scaleFactor), @"scaleFactor");
    return self;
}

@end
