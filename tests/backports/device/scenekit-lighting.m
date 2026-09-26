// Holds the port's SCNView shader to macOS SceneKit over the lighting grid (host/scenekit/lighting/cases.sh writes
// scenekit-lighting-expectations.h): each case is built through the port's SceneKit from the same data, drawn by
// -snapshot at 8x8 points and scale 1, and its pixel (4, 4) compared with macOS's. A case passes within one level of
// every channel, the residual the fits reach. The negative control: the cases that carry a known-wrong renderer's
// pixel (the specular exponent 132/128 too large, the roughness 0.02 too large) more than two levels from SceneKit's: the port
// must miss that pixel on every one (228 of them for the roughness; none for the exponent, which the grid cannot hold). Needs
// OpenGL ES 2.0, so a device, not the emulator.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>
#import <OpenGLES/ES2/gl.h>
#import "check.h"
#import "scenekit-lighting-expectations.h"

static UIColor *colour(NSArray *c)
{
    return [UIColor colorWithRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:c.count > 3 ? [c[3] doubleValue] : 1];
}

static UIColor *grey(NSNumber *g)
{
    return [UIColor colorWithRed:g.doubleValue green:g.doubleValue blue:g.doubleValue alpha:1];
}

static UIImage *solid_image(UIColor *colour)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), YES, 1);
    [colour setFill];
    UIRectFill(CGRectMake(0, 0, 4, 4));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static SCNGeometry *quad(void)
{
    static const float positions[] = {-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0};
    static const float normals[] = {0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1};
    static const float texcoords[] = {0, 1, 1, 1, 1, 0, 0, 0};
    static const uint16_t indices[] = {0, 1, 2, 0, 2, 3};
    SCNGeometrySource *vertex = [SCNGeometrySource geometrySourceWithData:[NSData dataWithBytes:positions length:sizeof(positions)]
                                                                 semantic:SCNGeometrySourceSemanticVertex vectorCount:4 floatComponents:YES
                                                      componentsPerVector:3 bytesPerComponent:4 dataOffset:0 dataStride:12];
    SCNGeometrySource *normal = [SCNGeometrySource geometrySourceWithData:[NSData dataWithBytes:normals length:sizeof(normals)]
                                                                 semantic:SCNGeometrySourceSemanticNormal vectorCount:4 floatComponents:YES
                                                      componentsPerVector:3 bytesPerComponent:4 dataOffset:0 dataStride:12];
    SCNGeometrySource *texcoord = [SCNGeometrySource geometrySourceWithData:[NSData dataWithBytes:texcoords length:sizeof(texcoords)]
                                                                   semantic:SCNGeometrySourceSemanticTexcoord vectorCount:4 floatComponents:YES
                                                        componentsPerVector:2 bytesPerComponent:4 dataOffset:0 dataStride:8];
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:[NSData dataWithBytes:indices length:sizeof(indices)]
                                                                primitiveType:SCNGeometryPrimitiveTypeTriangles primitiveCount:2 bytesPerIndex:2];
    return [SCNGeometry geometryWithSources:@[vertex, normal, texcoord] elements:@[element]];
}

