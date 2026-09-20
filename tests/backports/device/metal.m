#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <dlfcn.h>
#import "check.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wobjc-method-access"
#pragma clang diagnostic ignored "-Wnonnull"

static NSString *const results_folder = @"/private/var/backports";

typedef struct { float position[2]; float texture[2]; } Corner;

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;
@property (nonatomic, strong) id<MTLLibrary> library;
@end

static BOOL comes_from_backports(Class cls)
{
    Dl_info info;
    return cls && dladdr((__bridge void *)cls, &info) != 0 && [@(info.dli_fname).lastPathComponent isEqualToString:@"libMetalBackports.dylib"];
}

@implementation Delegate

- (id<MTLRenderPipelineState>)pipelineBlending:(BOOL)blending
{
    MTLRenderPipelineDescriptor *d = [[MTLRenderPipelineDescriptor alloc] init];
    d.vertexFunction = [self.library newFunctionWithName:@"quadVertex"];
    d.fragmentFunction = [self.library newFunctionWithName:@"quadFragment"];
    d.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    if (blending) {
        d.colorAttachments[0].blendingEnabled = YES;
        d.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        d.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }
    NSError *error = nil;
    id<MTLRenderPipelineState> state = [self.device newRenderPipelineStateWithDescriptor:d error:&error];
    CHECK(state != nil, blending ? "a blending pipeline is made" : "a pipeline is made");
    return state;
}

- (void)draw:(id<MTLTexture>)target pipeline:(id<MTLRenderPipelineState>)pipeline tint:(const float *)tint indexed:(BOOL)indexed clear:(MTLClearColor)clear picture:(id<MTLTexture>)picture
{
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = clear;
    MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
    sd.minFilter = MTLSamplerMinMagFilterNearest;
    sd.magFilter = MTLSamplerMinMagFilterNearest;
    id<MTLSamplerState> nearest = [self.device newSamplerStateWithDescriptor:sd];
    id<MTLCommandBuffer> buffer = [self.queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    Corner corners[6] = {
        {{-1, 1}, {0, 0}}, {{1, 1}, {1, 0}}, {{-1, -1}, {0, 1}},
        {{1, 1}, {1, 0}}, {{1, -1}, {1, 1}}, {{-1, -1}, {0, 1}}};
    Corner four[4] = {{{-1, 1}, {0, 0}}, {{1, 1}, {1, 0}}, {{-1, -1}, {0, 1}}, {{1, -1}, {1, 1}}};
    uint16_t indices[6] = {0, 1, 2, 1, 3, 2};
    float scale = 1;
    [encoder setRenderPipelineState:pipeline];
    if (indexed)
        [encoder setVertexBytes:four length:sizeof four atIndex:0];
    else
        [encoder setVertexBytes:corners length:sizeof corners atIndex:0];
    [encoder setVertexBytes:&scale length:sizeof scale atIndex:1];
    [encoder setFragmentTexture:picture atIndex:0];
    [encoder setFragmentSamplerState:nearest atIndex:0];
    [encoder setFragmentBytes:tint length:16 atIndex:0];
    if (indexed) {
        id<MTLBuffer> index = [self.device newBufferWithBytes:indices length:sizeof indices options:0];
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6 indexType:MTLIndexTypeUInt16 indexBuffer:index indexBufferOffset:0];
    } else {
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }
    [encoder endEncoding];
    [buffer commit];
    [buffer waitUntilCompleted];
}

