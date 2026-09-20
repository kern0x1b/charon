#import "CharonMetal.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

static GLenum blendFactor(MTLBlendFactor f)
{
    switch (f) {
    case MTLBlendFactorZero: return GL_ZERO;
    case MTLBlendFactorOne: return GL_ONE;
    case MTLBlendFactorSourceColor: return GL_SRC_COLOR;
    case MTLBlendFactorOneMinusSourceColor: return GL_ONE_MINUS_SRC_COLOR;
    case MTLBlendFactorSourceAlpha: return GL_SRC_ALPHA;
    case MTLBlendFactorOneMinusSourceAlpha: return GL_ONE_MINUS_SRC_ALPHA;
    case MTLBlendFactorDestinationColor: return GL_DST_COLOR;
    case MTLBlendFactorOneMinusDestinationColor: return GL_ONE_MINUS_DST_COLOR;
    case MTLBlendFactorDestinationAlpha: return GL_DST_ALPHA;
    case MTLBlendFactorOneMinusDestinationAlpha: return GL_ONE_MINUS_DST_ALPHA;
    case MTLBlendFactorSourceAlphaSaturated: return GL_SRC_ALPHA_SATURATE;
    case MTLBlendFactorBlendColor: return GL_CONSTANT_COLOR;
    case MTLBlendFactorOneMinusBlendColor: return GL_ONE_MINUS_CONSTANT_COLOR;
    case MTLBlendFactorBlendAlpha: return GL_CONSTANT_ALPHA;
    case MTLBlendFactorOneMinusBlendAlpha: return GL_ONE_MINUS_CONSTANT_ALPHA;
    default: return GL_ONE;
    }
}

static GLenum blendOperation(MTLBlendOperation o)
{
    switch (o) {
    case MTLBlendOperationSubtract: return GL_FUNC_SUBTRACT;
    case MTLBlendOperationReverseSubtract: return GL_FUNC_REVERSE_SUBTRACT;
    case MTLBlendOperationMin: return GL_MIN_EXT;
    case MTLBlendOperationMax: return GL_MAX_EXT;
    default: return GL_FUNC_ADD;
    }
}

@implementation CharonMetalEncoder {
    CharonMetalDevice *_device;
    CharonMetalPipeline *_pipeline;
    __strong CharonMetalBuffer *_vertexBuffers[31];
    NSUInteger _vertexOffsets[31];
    __strong CharonMetalBuffer *_fragmentBuffers[31];
    NSUInteger _fragmentOffsets[31];
    __strong CharonMetalTexture *_fragmentTextures[16];
    __strong CharonMetalSampler *_fragmentSamplers[16];
    CharonMetalTexture *_target;
    MTLViewport _viewport;
    BOOL _viewportSet;
    MTLCullMode _cull;
    MTLWinding _winding;
    BOOL _ended;
    NSUInteger _instance;
}

@synthesize label;

- (instancetype)initWithDescriptor:(MTLRenderPassDescriptor *)descriptor
{
    MTLRenderPassColorAttachmentDescriptor *color = descriptor.colorAttachments[0];
    CharonMetalTexture *texture = (CharonMetalTexture *)color.texture;
    if (![texture isKindOfClass:[CharonMetalTexture class]])
        return nil;
    if ((self = [super init])) {
        _device = [CharonMetalDevice shared];
        [_device acquire];
        _target = texture;
        _winding = MTLWindingClockwise;
        glBindFramebuffer(GL_FRAMEBUFFER, [texture renderTarget]);
        glViewport(0, 0, (GLsizei)texture.width, (GLsizei)texture.height);
        glDisable(GL_SCISSOR_TEST);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        if (color.loadAction == MTLLoadActionClear) {
            MTLClearColor c = color.clearColor;
            glClearColor(c.red, c.green, c.blue, c.alpha);
            glClear(GL_COLOR_BUFFER_BIT);
        }
    }
    return self;
}

