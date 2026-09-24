#import "CharonSCN.h"

SCNLightingModel const SCNLightingModelPhong = @"SCNLightingModelPhong";
SCNLightingModel const SCNLightingModelBlinn = @"SCNLightingModelBlinn";
SCNLightingModel const SCNLightingModelLambert = @"SCNLightingModelLambert";
SCNLightingModel const SCNLightingModelConstant = @"SCNLightingModelConstant";

@implementation SCNMaterial

- (instancetype)init
{
    if ((self = [super init])) {
        // Each slot's contents as macOS SceneKit's new material answers them (tests/backports/device/
        // scenekit-defaults-expectations.h). Ambient and roughness are a grey of 0.2 in linear light, which SceneKit
        // works in; a UIColor here is sRGB.
        UIColor *white = [UIColor whiteColor], *black = [UIColor blackColor];
        UIColor *grey = [CharonSCNCoding colorWithLinearWhite:0.2];
        _diffuse = [SCNMaterialProperty materialPropertyWithContents:white];
        _ambient = [SCNMaterialProperty materialPropertyWithContents:grey];
        _specular = [SCNMaterialProperty materialPropertyWithContents:black];
        _normal = [SCNMaterialProperty materialPropertyWithContents:white];
        _reflective = [SCNMaterialProperty materialPropertyWithContents:black];
        _emission = [SCNMaterialProperty materialPropertyWithContents:black];
        _transparent = [SCNMaterialProperty materialPropertyWithContents:white];
        _multiply = [SCNMaterialProperty materialPropertyWithContents:white];
        _displacement = [SCNMaterialProperty materialPropertyWithContents:black];
        _ambientOcclusion = [SCNMaterialProperty materialPropertyWithContents:white];
        _selfIllumination = [SCNMaterialProperty materialPropertyWithContents:black];
        _metalness = [SCNMaterialProperty materialPropertyWithContents:black];
        _roughness = [SCNMaterialProperty materialPropertyWithContents:grey];
        _lightingModelName = SCNLightingModelBlinn;
        _transparency = 1;
        _shininess = 1;
    }
    return self;
}

+ (instancetype)material
{
    return [[self alloc] init];
}

@synthesize name = _name;
@synthesize diffuse = _diffuse;
@synthesize ambient = _ambient;
@synthesize specular = _specular;
@synthesize normal = _normal;
@synthesize reflective = _reflective;
@synthesize emission = _emission;
@synthesize transparent = _transparent;
@synthesize multiply = _multiply;
@synthesize displacement = _displacement;
@synthesize ambientOcclusion = _ambientOcclusion;
@synthesize selfIllumination = _selfIllumination;
@synthesize metalness = _metalness;
@synthesize roughness = _roughness;
@synthesize lightingModelName = _lightingModelName;
@synthesize doubleSided = _doubleSided;
@synthesize transparency = _transparency;
@synthesize shininess = _shininess;
@synthesize blendMode = _blendMode;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self init])) {
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        for (NSString *key in @[@"diffuse", @"ambient", @"specular", @"normal", @"reflective", @"emission",
                                 @"transparent", @"multiply", @"displacement", @"ambientOcclusion",
                                 @"selfIllumination", @"metalness", @"roughness"]) {
            if ([coder containsValueForKey:key]) {
                SCNMaterialProperty *property = [coder decodeObjectOfClass:[SCNMaterialProperty class] forKey:key];
                if (property) {
                    // A colour this port cannot read keeps the slot at the default init gave it, as the log line says;
                    // an archive with no colour at all is contents set to nil, and stays nil (measured on macOS
                    // SceneKit: facts/SceneKit/SceneKit.md).
                    if (property.charonColorNotRead) {
                        property.contents = [(SCNMaterialProperty *)[self valueForKey:key] contents];
                    }
                    [self setValue:property forKey:key];
                }
            }
        }
        NSString *lightingModel = [coder decodeObjectOfClass:[NSString class] forKey:@"lightingModelName"];
        if (lightingModel.length) {
            _lightingModelName = lightingModel;
        }
        _doubleSided = [CharonSCNCoding decodeBool:coder forKey:@"doubleSided" default:NO];
        if ([coder containsValueForKey:@"transparency"]) {
            _transparency = [coder decodeDoubleForKey:@"transparency"];
        }
        if ([coder containsValueForKey:@"shininess"]) {
            _shininess = [coder decodeDoubleForKey:@"shininess"];
        }
        if ([coder containsValueForKey:@"blendMode"]) {
            _blendMode = [coder decodeIntegerForKey:@"blendMode"];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"name"];
    [coder encodeObject:_diffuse forKey:@"diffuse"];
    [coder encodeObject:_ambient forKey:@"ambient"];
    [coder encodeObject:_specular forKey:@"specular"];
    [coder encodeObject:_lightingModelName forKey:@"lightingModelName"];
    [coder encodeBool:_doubleSided forKey:@"doubleSided"];
    [coder encodeDouble:_transparency forKey:@"transparency"];
    [coder encodeDouble:_shininess forKey:@"shininess"];
    [coder encodeInteger:_blendMode forKey:@"blendMode"];
}

- (id)copyWithZone:(NSZone *)zone
{
    SCNMaterial *copy = [[SCNMaterial allocWithZone:zone] init];
    copy->_name = [_name copy];
    copy->_diffuse = [_diffuse copy];
    copy->_ambient = [_ambient copy];
    copy->_specular = [_specular copy];
    copy->_normal = [_normal copy];
    copy->_reflective = [_reflective copy];
    copy->_emission = [_emission copy];
    copy->_transparent = [_transparent copy];
    copy->_multiply = [_multiply copy];
    copy->_displacement = [_displacement copy];
    copy->_ambientOcclusion = [_ambientOcclusion copy];
    copy->_selfIllumination = [_selfIllumination copy];
    copy->_metalness = [_metalness copy];
    copy->_roughness = [_roughness copy];
    copy->_lightingModelName = _lightingModelName;
    copy->_doubleSided = _doubleSided;
    copy->_transparency = _transparency;
    copy->_shininess = _shininess;
    copy->_blendMode = _blendMode;
    return copy;
}

@end
