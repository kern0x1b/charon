#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@class CharonMetalTexture;
@class CharonMetalSampler;

typedef struct {
    GLenum type;
    GLint size;
    GLboolean normalized;
    NSUInteger bytes;
    BOOL floating;
} CharonVertexFormat;

BOOL CharonMetalVertexFormat(MTLVertexFormat format, CharonVertexFormat *out);
void CharonMetalDecodeVertex(MTLVertexFormat format, const uint8_t *bytes, GLfloat out[4]);

@interface MTLFunctionConstantValues (CharonValues)
- (NSDictionary *)valueAtIndex:(NSUInteger)index name:(NSString *)name;
@end

enum { CharonScalarFloat, CharonScalarHalf, CharonScalarI32, CharonScalarI16, CharonScalarI8 };

typedef struct {
    GLint location;
    unsigned buffer;
    NSUInteger offset;
    NSUInteger instanceStride;
    int scalar;
    int components;
} CharonUniformPlan;

typedef struct {
    GLint location;
    unsigned buffer;
    NSUInteger offset;
    NSUInteger stride;
    GLenum type;
    int components;
} CharonAttributePlan;

typedef struct {
    GLint location;
    MTLVertexFormat format;
    CharonVertexFormat decoded;
    unsigned buffer;
    NSUInteger offset;
    NSUInteger stride;
    NSUInteger stepRate;
    MTLVertexStepFunction step;
} CharonInputPlan;

typedef struct {
    GLint location;
    unsigned unit;
} CharonTexturePlan;

typedef struct {
    GLint location;
    unsigned unit;
} CharonSizePlan;

typedef struct {
    GLuint program;
    GLint flip;
    GLint instance;
    GLint vertexId;
    CharonUniformPlan *vertexUniforms;
    unsigned vertexUniformCount;
    CharonUniformPlan *fragmentUniforms;
    unsigned fragmentUniformCount;
    CharonAttributePlan *attributes;
    unsigned attributeCount;
    CharonInputPlan *inputs;
    unsigned inputCount;
    CharonTexturePlan *textures;
    unsigned textureCount;
    CharonSizePlan *sizes;
    unsigned sizeCount;
    BOOL blending;
    GLenum sourceRGB, destinationRGB, sourceAlpha, destinationAlpha, equationRGB, equationAlpha;
    GLboolean mask[4];
} CharonPlan;


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
@property (nonatomic, unsafe_unretained) CharonMetalSampler *appliedSampler;
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
- (CharonMetalFunction *)specializedWith:(MTLFunctionConstantValues *)values error:(NSError **)error;
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
- (const CharonPlan *)plan;
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



extern NSUInteger CharonMetalBindEpoch;

extern NSString *const CharonMetalErrorDomain;
NSError *CharonMetalError(NSInteger code, NSString *message);
id<CAMetalDrawable> CharonMetalNextDrawable(CAMetalLayer *layer);