- (id<MTLDevice>)device
{
    return _device;
}

- (void)setRenderPipelineState:(id<MTLRenderPipelineState>)pipelineState
{
    _pipeline = (CharonMetalPipeline *)pipelineState;
}

- (void)setViewport:(MTLViewport)viewport
{
    _viewport = viewport;
    _viewportSet = YES;
}

- (void)setCullMode:(MTLCullMode)cullMode
{
    _cull = cullMode;
}

- (void)setFrontFacingWinding:(MTLWinding)frontFacingWinding
{
    _winding = frontFacingWinding;
}

- (void)setBlendColorRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha
{
    glBlendColor(red, green, blue, alpha);
}

- (void)setDepthStencilState:(id)depthStencilState
{
    if (depthStencilState)
        NSLog(@"Metal: a depth and stencil state has no form in this port yet");
}

- (void)setScissorRect:(MTLScissorRect)rect
{
    glEnable(GL_SCISSOR_TEST);
    glScissor((GLint)rect.x, _target.screen ? (GLint)(_target.height - rect.y - rect.height) : (GLint)rect.y, (GLsizei)rect.width, (GLsizei)rect.height);
}

- (void)setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index
{
    if (index < 31) {
        _vertexBuffers[index] = (CharonMetalBuffer *)buffer;
        _vertexOffsets[index] = offset;
    }
}

- (void)setVertexBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{
    [self setVertexBuffer:(id<MTLBuffer>)[[CharonMetalBuffer alloc] initWithLength:length bytes:bytes] offset:0 atIndex:index];
}

- (void)setFragmentBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index
{
    if (index < 31) {
        _fragmentBuffers[index] = (CharonMetalBuffer *)buffer;
        _fragmentOffsets[index] = offset;
    }
}

- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{
    [self setFragmentBuffer:(id<MTLBuffer>)[[CharonMetalBuffer alloc] initWithLength:length bytes:bytes] offset:0 atIndex:index];
}

- (void)setFragmentTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index
{
    if (index < 16)
        _fragmentTextures[index] = (CharonMetalTexture *)texture;
}

- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index
{
    if (index < 16)
        _fragmentSamplers[index] = (CharonMetalSampler *)sampler;
}

- (void)uploadUniforms:(NSArray *)uniforms buffers:(CharonMetalBuffer *__strong *)buffers offsets:(NSUInteger *)offsets
{
    for (NSDictionary *u in uniforms) {
        NSUInteger index = [u[@"buffer"] unsignedIntegerValue];
        CharonMetalBuffer *buffer = index < 31 ? buffers[index] : nil;
        GLint location = [_pipeline locationForName:u[@"name"]];
        if (!buffer || location < 0)
            continue;
        const uint8_t *p = (const uint8_t *)buffer.bytes + offsets[index] + [u[@"offset"] unsignedIntegerValue] + [u[@"instanceStride"] unsignedIntegerValue] * _instance;
        NSString *scalar = u[@"scalar"];
        int n = [u[@"components"] intValue];
        if ([scalar isEqualToString:@"float"]) {
            const GLfloat *f = (const GLfloat *)p;
            if (n == 1) glUniform1fv(location, 1, f);
            else if (n == 2) glUniform2fv(location, 1, f);
            else if (n == 3) glUniform3fv(location, 1, f);
            else glUniform4fv(location, 1, f);
        } else {
            GLint v[4] = {0, 0, 0, 0};
            for (int i = 0; i < n; i++) {
                if ([scalar isEqualToString:@"i32"]) v[i] = ((const int32_t *)p)[i];
                else if ([scalar isEqualToString:@"i16"]) v[i] = ((const int16_t *)p)[i];
                else v[i] = ((const int8_t *)p)[i];
            }
            if (n == 1) glUniform1iv(location, 1, v);
            else if (n == 2) glUniform2iv(location, 1, v);
            else if (n == 3) glUniform3iv(location, 1, v);
            else glUniform4iv(location, 1, v);
        }
    }
}