- (void)read:(id<MTLTexture>)texture width:(NSUInteger)w height:(NSUInteger)h into:(uint8_t *)out
{
    [texture getBytes:out bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
}

static BOOL near(const uint8_t *p, int r, int g, int b, int tolerance)
{
    return abs(p[0] - r) <= tolerance && abs(p[1] - g) <= tolerance && abs(p[2] - b) <= tolerance;
}

- (void)runAndFinish
{
    CHECK(comes_from_backports(NSClassFromString(@"MTLTextureDescriptor")), "the texture descriptor comes from the backports");
    CHECK(comes_from_backports(NSClassFromString(@"MTLRenderPassDescriptor")), "the render pass descriptor comes from the backports");
    CHECK(comes_from_backports(NSClassFromString(@"MTLRenderPipelineDescriptor")), "the render pipeline descriptor comes from the backports");
    CHECK(comes_from_backports(NSClassFromString(@"MTLSamplerDescriptor")), "the sampler descriptor comes from the backports");
    CHECK(NSClassFromString(@"MTKView") == Nil, "MetalKit is not there");
    CHECK(NSClassFromString(@"MTLDepthStencilDescriptor") == Nil, "depth and stencil descriptors are not there");

    self.device = MTLCreateSystemDefaultDevice();
    CHECK(self.device != nil, "there is a default device");
    CHECK(MTLCreateSystemDefaultDevice() == self.device, "and it is the same the second time");
    CHECK(self.device.name.length > 0, "it has a name");
    CHECK(![self.device supportsFamily:MTLGPUFamilyApple1], "it supports no family");
    CHECK(![self.device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v1], "and no feature set");
    self.queue = [self.device newCommandQueue];
    CHECK(self.queue != nil, "it makes a command queue");

    NSString *folder = [[NSBundle mainBundle] pathForResource:@"quad" ofType:@"metallib.es2"];
    CHECK(folder != nil, "the translated library is in the bundle");
    NSError *error = nil;
    self.library = [self.device newLibraryWithFile:[folder stringByDeletingPathExtension] error:&error];
    CHECK(self.library != nil, "a library is read from beside its file");
    CHECK([[[self.library functionNames] sortedArrayUsingSelector:@selector(compare:)] isEqualToArray:(@[@"quadFragment", @"quadVertex"])], "it holds its two functions");
    CHECK([self.library newFunctionWithName:@"missing"] == nil, "a name it does not hold gives nil");
    CHECK([[self.library newFunctionWithName:@"quadVertex"] functionType] == MTLFunctionTypeVertex, "the vertex function is a vertex function");
    CHECK([[self.library newFunctionWithName:@"quadFragment"] functionType] == MTLFunctionTypeFragment, "and the fragment function a fragment function");
    error = nil;
    CHECK([self.device newLibraryWithFile:@"/nonexistent.metallib" error:&error] == nil && error != nil, "a library that is not there is an error");
    error = nil;
    CHECK([self.device newLibraryWithSource:@"kernel void f() {}" options:nil error:&error] == nil && error != nil, "source is not compiled");
    error = nil;
    CHECK([self.device newLibraryWithData:(id)[NSData data] error:&error] == nil && error != nil, "a library in memory is an error");

    error = nil;
    MTLRenderPipelineDescriptor *incomplete = [[MTLRenderPipelineDescriptor alloc] init];
    CHECK([self.device newRenderPipelineStateWithDescriptor:incomplete error:&error] == nil && error != nil, "a pipeline with no functions is an error");
    error = nil;
    CHECK([self.device newComputePipelineStateWithFunction:[self.library newFunctionWithName:@"quadVertex"] error:&error] == nil && error != nil, "a compute pipeline is an error");
    CHECK([self.device newDepthStencilStateWithDescriptor:nil] == nil, "a depth and stencil state is nil");
    MTLSamplerDescriptor *border = [[MTLSamplerDescriptor alloc] init];
    border.sAddressMode = MTLSamplerAddressModeClampToZero;
    CHECK([self.device newSamplerStateWithDescriptor:border] == nil, "a sampler that clamps to zero is nil");
    MTLTextureDescriptor *srgb = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB width:4 height:4 mipmapped:NO];
    CHECK([self.device newTextureWithDescriptor:srgb] == nil, "an sRGB texture is nil");
    id<MTLCommandBuffer> spare = [self.queue commandBuffer];
    CHECK([spare computeCommandEncoder] == nil && [spare blitCommandEncoder] == nil, "the compute and blit encoders are nil");

    MTLTextureDescriptor *pd = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
    id<MTLTexture> picture = [self.device newTextureWithDescriptor:pd];
    CHECK(picture != nil && picture.width == 2 && picture.height == 2 && picture.pixelFormat == MTLPixelFormatRGBA8Unorm, "a texture is made with its size and format");
    const uint8_t texels[16] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255};
    [picture replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:texels bytesPerRow:8];

    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> target = [self.device newTextureWithDescriptor:td];
    id<MTLRenderPipelineState> plain = [self pipelineBlending:NO];
    static uint8_t out[64 * 64 * 4];
    const float white[4] = {1, 1, 1, 1};
    for (int indexed = 0; indexed < 2; indexed++) {
        [self draw:target pipeline:plain tint:white indexed:indexed clear:MTLClearColorMake(0, 0, 0, 1) picture:picture];
        [self read:target width:64 height:64 into:out];
        const uint8_t *tl = out + (16 * 64 + 16) * 4, *tr = out + (16 * 64 + 48) * 4, *bl = out + (48 * 64 + 16) * 4, *br = out + (48 * 64 + 48) * 4;
        CHECK(near(tl, 0, 0, 255, 1), indexed ? "indexed: top left is the first texel, red and blue swapped by the shader" : "arrays: top left is the first texel, red and blue swapped by the shader");
        CHECK(near(tr, 0, 255, 0, 1), indexed ? "indexed: top right is the second texel" : "arrays: top right is the second texel");
        CHECK(near(bl, 255, 0, 0, 1), indexed ? "indexed: bottom left is the third texel, swapped" : "arrays: bottom left is the third texel, swapped");
        CHECK(near(br, 255, 255, 255, 1), indexed ? "indexed: bottom right is the fourth texel" : "arrays: bottom right is the fourth texel");
    }

    const float faint[4] = {0.5f, 0.5f, 0.5f, 0.4f};
    [self draw:target pipeline:plain tint:faint indexed:NO clear:MTLClearColorMake(0, 0, 0, 1) picture:picture];
    [self read:target width:64 height:64 into:out];
    const uint8_t *tl = out + (16 * 64 + 16) * 4;
    CHECK(near(tl, 128, 0, 0, 2), "a tint below the alpha of the test is not swapped and scales the colour");
    id<MTLRenderPipelineState> blended = [self pipelineBlending:YES];
    [self draw:target pipeline:blended tint:faint indexed:NO clear:MTLClearColorMake(0, 0, 0, 1) picture:picture];
    [self read:target width:64 height:64 into:out];
    CHECK(near(tl, 51, 0, 0, 2), "blending by source alpha over the cleared colour gives the mixed colour");

    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.frame = CGRectMake(0, 0, 100, 60);
    layer.contentsScale = 1;
    CHECK([layer nextDrawable] == nil, "a layer with no device has no drawable");
    layer.device = self.device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    [self.window.rootViewController.view.layer addSublayer:layer];
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    CHECK(drawable != nil, "a layer with the device has a drawable");
    CHECK(drawable.texture.width == 100 && drawable.texture.height == 60, "its texture is the size of the layer");
    CHECK(drawable.layer == layer, "and it names its layer");
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0.5, 1);
    id<MTLCommandBuffer> frame = [self.queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [frame renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    uint8_t pixel[4] = {0, 0, 0, 0};
    [drawable.texture getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(50, 30, 1, 1) mipmapLevel:0];
    [frame presentDrawable:drawable];
    [frame commit];
    [frame waitUntilCompleted];
    CHECK(abs(pixel[0] - 128) <= 1 && pixel[1] == 0 && pixel[2] == 255, "the drawable holds what the pass cleared it to, in the order of its BGRA format");
    id<CAMetalDrawable> second = [layer nextDrawable];
    CHECK(second != nil && second != drawable, "the next drawable is another");

    NSString *summary = [NSString stringWithFormat:@"%d checks, %d failed\n", charon_checks, charon_failures];
    [summary writeToFile:[results_folder stringByAppendingPathComponent:@"metal.done"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    [[NSFileManager defaultManager] createDirectoryAtPath:results_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[results_folder stringByAppendingPathComponent:@"metal.done"] error:NULL];
    charon_log_to([results_folder stringByAppendingPathComponent:@"metal.log"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(runAndFinish) withObject:nil afterDelay:0.3];
    return YES;
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([Delegate class]));
    }
}
