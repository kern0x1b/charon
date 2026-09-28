// ARSCNView11.m - ARKit's SceneKit view, at 11.0 where the class arrived in.
//
// `ARSCNView` is a SceneKit view, not a view that holds one: the SDK declares it as
// `@interface ARSCNView : SCNView<ARSessionProviding>`, and the backport implements that very class
// (`packages/a/apple-backports/SceneKit/SCNView.m` is `@implementation SCNView` and carries
// `_OBJC_CLASS_$_SCNView`, with `CharonSCN.h:1` importing the SDK's SceneKit.h as its declaration), so
// the superclass this subclasses is one the tree already has.
//
// The four questions the view is asked are the frame's, and the frame's answers are the shared pinhole
// arithmetic already in ARFrame.m - so this forwards rather than duplicating it. The node and anchor
// halves are the view's own.
//
// The pairing lives in an `NSMapTable` **held by the view**, weak in both directions, and that is the
// whole of the design. An earlier draft put it on the node as a category ivar, which cannot work: a
// category's `@synthesize` is rejected even on the non-fragile ABI armv7 has. A map the view holds
// needs nothing of `SCNNode` and nothing of the SDK's storage.
//
// The 12.0 members of this class are in `ARSCNView12.m`, because an object carries the API of one
// release: `-unprojectPoint:ontoPlaneWithTransform:` is `API_AVAILABLE(ios(12.0))` and does not resolve
// at a 6.1.3 target at all.

#import <ARKit/ARKit.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARSCNView ()

/// The anchor a node stands for, and the node an anchor is shown by. Both directions are weak keys and
/// weak values, because the session owns the anchors and the scene owns the nodes: a view that kept
/// either alive past its owner's release of it would be holding a thing nothing owns. A node the
/// caller built is simply not in the map, and an anchor with no node has none.
@property (nonatomic, strong) NSMapTable<SCNNode *, ARAnchor *> *anchorsByNode;
@property (nonatomic, strong) NSMapTable<ARAnchor *, SCNNode *> *nodesByAnchor;

@end

@implementation ARSCNView

@synthesize anchorsByNode = _anchorsByNode;
@synthesize nodesByAnchor = _nodesByAnchor;
@synthesize session = _session;
@synthesize delegate = _delegate;
@synthesize automaticallyUpdatesLighting = _automaticallyUpdatesLighting;
@synthesize rendersCameraGrain = _rendersCameraGrain;
@synthesize rendersMotionBlur = _rendersMotionBlur;
@synthesize scene = _scene;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
        [self charon_resetAnchorMaps];
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self)
        [self charon_resetAnchorMaps];
    return self;
}

- (void)charon_resetAnchorMaps
{
    _anchorsByNode = [NSMapTable weakToWeakObjectsMapTable];
    _nodesByAnchor = [NSMapTable weakToWeakObjectsMapTable];
}

- (nullable ARAnchor *)anchorForNode:(SCNNode *)node
{
    // The session places a node for an anchor, and a node the caller has put inside it is the same node
    // for this purpose - so the walk goes up the parents and the first ancestor the map knows is the
    // answer.
    for (SCNNode *walk = node; walk; walk = walk.parentNode) {
        ARAnchor *anchor = [self.anchorsByNode objectForKey:walk];
        if (anchor)
            return anchor;
    }
    return nil;
}

- (nullable SCNNode *)nodeForAnchor:(ARAnchor *)anchor
{
    return [self.nodesByAnchor objectForKey:anchor];
}

- (NSArray<ARHitTestResult *> *)hitTest:(CGPoint)point types:(ARHitTestResultType)types
{
    // Deprecated by the framework in favour of a raycast query, and answered from the frame for the
    // same reason the frame answers it: the arithmetic is one pinhole projection and it lives there.
    return [self.session.currentFrame hitTest:point types:types];
}

- (nullable ARRaycastQuery *)raycastQueryFromPoint:(CGPoint)point
                                    allowingTarget:(ARRaycastTarget)target
                                          alignment:(ARRaycastTargetAlignment)alignment
{
    return [self.session.currentFrame raycastQueryFromPoint:point
                                             allowingTarget:target
                                                   alignment:alignment];
}

@end

NS_ASSUME_NONNULL_END
