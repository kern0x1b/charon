#import "CharonMetal.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

static float halfToFloat(uint16_t h)
{
    uint32_t sign = (h >> 15) & 1, exponent = (h >> 10) & 31, mantissa = h & 1023;
    float value;
    if (exponent == 0)
        value = ldexpf((float)mantissa, -24);
    else if (exponent == 31)
        value = mantissa ? NAN : INFINITY;
    else
        value = ldexpf((float)(mantissa | 1024), (int)exponent - 25);
    return sign ? -value : value;
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
    const CharonPlan *_applied;
    BOOL _uniformsDirty, _attributesDirty, _texturesDirty, _viewportDirty;
    int _cullApplied;
    MTLWinding _windingApplied;
    uint32_t _enabled;
    GLuint _boundTexture[16];
    NSUInteger _epoch;
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
        _cullApplied = -1;
        _viewportDirty = _viewportSet;
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
    _uniformsDirty = _attributesDirty = _texturesDirty = YES;
}

- (void)setViewport:(MTLViewport)viewport
{
    _viewport = viewport;
    _viewportSet = YES;
    _viewportDirty = YES;
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
        _uniformsDirty = _attributesDirty = YES;
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
        _uniformsDirty = YES;
    }
}

- (void)setFragmentBytes:(const void *)bytes length:(NSUInteger)length atIndex:(NSUInteger)index
{
    [self setFragmentBuffer:(id<MTLBuffer>)[[CharonMetalBuffer alloc] initWithLength:length bytes:bytes] offset:0 atIndex:index];
}

- (void)setFragmentTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index
{
    if (index < 16)
    {
        _fragmentTextures[index] = (CharonMetalTexture *)texture;
        _texturesDirty = YES;
    }
}

- (void)setFragmentSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index
{
    if (index < 16)
    {
        _fragmentSamplers[index] = (CharonMetalSampler *)sampler;
        _texturesDirty = YES;
    }
}

static void uploadUniforms(const CharonUniformPlan *plans, unsigned count, CharonMetalBuffer *__strong *buffers, const NSUInteger *offsets, NSUInteger instance)
{
    for (unsigned k = 0; k < count; k++) {
        const CharonUniformPlan *u = &plans[k];
        CharonMetalBuffer *buffer = u->buffer < 31 ? buffers[u->buffer] : nil;
        if (!buffer)
            continue;
        const uint8_t *p = (const uint8_t *)buffer.bytes + offsets[u->buffer] + u->offset + u->instanceStride * instance;
        int n = u->components;
        if (u->scalar == CharonScalarFloat || u->scalar == CharonScalarHalf) {
            GLfloat converted[4];
            const GLfloat *f = (const GLfloat *)p;
            if (u->scalar == CharonScalarHalf) {
                for (int i = 0; i < n; i++)
                    converted[i] = halfToFloat(((const uint16_t *)p)[i]);
                f = converted;
            }
            switch (n) {
            case 1: glUniform1fv(u->location, 1, f); break;
            case 2: glUniform2fv(u->location, 1, f); break;
            case 3: glUniform3fv(u->location, 1, f); break;
            default: glUniform4fv(u->location, 1, f); break;
            }
        } else {
            GLint v[4] = {0, 0, 0, 0};
            for (int i = 0; i < n; i++)
                v[i] = u->scalar == CharonScalarI32 ? ((const int32_t *)p)[i] : u->scalar == CharonScalarI16 ? ((const int16_t *)p)[i] : ((const int8_t *)p)[i];
            switch (n) {
            case 1: glUniform1iv(u->location, 1, v); break;
            case 2: glUniform2iv(u->location, 1, v); break;
            case 3: glUniform3iv(u->location, 1, v); break;
            default: glUniform4iv(u->location, 1, v); break;
            }
        }
    }
}

static GLfloat *ramp;
static NSUInteger rampCount;

