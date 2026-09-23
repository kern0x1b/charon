#import <SceneKit/SceneKit.h>
#import <UIKit/UIKit.h>

@interface SCNPhysicsRadialGravityField : SCNPhysicsField <NSSecureCoding>
@end

@interface CharonSCNCoding : NSObject
+ (SCNVector3)decodeVector3:(NSCoder *)coder forKey:(NSString *)key;
+ (void)encodeVector3:(SCNVector3)vector coder:(NSCoder *)coder forKey:(NSString *)key;
+ (SCNVector4)decodeVector4:(NSCoder *)coder forKey:(NSString *)key;
+ (void)encodeVector4:(SCNVector4)vector coder:(NSCoder *)coder forKey:(NSString *)key;

+ (UIColor *)decodeColor:(NSCoder *)coder forKey:(NSString *)key;
+ (NSString *)decodeFileReferenceName:(NSCoder *)coder forKey:(NSString *)key;
+ (BOOL)decodeBool:(NSCoder *)coder forKey:(NSString *)key default:(BOOL)fallback;

+ (void)pushSourceURL:(NSURL *)url;
+ (void)popSourceURL;
+ (NSURL *)currentSourceURL;

+ (void)markFound:(BOOL)found forKey:(NSString *)key onObject:(id)object;
+ (BOOL)wasFound:(NSString *)key onObject:(id)object;
@end
