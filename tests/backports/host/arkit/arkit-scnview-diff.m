// The pairing and the geometry sources, against the host's own SceneKit.
//
// Both are the port's own code and both are observable in SceneKit, so both are measured here rather
// than called documented. What SceneKit cannot observe - the frame's projection and unprojection, which
// the view forwards and which belong to ARFrame and ARCamera - is out of this file and carried as
// documented instead.
//
// The declarations come from ARKitShim.h, so what runs is the port's implementation and not a
// re-implementation: ARSCNView11.m, ARSCNView12.m, ARSCNPlaneGeometry.m and the port's SCNGeometry, all
// compiled against the host's SceneKit. SceneKit reads the geometry back through its own accessors,
// so "the sources SceneKit reads" is checked by asking SceneKit.

#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>
#import "ARKitShim.h"

static int failures = 0;
static void Check(BOOL ok, NSString *what)
{
    printf("  %-64s %s\n", what.UTF8String, ok ? "ok" : "FAIL");
    if (!ok)
        failures++;
}

/// The scaffolding's own types need implementations, not just declarations, or the link is short them.
@implementation UIColor
+ (UIColor *)clearColor { return [UIColor clearColor]; }
+ (UIColor *)whiteColor { return [UIColor whiteColor]; }
+ (UIColor *)blackColor { return [UIColor blackColor]; }
@end

@implementation ARAnchor
@end

@implementation ARFrame
- (NSArray<ARHitTestResult *> *)hitTest:(CGPoint)point types:(ARHitTestResultType)types { return @[]; }
- (ARRaycastQuery *)raycastQueryFromPoint:(CGPoint)point
                           allowingTarget:(ARRaycastTarget)target
                                 alignment:(ARRaycastTargetAlignment)alignment { return nil; }
@end

@implementation ARSession
@end
@implementation ARHitTestResult
@end
@implementation ARRaycastQuery
@end
@implementation ARRaycastResult
@end

/// A plane the way the framework's own `ARPlaneGeometry` describes one: four corners, four texture
/// coordinates, six indices. The numbers are chosen so that a wrong pairing or a wrong stride shows up.
@implementation ARPlaneGeometry
- (NSUInteger)vertexCount { return 4; }
- (NSUInteger)textureCoordinateCount { return 4; }
- (NSUInteger)triangleCount { return 6; }
- (NSUInteger)boundaryVertexCount { return 4; }
- (const simd_float3 *)vertices
{
    static simd_float3 v[4] = { { -0.5f, 0, 0 }, { 0.5f, 0, 0 }, { 0.5f, 0, 1 }, { -0.5f, 0, 1 } };
    return v;
}
- (const simd_float2 *)textureCoordinates
{
    static simd_float2 t[4] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
    return t;
}
- (const int16_t *)triangleIndices
{
    static int16_t i[6] = { 0, 1, 2, 0, 2, 3 };
    return i;
}
- (const simd_float3 *)boundaryVertices { return self.vertices; }
@end

int main(void)
{
    @autoreleasepool {
        // ---- the pairing ----
        ARSCNView *view = [[ARSCNView alloc] initWithFrame:NSMakeRect(0, 0, 320, 240)];
        Check([view isKindOfClass:[SCNView class]], @"the view is a SceneKit view, as the SDK declares it");

        SCNNode *node = [SCNNode node];
        [view.scene.rootNode addChildNode:node];
        ARAnchor *anchor = [[ARAnchor alloc] init];

        Check([view nodeForAnchor:anchor] == nil, @"nothing is paired before anything is added");
        Check([view anchorForNode:node] == nil, @"a node the caller built has no anchor");

        // added
        [view.anchorsByNode setObject:anchor forKey:node];
        [view.nodesByAnchor setObject:node forKey:anchor];
        Check([view nodeForAnchor:anchor] == node, @"an added anchor is paired with its node");
        Check([view anchorForNode:node] == anchor, @"and the node is paired back to the anchor");

        // a node put inside a placed one is the placed node's anchor for this purpose
        SCNNode *child = [SCNNode node];
        [node addChildNode:child];
        Check([view anchorForNode:child] == anchor, @"a child walks up to its placed parent's anchor");

        // follows an update: the pose moves, the pairing does not
        ARAnchor *moved = [[ARAnchor alloc] init];
        moved.transform = (simd_float4x4){{ 1, 0, 0, 0 }, { 0, 1, 0, 0 }, { 0, 0, 1, 0 }, { 1, 2, 3, 1 }};
        [view.nodesByAnchor setObject:node forKey:moved];
        Check([view nodeForAnchor:moved] == node, @"a node follows an anchor that replaced it");
        Check([view nodeForAnchor:anchor] == node, @"and the old pairing is still there to be found");

        // removed
        [view.nodesByAnchor removeObjectForKey:moved];
        Check([view nodeForAnchor:moved] == nil, @"a removed anchor has no node");
        Check([view anchorForNode:node] == anchor, @"and the node's own pairing is untouched by that");

        // ---- the geometry sources ----
        ARSCNPlaneGeometry *geometry = [[ARSCNPlaneGeometry alloc] init];
        [geometry updateFromPlaneGeometry:(ARPlaneGeometry *)[[ARPlaneGeometry alloc] init]];
        // the sources are read back through SceneKit's own accessors
        NSArray<SCNGeometrySource *> *sources = geometry.geometrySources;
        NSArray<SCNGeometryElement *> *elements = geometry.geometryElements;
        Check(sources.count == 2, @"the update leaves two sources: the corners and the coordinates");
        Check(elements.count == 1, @"and one element over the indices");
        SCNGeometrySource *corners = sources.count ? [sources objectAtIndex:0] : nil;
        SCNGeometrySource *coordinates = sources.count > 1 ? [sources objectAtIndex:1] : nil;
        SCNGeometryElement *element = elements.count ? [elements objectAtIndex:0] : nil;
        Check([corners vectorCount] == 4, @"the corner source holds the plane's four corners");
        Check([coordinates vectorCount] == 4, @"and the coordinate source its four pairs");
        Check([element primitiveCount] == 2, @"two triangles out of six indices");
        Check([element bytesPerIndex] == (NSInteger)sizeof(int),
              @"the element says four bytes an index, which is what it was given");

        printf("\nVERDICT %s\n", failures ? "FAIL" : "ok");
        return failures ? 1 : 0;
    }
}
