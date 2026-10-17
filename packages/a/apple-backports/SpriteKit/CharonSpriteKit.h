#ifndef CharonSpriteKit_h
#define CharonSpriteKit_h

// The SpriteKit declarations this library carries, as the port declares them. The declarations are the generator's
// (packages/a/apple-backports/spec/SpriteKit/declarations.tsv); the bodies are the port's own.
//
// This header declares only the surface the library carries. It does not import the SDK's <SpriteKit/SpriteKit.h>:
// the SDK declares members that arrived in later releases (SKUniform's iOS 10 vector and matrix uniforms, for one), and
// an implementation that includes it is incomplete for every release below the member's own - clang warns on each of
// them. A member joins this header in the object of the release it arrived in: the iOS 7 surface of SKNode and SKScene
// is in SpriteKit7.m and SpriteKitScene7.m, the iOS 8 members in SpriteKit8.m and SpriteKitScene8.m (in categories,
// below), the iOS 9 members in SpriteKit9.m.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <TargetConditionals.h>

@class SKTexture;
@class SKScene;
@class SKView;

// SKColor is the colour class of the platform, as the SDK's SpriteKitBase.h defines it.
#if TARGET_OS_IPHONE
@class UIColor;
typedef UIColor CharonSKColor;
#else
@class NSColor;
typedef NSColor CharonSKColor;
#endif

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

// The scale modes of a scene, with the values the SDK gives them.
typedef NS_ENUM(NSInteger, SKSceneScaleMode) {
    SKSceneScaleModeFill = 0,
    SKSceneScaleModeAspectFill = 1,
    SKSceneScaleModeAspectFit = 2,
    SKSceneScaleModeResizeFill = 3,
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

// SKEffectNode of iOS 7: a node whose effects (its filter, shader and rasterisation) are owed to the effects step, so
// the class carries no members of its own yet (registry/SpriteKit/ios7.json). It is the superclass of SKScene.
@interface SKEffectNode : SKNode
@end

// SKScene of iOS 7: the root of a tree of nodes, presented in a view. Its size is the viewport and its anchor point
// places the origin of its coordinates in that viewport; it does not take a position or a scale (SpriteKitScene7.m).
@interface SKScene : SKEffectNode

+ (instancetype)sceneWithSize:(CGSize)size;
- (instancetype)initWithSize:(CGSize)size;

@property (nonatomic) CGSize size;
@property (nonatomic) SKSceneScaleMode scaleMode;
@property (nonatomic) CGPoint anchorPoint;
@property (nonatomic, retain) CharonSKColor *backgroundColor;

#if TARGET_OS_IPHONE
@property (nonatomic, weak, readonly) SKView *view;
- (void)didMoveToView:(SKView *)view;
- (void)willMoveFromView:(SKView *)view;
#endif

- (void)update:(NSTimeInterval)currentTime;
- (void)didEvaluateActions;
- (void)didSimulatePhysics;
- (void)didChangeSize:(CGSize)oldSize;

@end

// The seam between SKView and the scene's members: the view records itself as the scene's view, which the scene's
// view property reads. The view calls it; no application does.
@interface SKScene (CharonSpriteKitView)
- (void)charon_setView:(SKView *)view;
@end

// SKNode's scene of iOS 7 (SpriteKitScene7.m): the scene the node is in, the node itself for a scene, or nil.
@interface SKNode (CharonSpriteKitScene)
@property (nonatomic, readonly) SKScene *scene;
@end

// The delegate of iOS 8 (SpriteKitScene8.m): the scene's delegate property and members of that release. The protocol is
// written by the generator into CharonSpriteKitProtocols.h (spec/protocol-headers.tsv); the sources that call its methods
// import that header.
@protocol SKSceneDelegate;

@interface SKScene (CharonSpriteKitScene8)
@property (nonatomic, weak) id<SKSceneDelegate> delegate;
- (void)didApplyConstraints;
- (void)didFinishUpdate;
@end

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

// SKView of iOS 7 (SpriteKitView7.m): the view that presents a scene. The port draws the scene's background colour and
// steps the scene's update methods each frame; the nodes' content is drawn by the step that carries it. The members
// carried are the ones whose behaviour the port has; the rest of the SDK's SKView are owed (registry/SpriteKit/ios7.json).
// Device-unverified.
@interface SKView : UIView

@property (nonatomic, getter=isPaused) BOOL paused;
@property (nonatomic) BOOL showsFPS;
@property (nonatomic) BOOL showsDrawCount;
@property (nonatomic) BOOL showsNodeCount;
@property (nonatomic, getter=isAsynchronous) BOOL asynchronous;
@property (nonatomic) BOOL ignoresSiblingOrder;
@property (nonatomic) NSInteger frameInterval;
@property (nonatomic, readonly) SKScene *scene;

- (void)presentScene:(SKScene *)scene;

@end
#endif

#endif /* CharonSpriteKit_h */