- (BOOL)prepareForVertexCount:(NSUInteger)count
{
    if (!_pipeline)
        return NO;
    MTLRenderPipelineColorAttachmentDescriptor *blend = _pipeline.descriptor.colorAttachments[0];
    glUseProgram(_pipeline.program);
    if (blend.blendingEnabled) {
        glEnable(GL_BLEND);
        glBlendFuncSeparate(blendFactor(blend.sourceRGBBlendFactor), blendFactor(blend.destinationRGBBlendFactor), blendFactor(blend.sourceAlphaBlendFactor), blendFactor(blend.destinationAlphaBlendFactor));
        glBlendEquationSeparate(blendOperation(blend.rgbBlendOperation), blendOperation(blend.alphaBlendOperation));
    } else {
        glDisable(GL_BLEND);
    }
    glColorMask((blend.writeMask & MTLColorWriteMaskRed) != 0, (blend.writeMask & MTLColorWriteMaskGreen) != 0, (blend.writeMask & MTLColorWriteMaskBlue) != 0, (blend.writeMask & MTLColorWriteMaskAlpha) != 0);
    if (_viewportSet) {
        GLint y = _target.screen ? (GLint)(_target.height - _viewport.originY - _viewport.height) : (GLint)_viewport.originY;
        glViewport((GLint)_viewport.originX, y, (GLsizei)_viewport.width, (GLsizei)_viewport.height);
    }
    BOOL flipped = !_target.screen;
    GLint flip = [_pipeline locationForName:@"charon_flip"];
    if (flip >= 0)
        glUniform1f(flip, flipped ? -1.0f : 1.0f);
    if (_cull == MTLCullModeNone) {
        glDisable(GL_CULL_FACE);
    } else {
        glEnable(GL_CULL_FACE);
        glFrontFace((_winding == MTLWindingClockwise) != flipped ? GL_CW : GL_CCW);
        glCullFace(_cull == MTLCullModeFront ? GL_FRONT : GL_BACK);
    }

    NSDictionary *vertex = _pipeline.vertexReflection;
    GLint instance = [_pipeline locationForName:@"charon_instance"];
    if (instance >= 0)
        glUniform1f(instance, (GLfloat)_instance);
    GLint idLocation = -1;
    if ([vertex[@"usesVertexId"] boolValue]) {
        idLocation = [_pipeline attributeForName:@"a_vertex_id"];
        if (idLocation >= 0) {
            GLfloat *ramp = malloc(count * sizeof(GLfloat));
            for (NSUInteger i = 0; i < count; i++)
                ramp[i] = (GLfloat)i;
            NSData *keep = [NSData dataWithBytesNoCopy:ramp length:count * sizeof(GLfloat) freeWhenDone:YES];
            objc_setAssociatedObject(self, "ramp", keep, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            glEnableVertexAttribArray(idLocation);
            glVertexAttribPointer(idLocation, 1, GL_FLOAT, GL_FALSE, 0, ramp);
        }
    }
    for (NSDictionary *a in vertex[@"attributes"]) {
        GLint location = [_pipeline attributeForName:a[@"name"]];
        NSUInteger index = [a[@"buffer"] unsignedIntegerValue];
        CharonMetalBuffer *buffer = index < 31 ? _vertexBuffers[index] : nil;
        if (location < 0)
            continue;
        if (!buffer) {
            glDisableVertexAttribArray(location);
            continue;
        }
        NSString *scalar = a[@"scalar"];
        GLenum type = [scalar isEqualToString:@"float"] ? GL_FLOAT : [scalar isEqualToString:@"i8"] ? GL_UNSIGNED_BYTE : GL_SHORT;
        glEnableVertexAttribArray(location);
        glVertexAttribPointer(location, [a[@"components"] intValue], type, GL_FALSE, (GLsizei)[a[@"stride"] unsignedIntegerValue], (const uint8_t *)buffer.bytes + _vertexOffsets[index] + [a[@"offset"] unsignedIntegerValue]);
    }
    [self uploadUniforms:vertex[@"uniforms"] buffers:_vertexBuffers offsets:_vertexOffsets];
    [self uploadUniforms:_pipeline.fragmentReflection[@"uniforms"] buffers:_fragmentBuffers offsets:_fragmentOffsets];
    for (NSDictionary *t in _pipeline.fragmentReflection[@"textures"]) {
        NSUInteger unit = [t[@"index"] unsignedIntegerValue];
        if (unit >= 8 || !_fragmentTextures[unit])
            continue;
        glActiveTexture(GL_TEXTURE0 + (GLenum)unit);
        glBindTexture(GL_TEXTURE_2D, _fragmentTextures[unit].name);
        CharonMetalSampler *sampler = _fragmentSamplers[unit];
        if (sampler) {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, sampler.minFilter);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, sampler.magFilter);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, sampler.wrapS);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, sampler.wrapT);
        }
        GLint location = [_pipeline locationForName:t[@"name"]];
        if (location >= 0)
            glUniform1i(location, (GLint)unit);
    }
    for (NSDictionary *size in _pipeline.fragmentReflection[@"sizes"]) {
        NSUInteger unit = [size[@"texture"] unsignedIntegerValue];
        GLint location = [_pipeline locationForName:size[@"name"]];
        if (location >= 0 && unit < 16 && _fragmentTextures[unit])
            glUniform2f(location, (GLfloat)_fragmentTextures[unit].width, (GLfloat)_fragmentTextures[unit].height);
    }
    return YES;
}

