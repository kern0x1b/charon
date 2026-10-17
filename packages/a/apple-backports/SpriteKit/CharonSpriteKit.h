#ifndef CharonSpriteKit_h
#define CharonSpriteKit_h

// The SpriteKit declarations this library carries, as the port declares them. The declarations are the generator's
// (packages/a/apple-backports/spec/SpriteKit/declarations.tsv); the bodies are the port's own.
//
// This header declares only the surface the library carries. It does not import the SDK's <SpriteKit/SpriteKit.h>:
// the SDK declares members that arrived in later releases (SKUniform's iOS 10 vector and matrix uniforms, for one), and
// an implementation that includes it is incomplete for every release below the member's own - clang warns on each of
// them. A member joins this header in the object of the release it arrived in: the iOS 7 surface of SKNode is in
// SpriteKit7.m, the iOS 8 members in SpriteKit8.m (in a category, below), the iOS 9 members in SpriteKit9.m.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

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

// SKNode of iOS 7: the tree of named nodes that every SpriteKit node is. Its frame, hit tests and conversions are the
// zero-size, content-free ones of the base class; a node with content supplies its own frame.
@interface SKNode : NSObject

+ (instancetype)node;
- (instancetype)init;

@property (nonatomic, copy) NSString *name;
@property (nonatomic) CGPoint position;
@property (nonatomic) CGFloat zPosition;
@property (nonatomic) CGFloat zRotation;
@property (nonatomic) CGFloat xScale;
@property (nonatomic) CGFloat yScale;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGFloat speed;
@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic, getter=isUserInteractionEnabled) BOOL userInteractionEnabled;
@property (nonatomic, retain) NSMutableDictionary *userData;

@property (nonatomic, readonly) SKNode *parent;
@property (nonatomic, readonly) NSArray *children;
@property (nonatomic, readonly) CGRect frame;

- (CGRect)calculateAccumulatedFrame;
- (void)setScale:(CGFloat)scale;

- (void)addChild:(SKNode *)node;
- (void)insertChild:(SKNode *)node atIndex:(NSUInteger)index;
- (void)removeChildrenInArray:(NSArray *)nodes;
- (void)removeAllChildren;
- (void)removeFromParent;

- (SKNode *)childNodeWithName:(NSString *)name;
- (void)enumerateChildNodesWithName:(NSString *)name usingBlock:(void (^)(SKNode *node, BOOL *stop))block;

- (BOOL)inParentHierarchy:(SKNode *)parent;
- (BOOL)containsPoint:(CGPoint)point;
- (SKNode *)nodeAtPoint:(CGPoint)point;
- (NSArray *)nodesAtPoint:(CGPoint)point;
- (CGPoint)convertPoint:(CGPoint)point fromNode:(SKNode *)node;
- (CGPoint)convertPoint:(CGPoint)point toNode:(SKNode *)node;
- (BOOL)intersectsNode:(SKNode *)node;
- (BOOL)isEqualToNode:(SKNode *)node;

@end

// The seam between the iOS 7 object and the members of later releases that match names: the node's descendants and
// children that a path of names picks out, in the order the host gives them. Declared here because two objects use it.
@interface SKNode (CharonSpriteKitMatching)
- (NSArray *)charon_nodesMatchingPath:(NSString *)path;
@end

// SKNode's iOS 8 member (SpriteKit8.m): the nodes a path picks out, as an array.
@interface SKNode (CharonSpriteKit8)
- (NSArray *)objectForKeyedSubscript:(NSString *)path;
@end

// SKNode's iOS 9 member (SpriteKit9.m): the node moves to a new parent, and leaves its old one.
@interface SKNode (CharonSpriteKit9)
- (void)moveToParent:(SKNode *)parent;
@end

#endif /* CharonSpriteKit_h */