static SCNScene *scene_for(NSDictionary *c)
{
    SCNScene *scene = [SCNScene scene];
    SCNNode *camera = [SCNNode node];
    camera.camera = [SCNCamera camera];
    camera.camera.usesOrthographicProjection = YES;
    camera.camera.orthographicScale = 1;
    camera.position = SCNVector3Make(0, 0, 5);
    [scene.rootNode addChildNode:camera];
    SCNNode *node = [SCNNode node];
    node.geometry = quad();
    node.eulerAngles = SCNVector3Make([c[@"tilt"] floatValue], 0, 0);
    node.opacity = c[@"opacity"] ? [c[@"opacity"] doubleValue] : 1;
    [scene.rootNode addChildNode:node];
    SCNMaterial *m = [SCNMaterial material];
    node.geometry.materials = @[m];
    m.lightingModelName = [@"SCNLightingModel" stringByAppendingString:c[@"model"]];
    m.diffuse.contents = c[@"diffuseImage"] ? (id)solid_image(colour(c[@"diffuse"])) : (id)colour(c[@"diffuse"]);
    if (c[@"diffuseIntensity"]) m.diffuse.intensity = [c[@"diffuseIntensity"] doubleValue];
    if (c[@"specular"]) m.specular.contents = grey(c[@"specular"]);
    if (c[@"shininess"]) m.shininess = [c[@"shininess"] doubleValue];
    if (c[@"metalness"]) m.metalness.contents = c[@"metalness"];
    if (c[@"roughness"]) m.roughness.contents = c[@"roughness"];
    if (c[@"emission"]) m.emission.contents = grey(c[@"emission"]);
    if (c[@"multiply"]) m.multiply.contents = grey(c[@"multiply"]);
    if (c[@"selfIllumination"]) m.selfIllumination.contents = grey(c[@"selfIllumination"]);
    if (c[@"selfIlluminationIntensity"]) m.selfIllumination.intensity = [c[@"selfIlluminationIntensity"] doubleValue];
    if (c[@"roughnessDefaultAssigned"]) m.roughness.contents = [SCNMaterial material].roughness.contents;
    if (c[@"roughnessIntensity"]) m.roughness.intensity = [c[@"roughnessIntensity"] doubleValue];
    if (c[@"ambientOcclusion"]) m.ambientOcclusion.contents = grey(c[@"ambientOcclusion"]);
    if (c[@"transparency"]) m.transparency = [c[@"transparency"] doubleValue];
    if (c[@"transparent"]) m.transparent.contents = [UIColor colorWithWhite:[c[@"transparent"][0] doubleValue] alpha:[c[@"transparent"][1] doubleValue]];
    if (c[@"ambient"]) {
        m.ambient.contents = grey(c[@"ambient"][0]);
        m.locksAmbientWithDiffuse = [c[@"ambient"][1] boolValue];
    }
    for (NSDictionary *l in c[@"lights"]) {
        SCNNode *holder = [SCNNode node];
        SCNLight *light = [SCNLight light];
        holder.light = light;
        light.type = l[@"type"];
        light.intensity = [l[@"intensity"] doubleValue];
        light.color = colour(l[@"color"] ?: @[@1, @1, @1]);
        if (l[@"start"]) light.attenuationStartDistance = [l[@"start"] doubleValue];
        if (l[@"end"]) light.attenuationEndDistance = [l[@"end"] doubleValue];
        if (l[@"exponent"]) light.attenuationFalloffExponent = [l[@"exponent"] doubleValue];
        if (l[@"inner"]) light.spotInnerAngle = [l[@"inner"] doubleValue];
        if (l[@"outer"]) light.spotOuterAngle = [l[@"outer"] doubleValue];
        NSArray *e = l[@"euler"], *p = l[@"position"];
        if (e) holder.eulerAngles = SCNVector3Make([e[0] floatValue], [e[1] floatValue], [e[2] floatValue]);
        if (p) holder.position = SCNVector3Make([p[0] floatValue], [p[1] floatValue], [p[2] floatValue]);
        [scene.rootNode addChildNode:holder];
    }
    return scene;
}

static int distance(const uint8_t *px, NSArray *want)
{
    int worst = 0;
    for (int k = 0; k < 4; k++) {
        int d = abs((int)px[k] - [want[k] intValue]);
        worst = d > worst ? d : worst;
    }
    return worst;
}

static void pixel_of(SCNView *view, SCNScene *scene, uint8_t px[4])
{
    view.scene = scene;
    UIImage *image = [view snapshot];
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
    memcpy(px, CFDataGetBytePtr(data) + 4 * CGImageGetBytesPerRow(image.CGImage) + 4 * 4, 4);
    CFRelease(data);
}

static CABasicAnimation *hold_position(float x, float y, float z)
{
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
    animation.fromValue = [NSValue valueWithSCNVector3:SCNVector3Make(x, y, z)];
    animation.toValue = animation.fromValue;
    animation.duration = 1;
    return animation;
}

static SCNNode *light_node(SCNScene *scene)
{
    for (SCNNode *node in scene.rootNode.childNodes) {
        if (node.light) return node;
    }
    return nil;
}