static const GLfloat *rampOf(NSUInteger count)
{
    if (count > rampCount) {
        NSUInteger size = rampCount ? rampCount : 1024;
        while (size < count)
            size *= 2;
        GLfloat *grown = realloc(ramp, size * sizeof(GLfloat));
        for (NSUInteger i = rampCount; i < size; i++)
            grown[i] = (GLfloat)i;
        ramp = grown;
        rampCount = size;
    }
    return ramp;
}

- (void)setAttribute:(GLint)location enabled:(BOOL)enabled
{
    uint32_t bit = 1u << (location & 31);
    if (enabled && !(_enabled & bit)) {
        glEnableVertexAttribArray(location);
        _enabled |= bit;
    } else if (!enabled && (_enabled & bit)) {
        glDisableVertexAttribArray(location);
        _enabled &= ~bit;
    }
}

- (BOOL)prepareForVertexCount:(NSUInteger)count
{
    if (!_pipeline)
        return NO;
    const CharonPlan *plan = _pipeline.plan;
    if (plan != _applied) {
        glUseProgram(plan->program);
        if (plan->blending) {
            glEnable(GL_BLEND);
            glBlendFuncSeparate(plan->sourceRGB, plan->destinationRGB, plan->sourceAlpha, plan->destinationAlpha);
            glBlendEquationSeparate(plan->equationRGB, plan->equationAlpha);
        } else {
            glDisable(GL_BLEND);
        }
        glColorMask(plan->mask[0], plan->mask[1], plan->mask[2], plan->mask[3]);
        if (plan->flip >= 0)
            glUniform1f(plan->flip, _target.screen ? 1.0f : -1.0f);
        if (plan->instance >= 0)
            glUniform1f(plan->instance, (GLfloat)_instance);
        _applied = plan;
        _uniformsDirty = _attributesDirty = _texturesDirty = YES;
        _cullApplied = -1;
    }
    if (_viewportDirty) {
        GLint y = _target.screen ? (GLint)(_target.height - _viewport.originY - _viewport.height) : (GLint)_viewport.originY;
        glViewport((GLint)_viewport.originX, y, (GLsizei)_viewport.width, (GLsizei)_viewport.height);
        _viewportDirty = NO;
    }
    if (_cullApplied != (int)_cull || (_cull != MTLCullModeNone && _windingApplied != _winding)) {
        BOOL flipped = !_target.screen;
        if (_cull == MTLCullModeNone) {
            glDisable(GL_CULL_FACE);
        } else {
            glEnable(GL_CULL_FACE);
            glFrontFace((_winding == MTLWindingClockwise) != flipped ? GL_CW : GL_CCW);
            glCullFace(_cull == MTLCullModeFront ? GL_FRONT : GL_BACK);
        }
        _cullApplied = (int)_cull;
        _windingApplied = _winding;
    }
    if (plan->vertexId >= 0) {
        [self setAttribute:plan->vertexId enabled:YES];
        glVertexAttribPointer(plan->vertexId, 1, GL_FLOAT, GL_FALSE, 0, rampOf(count));
    }
    if (_attributesDirty) {
        for (unsigned k = 0; k < plan->attributeCount; k++) {
            const CharonAttributePlan *a = &plan->attributes[k];
            CharonMetalBuffer *buffer = a->buffer < 31 ? _vertexBuffers[a->buffer] : nil;
            if (!buffer) {
                [self setAttribute:a->location enabled:NO];
                continue;
            }
            [self setAttribute:a->location enabled:YES];
            glVertexAttribPointer(a->location, a->components, a->type, GL_FALSE, (GLsizei)a->stride, (const uint8_t *)buffer.bytes + _vertexOffsets[a->buffer] + a->offset);
        }
        for (unsigned k = 0; k < plan->inputCount; k++) {
            const CharonInputPlan *in = &plan->inputs[k];
            CharonMetalBuffer *buffer = in->buffer < 31 ? _vertexBuffers[in->buffer] : nil;
            if (!buffer) {
                [self setAttribute:in->location enabled:NO];
                continue;
            }
            const uint8_t *base = (const uint8_t *)buffer.bytes + _vertexOffsets[in->buffer] + in->offset;
            if (in->step == MTLVertexStepFunctionPerVertex) {
                [self setAttribute:in->location enabled:YES];
                glVertexAttribPointer(in->location, in->decoded.size, in->decoded.type, in->decoded.normalized, (GLsizei)in->stride, base);
            } else {
                NSUInteger element = in->step == MTLVertexStepFunctionConstant ? 0 : _instance / in->stepRate;
                GLfloat v[4];
                CharonMetalDecodeVertex(in->format, base + element * in->stride, v);
                [self setAttribute:in->location enabled:NO];
                glVertexAttrib4f(in->location, v[0], v[1], v[2], v[3]);
            }
        }
        _attributesDirty = NO;
    }
    if (_uniformsDirty) {
        uploadUniforms(plan->vertexUniforms, plan->vertexUniformCount, _vertexBuffers, _vertexOffsets, _instance);
        uploadUniforms(plan->fragmentUniforms, plan->fragmentUniformCount, _fragmentBuffers, _fragmentOffsets, _instance);
        _uniformsDirty = NO;
    }
    if (_epoch != CharonMetalBindEpoch) {
        memset(_boundTexture, 0, sizeof _boundTexture);
        _epoch = CharonMetalBindEpoch;
        _texturesDirty = YES;
    }
    if (_texturesDirty) {
        for (unsigned k = 0; k < plan->textureCount; k++) {
            unsigned unit = plan->textures[k].unit;
            CharonMetalTexture *texture = unit < 8 ? _fragmentTextures[unit] : nil;
            if (!texture)
                continue;
            glActiveTexture(GL_TEXTURE0 + unit);
            if (_boundTexture[unit] != texture.name) {
                glBindTexture(GL_TEXTURE_2D, texture.name);
                _boundTexture[unit] = texture.name;
            }
            CharonMetalSampler *sampler = _fragmentSamplers[unit];
            if (sampler && texture.appliedSampler != sampler) {
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, sampler.minFilter);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, sampler.magFilter);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, sampler.wrapS);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, sampler.wrapT);
                texture.appliedSampler = sampler;
            }
            glUniform1i(plan->textures[k].location, (GLint)unit);
        }
        for (unsigned k = 0; k < plan->sizeCount; k++) {
            unsigned unit = plan->sizes[k].unit;
            if (unit < 16 && _fragmentTextures[unit])
                glUniform2f(plan->sizes[k].location, (GLfloat)_fragmentTextures[unit].width, (GLfloat)_fragmentTextures[unit].height);
        }
        _texturesDirty = NO;
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
    for (_instance = 0; _instance < instanceCount; _instance++) {
        if (_applied && _applied->instance >= 0)
            glUniform1f(_applied->instance, (GLfloat)_instance);
        _uniformsDirty = _attributesDirty = YES;
        [self drawPrimitives:primitiveType vertexStart:vertexStart vertexCount:vertexCount];
    }
    _instance = 0;
    _uniformsDirty = _attributesDirty = YES;
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset instanceCount:(NSUInteger)instanceCount
{
    for (_instance = 0; _instance < instanceCount; _instance++) {
        if (_applied && _applied->instance >= 0)
            glUniform1f(_applied->instance, (GLfloat)_instance);
        _uniformsDirty = _attributesDirty = YES;
        [self drawIndexedPrimitives:primitiveType indexCount:indexCount indexType:indexType indexBuffer:indexBuffer indexBufferOffset:indexBufferOffset];
    }
    _instance = 0;
    _uniformsDirty = _attributesDirty = YES;
}

- (void)drawIndexedPrimitives:(MTLPrimitiveType)primitiveType indexCount:(NSUInteger)indexCount indexType:(MTLIndexType)indexType indexBuffer:(id<MTLBuffer>)indexBuffer indexBufferOffset:(NSUInteger)indexBufferOffset
{
    CharonMetalBuffer *buffer = (CharonMetalBuffer *)indexBuffer;
    const uint8_t *indices = (const uint8_t *)buffer.bytes + indexBufferOffset;
    NSUInteger maximum = 0;
    for (NSUInteger i = 0; _pipeline.plan->vertexId >= 0 && i < indexCount; i++) {
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
