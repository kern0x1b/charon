// The SceneKit archive decoder on shapes of archive a scene file can hold. Archives are written here with
// NSKeyedArchiver, by stand-in classes archived under SceneKit's class names, so each case is exactly the shape it
// names. Needs no OpenGL: runs on the emulator (xmake emulate) as well as on a device.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>
#import "check.h"

// Writes the keys it is given, as a SceneKit class would write them.
@interface StandIn : NSObject <NSCoding>
@property (nonatomic, strong) NSDictionary<NSString *, id> *keys;
@end

@implementation StandIn
@synthesize keys = _keys;
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    for (NSString *key in _keys) {
        [coder encodeObject:_keys[key] forKey:key];
    }
}
@end

@interface StandInNode : StandIn
@end
@implementation StandInNode
@end

@interface StandInGeometry : StandIn
@end
@implementation StandInGeometry
@end

static id stand_in(Class cls, NSDictionary *keys)
{
    StandIn *object = [cls new];
    object.keys = keys;
    return object;
}

// A node archived from the stand-ins, decoded by the port with secure coding, as SCNScene's loader does.
static SCNNode *decode_node(StandInNode *root, NSString **failure)
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"SCNNode" forClass:[StandInNode class]];
    [archiver setClassName:@"SCNGeometry" forClass:[StandInGeometry class]];
    [archiver encodeObject:root forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    unarchiver.requiresSecureCoding = YES;
    @try {
        return [unarchiver decodeObjectOfClass:[SCNNode class] forKey:NSKeyedArchiveRootObjectKey];
    } @catch (NSException *exception) {
        *failure = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
        return nil;
    }
}

static void check_single_objects(void)
{
    NSString *failure = nil;
    SCNNode *node = decode_node(stand_in([StandInNode class], @{@"particleSystem": [SCNParticleSystem particleSystem]}), &failure);
    charon_check(node != nil && node.particleSystems.count == 1, "a single particle system under particleSystem is one system",
                 [NSString stringWithFormat:@"node %@, systems %lu, %@", node, (unsigned long)node.particleSystems.count, failure]);

    failure = nil;
    node = decode_node(stand_in([StandInNode class], @{@"particleSystems": [SCNParticleSystem particleSystem]}), &failure);
    charon_check(node != nil && node.particleSystems.count == 1, "a single particle system under particleSystems is one system",
                 [NSString stringWithFormat:@"node %@, %@", node, failure]);

    failure = nil;
    node = decode_node(stand_in([StandInNode class], @{@"particleSystems": @[[SCNParticleSystem particleSystem], [SCNParticleSystem particleSystem]]}), &failure);
    charon_check(node != nil && node.particleSystems.count == 2, "an array of two particle systems is two systems (control)",
                 [NSString stringWithFormat:@"node %@, %@", node, failure]);

    failure = nil;
    StandInNode *child = stand_in([StandInNode class], @{@"name": @"child"});
    node = decode_node(stand_in([StandInNode class], @{@"childNodes": child}), &failure);
    charon_check(node != nil && node.childNodes.count == 1 && [node.childNodes.firstObject.name isEqualToString:@"child"],
                 "a single child under childNodes is one child", [NSString stringWithFormat:@"node %@, %@", node, failure]);

    failure = nil;
    StandInGeometry *geometry = stand_in([StandInGeometry class], @{@"materials": [SCNMaterial material],
                                                                  @"elements": [SCNGeometryElement geometryElementWithData:[NSData dataWithBytes:(uint16_t[]){0, 1, 2} length:6]
                                                                                                             primitiveType:SCNGeometryPrimitiveTypeTriangles primitiveCount:1 bytesPerIndex:2]});
    node = decode_node(stand_in([StandInNode class], @{@"geometry": geometry}), &failure);
    charon_check(node.geometry.materials.count == 1 && node.geometry.geometryElements.count == 1,
                 "a single material and a single element are one of each", [NSString stringWithFormat:@"geometry %@, %@", node.geometry, failure]);
}

int main(void)
{
    @autoreleasepool {
        check_single_objects();
        printf("%d of %d checks failed\n", charon_failures, charon_checks);
        return charon_failures;
    }
}