static SCNNode *camera_node(SCNScene *scene)
{
    for (SCNNode *node in scene.rootNode.childNodes) {
        if (node.camera) return node;
    }
    return nil;
}

// A light and a camera are placed where the frame's animations put them, as a mesh is: the pixel of a scene whose light
// (or its parent, or the camera) holds an animated position must be the pixel of a scene with that position set.
static void check_presented(SCNView *view)
{
    NSDictionary *(^omni)(float) = ^(float z) {
        return @{@"name": @"presented", @"model": @"Blinn", @"diffuse": @[@0.5, @0.5, @0.5, @1],
                 @"lights": @[@{@"type": @"omni", @"intensity": @1000, @"end": @20, @"position": @[@0, @0, @(z)]}]};
    };
    uint8_t near[4], far[4], animated[4], parented[4];
    pixel_of(view, scene_for(omni(2)), near);
    pixel_of(view, scene_for(omni(4)), far);
    charon_check(abs((int)near[0] - (int)far[0]) > 4, "the light at 2 and at 4 draw different pixels", [NSString stringWithFormat:@"%d and %d", near[0], far[0]]);
    SCNScene *lit = scene_for(omni(4));
    [light_node(lit) addAnimation:hold_position(0, 0, 2) forKey:@"held"];
    pixel_of(view, lit, animated);
    charon_check(memcmp(near, animated, 4) == 0, "a light whose position is animated is drawn at the presented position",
                 [NSString stringWithFormat:@"%d, presented position gives %d, model position gives %d", animated[0], near[0], far[0]]);
    SCNScene *under = scene_for(omni(0));
    SCNNode *parent = [SCNNode node];
    [under.rootNode addChildNode:parent];
    [parent addChildNode:light_node(under)];
    [parent addAnimation:hold_position(0, 0, 2) forKey:@"held"];
    pixel_of(view, under, parented);
    charon_check(memcmp(near, parented, 4) == 0, "a light under a parent whose position is animated is drawn at the presented position",
                 [NSString stringWithFormat:@"%d, presented position gives %d", parented[0], near[0]]);
    uint8_t seen[4], gone[4], moved[4];
    NSDictionary *plain = @{@"name": @"presented", @"model": @"Constant", @"diffuse": @[@0.5, @0.5, @0.5, @1], @"lights": @[]};
    pixel_of(view, scene_for(plain), seen);
    SCNScene *away = scene_for(plain);
    camera_node(away).position = SCNVector3Make(10, 0, 5);
    pixel_of(view, away, gone);
    charon_check(memcmp(seen, gone, 4) != 0, "the camera at x = 10 sees other pixels than the camera at x = 0", [NSString stringWithFormat:@"%d and %d", seen[3], gone[3]]);
    SCNScene *panned = scene_for(plain);
    [camera_node(panned) addAnimation:hold_position(10, 0, 5) forKey:@"held"];
    pixel_of(view, panned, moved);
    charon_check(memcmp(gone, moved, 4) == 0, "a camera whose position is animated looks from the presented position",
                 [NSString stringWithFormat:@"%d, presented position gives %d, model position gives %d", moved[3], gone[3], seen[3]]);
}

static int distance_between(NSArray *a, NSArray *b)
{
    uint8_t px[4];
    for (int k = 0; k < 4; k++) {
        px[k] = (uint8_t)[a[k] intValue];
    }
    return distance(px, b);
}

