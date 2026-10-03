#import "CharonMetal.h"


// The 12.0 blits. -optimizeContentsFor{CPU,GPU}Access: is a hint about where a resource's bytes
// should live for speed, and on this device the answer is already the case for every resource: a
// buffer is its own bytes and a texture is an OpenGL ES 2.0 texture the port reads and writes on the
// CPU, so there is nothing to move and nothing to migrate. The API asks for a performance, not for
// a value, and the performance is the one it asks for, which is why these do what doing nothing
// means here rather than refusing.
//
// The three indirect-command-buffer blits of 12.0 take an MTLIndirectCommandBuffer, which this port
// does not carry; MTLIndirectCommandBuffer is in registry/Metal/absent_Metal.json as absent, with the
// effect that says so.

// The four access hints are a hint to a memory migrator this device does not have: every resource of
// the port is CPU-resident already, so there is nothing to move between two residency modes that do
// not exist. They are inert rather than implemented, and the registry says so, because the API asks
// for a performance and not for a value: the performance is the one it asks for. The log says it once
// the first time, the way an inert entry of this package does.
static void CharonMetalBlitAccessHintIsInert(NSString *what, id<MTLTexture>texture)
{
    static BOOL said;
    if (said)
        return;
    said = YES;
    NSLog(@"Metal: %@ is kept and does nothing: every resource of this port is CPU-resident already, so there is no residency to move it between (texture %@)",
          what, [(id)texture label] ? [(id)texture label] : @"(no label)");
}

@implementation CharonMetalBlitEncoder (Optimize)

- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture
{
    CharonMetalBlitAccessHintIsInert(@"optimizeContentsForCPUAccess:", texture);
}

- (void)optimizeContentsForCPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level
{
    CharonMetalBlitAccessHintIsInert(@"optimizeContentsForCPUAccess:slice:level:", texture);
}

- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture
{
    CharonMetalBlitAccessHintIsInert(@"optimizeContentsForGPUAccess:", texture);
}

- (void)optimizeContentsForGPUAccess:(id<MTLTexture>)texture slice:(NSUInteger)slice level:(NSUInteger)level
{
    CharonMetalBlitAccessHintIsInert(@"optimizeContentsForGPUAccess:slice:level:", texture);
}

@end

