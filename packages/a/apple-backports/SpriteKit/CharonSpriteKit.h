#ifndef CharonSpriteKit_h
#define CharonSpriteKit_h

// The SpriteKit declarations this library carries, as the port declares them. The declarations are the generator's
// (packages/a/apple-backports/spec/SpriteKit/declarations.tsv); the bodies are the port's own (SpriteKit8.m).
//
// This header declares only the surface the library carries. It does not import the SDK's <SpriteKit/SpriteKit.h>:
// the SDK declares members of SKUniform that arrived in later releases (iOS 10's vector and matrix uniforms), and an
// implementation that includes it is incomplete for every release below 10 - clang warns on each of them. A member
// joins this header in the object of the release it arrived in.

#import <Foundation/Foundation.h>

@class SKTexture;

// The uniform types, with the values the SDK gives them (spec/SpriteKit/declarations.tsv).
typedef NS_ENUM(NSInteger, SKUniformType) {
    SKUniformTypeNone = 0,
    SKUniformTypeFloat = 1,
    SKUniformTypeFloatVector2 = 2,
    SKUniformTypeFloatVector3 = 3,
    SKUniformTypeFloatVector4 = 4,
    SKUniformTypeFloatMatrix2 = 5,
    SKUniformTypeFloatMatrix3 = 6,
    SKUniformTypeFloatMatrix4 = 7,
    SKUniformTypeTexture = 8,
};

// SKUniform of iOS 8: a name, a type and one payload.
@interface SKUniform : NSObject <NSCopying, NSSecureCoding>

+ (instancetype)uniformWithName:(NSString *)name;
+ (instancetype)uniformWithName:(NSString *)name texture:(SKTexture *)texture;
+ (instancetype)uniformWithName:(NSString *)name float:(float)value;

- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name texture:(SKTexture *)texture;
- (instancetype)initWithName:(NSString *)name float:(float)value;

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) SKUniformType uniformType;
@property (nonatomic, retain) SKTexture *textureValue;
@property (nonatomic) float floatValue;

@end

#endif /* CharonSpriteKit_h */