int main(void)
{
    @autoreleasepool {
        NSError *error = nil;
        NSArray *cases = [NSJSONSerialization JSONObjectWithData:[@(scenekit_lighting_expectations) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
        CHECK(cases.count > 0, "the host's cases are readable");
        SCNView *view = [[SCNView alloc] initWithFrame:CGRectMake(0, 0, 8, 8)];
        view.contentScaleFactor = 1;
        view.backgroundColor = [UIColor clearColor];
        if (view.eaglContext == nil) {
            printf("FAIL no OpenGL ES 2.0 context: this test needs a device\n");
            return 1;
        }
        // what the GPU's fragment floats hold: the renderer's precision qualifiers rest on this (facts/SceneKit/SCNView.md)
        [EAGLContext setCurrentContext:view.eaglContext];
        GLenum kinds[2] = {GL_MEDIUM_FLOAT, GL_HIGH_FLOAT};
        for (int k = 0; k < 2; k++) {
            GLint range[2] = {0, 0}, precision = 0;
            glGetShaderPrecisionFormat(GL_FRAGMENT_SHADER, kinds[k], range, &precision);
            printf("fragment %s float: range 2^-%d to 2^%d, %d bits of precision\n", k ? "highp" : "mediump", range[0], range[1], precision);
        }
        int within = 0, outside = 0, histogram[256] = {0};
        NSMutableDictionary<NSString *, NSNumber *> *mutantCases = [NSMutableDictionary dictionary], *mutantMissed = [NSMutableDictionary dictionary];
        for (NSDictionary *c in cases) {
            @autoreleasepool {
                view.scene = scene_for(c);
                UIImage *image = [view snapshot];
                CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage));
                const uint8_t *bytes = CFDataGetBytePtr(data);
                size_t row = CGImageGetBytesPerRow(image.CGImage);
                uint8_t px[4];
                memcpy(px, bytes + 4 * row + 4 * 4, 4);
                CFRelease(data);
                int d = distance(px, c[@"expected"]);
                histogram[d]++;
                if (d <= 1) {
                    within++;
                } else {
                    outside++;
                    printf("FAIL %s: port (%d, %d, %d, %d), SceneKit %s, off by %d\n", [c[@"name"] UTF8String], px[0], px[1], px[2], px[3],
                           [[c[@"expected"] componentsJoinedByString:@", "] UTF8String], d);
                }
                // a port within one level of SceneKit's pixel is surely off the wrong renderer's when that differs from
                // SceneKit's by more than two levels: only those cases can tell the two apart
                if (c[@"mutant"] && distance_between(c[@"mutant"], c[@"expected"]) > 2) {
                    NSString *kind = c[@"shininess"] ? @"exponent 132/128" : @"roughness +0.02";
                    mutantCases[kind] = @(mutantCases[kind].intValue + 1);
                    if (distance(px, c[@"mutant"]) > 1) {
                        mutantMissed[kind] = @(mutantMissed[kind].intValue + 1);
                    }
                }
            }
        }
        charon_check(outside == 0, "every case within one level of SceneKit's pixel",
                     [NSString stringWithFormat:@"%d of %lu cases outside", outside, (unsigned long)cases.count]);
        printf("cases %lu, within one level %d; off by 0: %d, 1: %d, 2: %d, 3+: %d\n", (unsigned long)cases.count, within,
               histogram[0], histogram[1], histogram[2], (int)cases.count - histogram[0] - histogram[1] - histogram[2]);
        // The roughness control: 228 cases of the grid's data carry a wrong pixel more than two levels from SceneKit's, and the
        // port must miss it on every one. The exponent control has none (its wrong renderer is within two levels of SceneKit's
        // pixel on every case, and more than one on 18 of 192): the grid cannot tell an exponent 3% too large from the fit, and
        // says so here rather than passing a check that cannot fail.
        for (NSString *kind in @[@"exponent 132/128", @"roughness +0.02"]) {
            int missed = mutantMissed[kind].intValue, total = mutantCases[kind].intValue;
            printf("negative control %s: the port misses the wrong renderer's pixel on %d of the %d cases that differ from SceneKit's by more than two levels\n", kind.UTF8String, missed, total);
        }
        int roughMissed = mutantMissed[@"roughness +0.02"].intValue, roughTotal = mutantCases[@"roughness +0.02"].intValue;
        charon_check(roughMissed == roughTotal && roughTotal >= 228, "the check tells a renderer with roughness 0.02 too large from SceneKit",
                     [NSString stringWithFormat:@"%d of %d, at least 228 wanted", roughMissed, roughTotal]);
        check_presented(view);
        printf("%d of %d checks failed\n", charon_failures, charon_checks);
        return charon_failures;
    }
}
