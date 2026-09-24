// The SceneKit archive decoder on shapes of archive a scene file can hold. Archives are written here with
// NSKeyedArchiver, by stand-in classes archived under SceneKit's class names, so each case is exactly the shape it
// names. Needs no OpenGL: runs on the emulator (xmake emulate) as well as on a device.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>
#import "check.h"
#include <unistd.h>

// Writes the keys it is given, as a SceneKit or AppKit class would write them: objects, integers and raw bytes.
@interface StandIn : NSObject <NSCoding>
@property (nonatomic, strong) NSDictionary<NSString *, id> *keys;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *integers;
@property (nonatomic, strong) NSDictionary<NSString *, NSData *> *bytes;
@end

@implementation StandIn
@synthesize keys = _keys;
@synthesize integers = _integers;
@synthesize bytes = _bytes;
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    for (NSString *key in _keys) {
        [coder encodeObject:_keys[key] forKey:key];
    }
    for (NSString *key in _integers) {
        [coder encodeInteger:_integers[key].integerValue forKey:key];
    }
    for (NSString *key in _bytes) {
        [coder encodeBytes:_bytes[key].bytes length:_bytes[key].length forKey:key];
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

@interface StandInMaterialProperty : StandIn
@end
@implementation StandInMaterialProperty
@end

// Written under AppKit's NSColor, as a .scn file authored on macOS holds a material's colour.
@interface StandInColor : StandIn
@end
@implementation StandInColor
@end

static id stand_in(Class cls, NSDictionary *keys)
{
    StandIn *object = [cls new];
    object.keys = keys;
    return object;
}

static id stand_in_with(Class cls, NSDictionary *keys, NSDictionary *integers, NSDictionary *bytes)
{
    StandIn *object = stand_in(cls, keys);
    object.integers = integers;
    object.bytes = bytes;
    return object;
}

// A root archived from the stand-ins, decoded by the port with secure coding, as SCNScene's loader does.
static id decode_root(StandIn *root, Class cls, NSString **failure)
{
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"SCNNode" forClass:[StandInNode class]];
    [archiver setClassName:@"SCNGeometry" forClass:[StandInGeometry class]];
    [archiver setClassName:@"SCNMaterialProperty" forClass:[StandInMaterialProperty class]];
    [archiver setClassName:@"NSColor" forClass:[StandInColor class]];
    [archiver encodeObject:root forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    unarchiver.requiresSecureCoding = YES;
    @try {
        return [unarchiver decodeObjectOfClass:cls forKey:NSKeyedArchiveRootObjectKey];
    } @catch (NSException *exception) {
        *failure = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
        return nil;
    }
}

static SCNNode *decode_node(StandInNode *root, NSString **failure)
{
    return decode_root(root, [SCNNode class], failure);
}

// What the block writes to standard error. NSLog writes there as well as to the system log when standard error is
// a regular file.
static NSString *captured_stderr(void (^block)(void))
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scenekit-decode-stderr.XXXXXX"];
    char *name = strdup(path.fileSystemRepresentation);
    int file = mkstemp(name);
    if (file < 0) {
        free(name);
        return nil;
    }
    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    dup2(file, STDERR_FILENO);
    block();
    fflush(stderr);
    dup2(saved, STDERR_FILENO);
    close(saved);
    close(file);
    NSString *text = [NSString stringWithContentsOfFile:@(name) encoding:NSUTF8StringEncoding error:NULL];
    unlink(name);
    free(name);
    return text;
}

static NSUInteger count_lines_containing(NSString *text, NSString *needle)
{
    NSUInteger count = 0;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line rangeOfString:needle].location != NSNotFound) {
            count++;
        }
    }
    return count;
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

// A colour the port cannot read leaves the material property at its default and is said once, naming the key; a
// colour it reads says nothing.
static void check_colours(void)
{
    __block SCNMaterialProperty *property = nil;
    __block NSString *failure = nil;
    StandInColor *catalog = stand_in_with([StandInColor class], nil, @{@"NSColorSpace": @6}, nil);
    NSString *log = captured_stderr(^{
        property = decode_root(stand_in([StandInMaterialProperty class], @{@"color": catalog}), [SCNMaterialProperty class], &failure);
    });
    charon_check(property != nil && property.contents == nil, "an unreadable colour leaves the property at its default",
                 [NSString stringWithFormat:@"property %@, contents %@, %@", property, property.contents, failure]);
    charon_check(log != nil && count_lines_containing(log, @"the colour under color is not read") == 1,
                 "an unreadable colour is said once, naming its key", [NSString stringWithFormat:@"log: %@", log]);

    property = nil;
    failure = nil;
    const char *red = "1 0 0 1";
    StandInColor *device = stand_in_with([StandInColor class], nil, @{@"NSColorSpace": @2},
                                         @{@"NSRGB": [NSData dataWithBytes:red length:strlen(red) + 1]});
    log = captured_stderr(^{
        property = decode_root(stand_in([StandInMaterialProperty class], @{@"color": device}), [SCNMaterialProperty class], &failure);
    });
    CGFloat r = -1, g = -1, b = -1, a = -1;
    BOOL read = [property.contents isKindOfClass:[UIColor class]] && [(UIColor *)property.contents getRed:&r green:&g blue:&b alpha:&a];
    charon_check(read && r == 1 && g == 0 && b == 0 && a == 1, "a device RGB colour is read (control)",
                 [NSString stringWithFormat:@"contents %@, %@", property.contents, failure]);
    charon_check(log != nil && count_lines_containing(log, @"SceneKit:") == 0, "a colour that is read says nothing (control)",
                 [NSString stringWithFormat:@"log: %@", log]);
}

int main(void)
{
    @autoreleasepool {
        check_single_objects();
        check_colours();
        printf("%d of %d checks failed\n", charon_failures, charon_checks);
        return charon_failures;
    }
}
