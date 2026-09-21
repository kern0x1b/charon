#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@class CharonMetalTexture;

@interface CharonMetalDevice : NSObject <MTLDevice>
@property (nonatomic, readonly) EAGLContext *context;
+ (CharonMetalDevice *)shared;
- (void)acquire;
- (void)relinquish;
@end

@interface CharonMetalBuffer : NSObject <MTLBuffer>
@property (nonatomic, readonly) void *bytes;
@property (nonatomic, readonly) NSUInteger length;
- (instancetype)initWithLength:(NSUInteger)length bytes:(const void *)bytes;
@end

@interface CharonMetalTexture : NSObject <MTLTexture>
@property (nonatomic, readonly) GLuint name;
@property (nonatomic, readonly) GLuint framebuffer;
@property (nonatomic, readonly) BOOL screen;
@property (nonatomic, readonly) MTLPixelFormat pixelFormat;
@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
- (instancetype)initWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (instancetype)initScreenWithFramebuffer:(GLuint)framebuffer width:(NSUInteger)width height:(NSUInteger)height pixelFormat:(MTLPixelFormat)format;
- (GLuint)renderTarget;
@end

@interface CharonMetalSampler : NSObject <MTLSamplerState>
@property (nonatomic, readonly) GLint minFilter;
@property (nonatomic, readonly) GLint magFilter;
@property (nonatomic, readonly) GLint wrapS;
@property (nonatomic, readonly) GLint wrapT;
- (instancetype)initWithDescriptor:(MTLSamplerDescriptor *)descriptor;
@end

@interface CharonMetalFunction : NSObject <MTLFunction>
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *stage;
@property (nonatomic, readonly) NSString *source;
@property (nonatomic, readonly) NSDictionary *reflection;
- (instancetype)initWithName:(NSString *)name stage:(NSString *)stage source:(NSString *)source reflection:(NSDictionary *)reflection;
@end

@interface CharonMetalLibrary : NSObject <MTLLibrary>
- (instancetype)initWithFolder:(NSString *)folder error:(NSError **)error;
@end

@interface CharonMetalPipeline : NSObject <MTLRenderPipelineState>
@property (nonatomic, readonly) GLuint program;
@property (nonatomic, readonly) NSDictionary *vertexReflection;
@property (nonatomic, readonly) NSDictionary *fragmentReflection;
@property (nonatomic, readonly) MTLRenderPipelineDescriptor *descriptor;
- (instancetype)initWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor error:(NSError **)error;
- (GLint)locationForName:(NSString *)name;
- (GLint)attributeForName:(NSString *)name;
@end

@interface CharonMetalQueue : NSObject <MTLCommandQueue>
@end

@interface CharonMetalCommandBuffer : NSObject <MTLCommandBuffer>
@end

@interface CharonMetalEncoder : NSObject <MTLRenderCommandEncoder>
- (instancetype)initWithDescriptor:(MTLRenderPassDescriptor *)descriptor;
@end

@interface CharonMetalDrawable : NSObject <CAMetalDrawable>
- (instancetype)initWithTexture:(CharonMetalTexture *)texture layer:(CAMetalLayer *)layer context:(EAGLContext *)context;
@end

typedef struct {
    GLenum type;
    GLint size;
    GLboolean normalized;
    NSUInteger bytes;
    BOOL floating;
} CharonVertexFormat;

BOOL CharonMetalVertexFormat(MTLVertexFormat format, CharonVertexFormat *out);
void CharonMetalDecodeVertex(MTLVertexFormat format, const uint8_t *bytes, GLfloat out[4]);

extern NSString *const CharonMetalErrorDomain;
NSError *CharonMetalError(NSInteger code, NSString *message);
id<CAMetalDrawable> CharonMetalNextDrawable(CAMetalLayer *layer);
