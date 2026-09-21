#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

typedef struct {
    GLint internal;
    GLenum format;
    GLenum type;
    NSUInteger bytes;
} CharonFormat;

static BOOL formatFor(MTLPixelFormat pixelFormat, CharonFormat *out)
{
    switch ((NSUInteger)pixelFormat) {
    case 70: *out = (CharonFormat){GL_RGBA, GL_RGBA, GL_UNSIGNED_BYTE, 4}; return YES;
    case 80: *out = (CharonFormat){GL_RGBA, GL_BGRA_EXT, GL_UNSIGNED_BYTE, 4}; return YES;
    case 10: *out = (CharonFormat){GL_RED_EXT, GL_RED_EXT, GL_UNSIGNED_BYTE, 1}; return YES;
    case 30: *out = (CharonFormat){GL_RG_EXT, GL_RG_EXT, GL_UNSIGNED_BYTE, 2}; return YES;
    default: return NO;
    }
}

NSUInteger CharonMetalBindEpoch;

@implementation CharonMetalTexture {
    GLuint _name;
    GLuint _framebuffer;
    BOOL _screen;
    MTLPixelFormat _pixelFormat;
    NSUInteger _width;
    NSUInteger _height;
    MTLTextureUsage _usage;
    __unsafe_unretained CharonMetalSampler *_appliedSampler;
    int _kind;
    GLuint _renderbuffer;
    GLuint _checkedDepth, _checkedStencil;
}

@synthesize label;

static int depthKind(MTLPixelFormat pixelFormat)
{
    switch ((NSUInteger)pixelFormat) {
    case 250: case 252: return 1;
    case 253: return 3;
    case 255: case 260: return 2;
    default: return 0;
    }
}

- (instancetype)initWithDepthDescriptor:(MTLTextureDescriptor *)descriptor kind:(int)kind
{
    if (descriptor.textureType != MTLTextureType2D || descriptor.sampleCount != 1 || descriptor.width == 0 || descriptor.height == 0)
        return nil;
    if ((self = [super init])) {
        _pixelFormat = descriptor.pixelFormat;
        _width = descriptor.width;
        _height = descriptor.height;
        _usage = descriptor.usage;
        _kind = kind;
        CharonMetalDevice *device = [CharonMetalDevice shared];
        [device acquire];
        if (kind == 3) {
            glGenRenderbuffers(1, &_renderbuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, (GLsizei)_width, (GLsizei)_height);
        } else {
            CharonMetalBindEpoch++;
            glGenTextures(1, &_name);
            glBindTexture(GL_TEXTURE_2D, _name);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            if (kind == 2)
                glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_STENCIL_OES, (GLsizei)_width, (GLsizei)_height, 0, GL_DEPTH_STENCIL_OES, GL_UNSIGNED_INT_24_8_OES, NULL);
            else
                glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, (GLsizei)_width, (GLsizei)_height, 0, GL_DEPTH_COMPONENT, (NSUInteger)descriptor.pixelFormat == 250 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT, NULL);
        }
        [device relinquish];
    }
    return self;
}

- (GLuint)checkedDepth
{
    return _checkedDepth;
}

- (void)setCheckedDepth:(GLuint)value
{
    _checkedDepth = value;
}

- (GLuint)checkedStencil
{
    return _checkedStencil;
}

- (void)setCheckedStencil:(GLuint)value
{
    _checkedStencil = value;
}

- (int)attachmentKind
{
    return _kind;
}

- (GLuint)renderbuffer
{
    return _renderbuffer;
}

- (instancetype)initWithDescriptor:(MTLTextureDescriptor *)descriptor
{
    int depth = depthKind(descriptor.pixelFormat);
    if (depth)
        return [self initWithDepthDescriptor:descriptor kind:depth];
    CharonFormat format;
    if (descriptor.textureType != MTLTextureType2D || !formatFor(descriptor.pixelFormat, &format) || descriptor.sampleCount != 1 || descriptor.width == 0 || descriptor.height == 0) {
        NSLog(@"Metal: texture of type %d, pixel format %d, %d samples has no OpenGL ES 2.0 form", (int)descriptor.textureType, (int)descriptor.pixelFormat, (int)descriptor.sampleCount);
        return nil;
    }
    if ((self = [super init])) {
        _pixelFormat = descriptor.pixelFormat;
        _width = descriptor.width;
        _height = descriptor.height;
        _usage = descriptor.usage;
        CharonMetalDevice *device = [CharonMetalDevice shared];
        [device acquire];
        CharonMetalBindEpoch++;
        glGenTextures(1, &_name);
        glBindTexture(GL_TEXTURE_2D, _name);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, format.internal, (GLsizei)_width, (GLsizei)_height, 0, format.format, format.type, NULL);
        [device relinquish];
    }
    return self;
}

- (instancetype)initScreenWithFramebuffer:(GLuint)framebuffer width:(NSUInteger)width height:(NSUInteger)height pixelFormat:(MTLPixelFormat)format
{
    if ((self = [super init])) {
        _screen = YES;
        _framebuffer = framebuffer;
        _width = width;
        _height = height;
        _pixelFormat = format;
        _usage = MTLTextureUsageRenderTarget;
    }
    return self;
}

- (void)dealloc
{
    if (!_screen && (_name || _renderbuffer)) {
        CharonMetalDevice *device = [CharonMetalDevice shared];
        [device acquire];
        if (_framebuffer)
            glDeleteFramebuffers(1, &_framebuffer);
        if (_name)
            glDeleteTextures(1, &_name);
        if (_renderbuffer)
            glDeleteRenderbuffers(1, &_renderbuffer);
        [device relinquish];
    }
}