static GLenum primitive(MTLPrimitiveType type)
{
    switch (type) {
    case MTLPrimitiveTypePoint: return GL_POINTS;
    case MTLPrimitiveTypeLine: return GL_LINES;
    case MTLPrimitiveTypeLineStrip: return GL_LINE_STRIP;
    case MTLPrimitiveTypeTriangleStrip: return GL_TRIANGLE_STRIP;
    default: return GL_TRIANGLES;
    }
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount
{
    if (![self prepareForVertexCount:vertexStart + vertexCount])
        return;
    glDrawArrays(primitive(primitiveType), (GLint)vertexStart, (GLsizei)vertexCount);
}

- (void)drawPrimitives:(MTLPrimitiveType)primitiveType vertexStart:(NSUInteger)vertexStart vertexCount:(NSUInteger)vertexCount instanceCount:(NSUInteger)instanceCount
{
    for (_instance = 0; _instance < instanceCount; _instance++)
        [self drawPrimitives:primitiveType vertexStart:vertexStart vertexCount:vertexCount];
    _instance = 0;
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount
{
    for (_instance = 0; _instance < instanceCount; _instance++)
        [self drawIndexedPrimitives:primitiveType indexCount:indexCount indexType:indexType indexBuffer:indexBuffer indexBufferOffset:indexBufferOffset];
    _instance = 0;
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset
{
    CharonMetalBuffer *buffer = (CharonMetalBuffer *)indexBuffer;
    const uint8_t *indices = (const uint8_t *)buffer.bytes + indexBufferOffset;
    NSUInteger maximum = 0;
    for (NSUInteger i = 0; i < indexCount; i++) {
        NSUInteger v = indexType == MTLIndexTypeUInt16 ? ((const uint16_t *)indices)[i] : ((const uint32_t *)indices)[i];
        if (v > maximum)
            maximum = v;
    }
    if (![self prepareForVertexCount:maximum + 1])
        return;
    glDrawElements(primitive(primitiveType), (GLsizei)indexCount, indexType == MTLIndexTypeUInt16 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT, indices);
}

- (void)endEncoding
{
    if (_ended)
        return;
    _ended = YES;
    [_device relinquish];
}

- (void)dealloc
{
    [self endEncoding];
}

@end