- (CharonMetalSampler *)appliedSampler
{
    return _appliedSampler;
}

- (void)setAppliedSampler:(CharonMetalSampler *)sampler
{
    _appliedSampler = sampler;
}

- (GLuint)name
{
    return _name;
}

- (GLuint)framebuffer
{
    return _framebuffer;
}

- (BOOL)screen
{
    return _screen;
}

- (GLuint)renderTarget
{
    if (_screen)
        return _framebuffer;
    if (!_framebuffer) {
        glGenFramebuffers(1, &_framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _name, 0);
    }
    return _framebuffer;
}

- (MTLPixelFormat)pixelFormat
{
    return _pixelFormat;
}

- (NSUInteger)width
{
    return _width;
}

- (NSUInteger)height
{
    return _height;
}

- (NSUInteger)depth
{
    return 1;
}

- (NSUInteger)mipmapLevelCount
{
    return 1;
}

- (NSUInteger)sampleCount
{
    return 1;
}

- (NSUInteger)arrayLength
{
    return 1;
}

- (MTLTextureType)textureType
{
    return MTLTextureType2D;
}

- (MTLTextureUsage)usage
{
    return _usage;
}

- (BOOL)isFramebufferOnly
{
    return _screen;
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

- (MTLResourceOptions)resourceOptions
{
    return MTLResourceStorageModeShared;
}

- (MTLStorageMode)storageMode
{
    return MTLStorageModeShared;
}

- (void)replaceRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level withBytes:(const void *)pointer bytesPerRow:(NSUInteger)bytesPerRow
{
    CharonFormat format;
    if (_screen || _kind || level != 0 || !formatFor(_pixelFormat, &format))
        return;
    CharonMetalDevice *device = [CharonMetalDevice shared];
    [device acquire];
    CharonMetalBindEpoch++;
    glBindTexture(GL_TEXTURE_2D, _name);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    NSUInteger rowBytes = region.size.width * format.bytes;
    if (bytesPerRow == rowBytes) {
        glTexSubImage2D(GL_TEXTURE_2D, 0, (GLint)region.origin.x, (GLint)region.origin.y, (GLsizei)region.size.width, (GLsizei)region.size.height, format.format, format.type, pointer);
    } else {
        for (NSUInteger row = 0; row < region.size.height; row++)
            glTexSubImage2D(GL_TEXTURE_2D, 0, (GLint)region.origin.x, (GLint)(region.origin.y + row), (GLsizei)region.size.width, 1, format.format, format.type, (const uint8_t *)pointer + row * bytesPerRow);
    }
    [device relinquish];
}

- (void)getBytes:(void *)pointer bytesPerRow:(NSUInteger)bytesPerRow fromRegion:(MTLRegion)region mipmapLevel:(NSUInteger)level
{
    CharonFormat format;
    if (_kind || level != 0 || !formatFor(_pixelFormat, &format))
        return;
    CharonMetalDevice *device = [CharonMetalDevice shared];
    [device acquire];
    GLint previous;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previous);
    glBindFramebuffer(GL_FRAMEBUFFER, [self renderTarget]);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    GLenum readFormat = format.format == GL_BGRA_EXT ? GL_BGRA_EXT : GL_RGBA;
    if (format.bytes != 4 && !_screen) {
        [device relinquish];
        return;
    }
    NSUInteger rowBytes = region.size.width * 4;
    for (NSUInteger row = 0; row < region.size.height; row++)
        glReadPixels((GLint)region.origin.x, (GLint)(region.origin.y + row), (GLsizei)region.size.width, 1, readFormat, GL_UNSIGNED_BYTE, (uint8_t *)pointer + row * bytesPerRow);
    (void)rowBytes;
    glBindFramebuffer(GL_FRAMEBUFFER, previous);
    [device relinquish];
}

@end

@implementation CharonMetalSampler {
    GLint _minFilter, _magFilter, _wrapS, _wrapT;
}

@synthesize label;

static BOOL wrapFor(MTLSamplerAddressMode mode, GLint *out)
{
    switch (mode) {
    case MTLSamplerAddressModeClampToEdge: *out = GL_CLAMP_TO_EDGE; return YES;
    case MTLSamplerAddressModeRepeat: *out = GL_REPEAT; return YES;
    case MTLSamplerAddressModeMirrorRepeat: *out = GL_MIRRORED_REPEAT; return YES;
    default: return NO;
    }
}

- (instancetype)initWithDescriptor:(MTLSamplerDescriptor *)descriptor
{
    if ((self = [super init])) {
        if (!wrapFor(descriptor.sAddressMode, &_wrapS) || !wrapFor(descriptor.tAddressMode, &_wrapT)) {
            NSLog(@"Metal: sampler address mode %d/%d has no OpenGL ES 2.0 form", (int)descriptor.sAddressMode, (int)descriptor.tAddressMode);
            return nil;
        }
        if (!descriptor.normalizedCoordinates) {
            NSLog(@"Metal: sampler with pixel coordinates has no OpenGL ES 2.0 form");
            return nil;
        }
        _minFilter = descriptor.minFilter == MTLSamplerMinMagFilterNearest ? GL_NEAREST : GL_LINEAR;
        _magFilter = descriptor.magFilter == MTLSamplerMinMagFilterNearest ? GL_NEAREST : GL_LINEAR;
    }
    return self;
}

- (GLint)minFilter
{
    return _minFilter;
}

- (GLint)magFilter
{
    return _magFilter;
}

- (GLint)wrapS
{
    return _wrapS;
}

- (GLint)wrapT
{
    return _wrapT;
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

@end
