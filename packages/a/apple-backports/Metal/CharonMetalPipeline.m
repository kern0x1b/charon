#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

static GLuint compile(GLenum type, NSString *source, NSString **log)
{
    GLuint shader = glCreateShader(type);
    const char *text = source.UTF8String;
    glShaderSource(shader, 1, &text, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char buffer[1024] = {0};
        glGetShaderInfoLog(shader, sizeof buffer - 1, NULL, buffer);
        *log = [NSString stringWithUTF8String:buffer];
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

BOOL CharonMetalVertexFormat(MTLVertexFormat format, CharonVertexFormat *out)
{
    GLenum type;
    GLint size;
    GLboolean normalized = GL_FALSE;
    switch (format) {
    case MTLVertexFormatUChar: case MTLVertexFormatUChar2: case MTLVertexFormatUChar3: case MTLVertexFormatUChar4:
        type = GL_UNSIGNED_BYTE;
        break;
    case MTLVertexFormatUCharNormalized: case MTLVertexFormatUChar2Normalized: case MTLVertexFormatUChar3Normalized: case MTLVertexFormatUChar4Normalized:
        type = GL_UNSIGNED_BYTE;
        normalized = GL_TRUE;
        break;
    case MTLVertexFormatChar: case MTLVertexFormatChar2: case MTLVertexFormatChar3: case MTLVertexFormatChar4:
        type = GL_BYTE;
        break;
    case MTLVertexFormatCharNormalized: case MTLVertexFormatChar2Normalized: case MTLVertexFormatChar3Normalized: case MTLVertexFormatChar4Normalized:
        type = GL_BYTE;
        normalized = GL_TRUE;
        break;
    case MTLVertexFormatUShort: case MTLVertexFormatUShort2: case MTLVertexFormatUShort3: case MTLVertexFormatUShort4:
        type = GL_UNSIGNED_SHORT;
        break;
    case MTLVertexFormatUShortNormalized: case MTLVertexFormatUShort2Normalized: case MTLVertexFormatUShort3Normalized: case MTLVertexFormatUShort4Normalized:
        type = GL_UNSIGNED_SHORT;
        normalized = GL_TRUE;
        break;
    case MTLVertexFormatShort: case MTLVertexFormatShort2: case MTLVertexFormatShort3: case MTLVertexFormatShort4:
        type = GL_SHORT;
        break;
    case MTLVertexFormatShortNormalized: case MTLVertexFormatShort2Normalized: case MTLVertexFormatShort3Normalized: case MTLVertexFormatShort4Normalized:
        type = GL_SHORT;
        normalized = GL_TRUE;
        break;
    case MTLVertexFormatFloat: case MTLVertexFormatFloat2: case MTLVertexFormatFloat3: case MTLVertexFormatFloat4:
        type = GL_FLOAT;
        break;
    default:
        return NO;
    }
    switch (format) {
    case MTLVertexFormatUChar: case MTLVertexFormatUCharNormalized: case MTLVertexFormatChar: case MTLVertexFormatCharNormalized:
    case MTLVertexFormatUShort: case MTLVertexFormatUShortNormalized: case MTLVertexFormatShort: case MTLVertexFormatShortNormalized:
    case MTLVertexFormatFloat:
        size = 1;
        break;
    case MTLVertexFormatUChar2: case MTLVertexFormatUChar2Normalized: case MTLVertexFormatChar2: case MTLVertexFormatChar2Normalized:
    case MTLVertexFormatUShort2: case MTLVertexFormatUShort2Normalized: case MTLVertexFormatShort2: case MTLVertexFormatShort2Normalized:
    case MTLVertexFormatFloat2:
        size = 2;
        break;
    case MTLVertexFormatUChar3: case MTLVertexFormatUChar3Normalized: case MTLVertexFormatChar3: case MTLVertexFormatChar3Normalized:
    case MTLVertexFormatUShort3: case MTLVertexFormatUShort3Normalized: case MTLVertexFormatShort3: case MTLVertexFormatShort3Normalized:
    case MTLVertexFormatFloat3:
        size = 3;
        break;
    default:
        size = 4;
        break;
    }
    NSUInteger width = type == GL_FLOAT ? 4 : (type == GL_UNSIGNED_SHORT || type == GL_SHORT) ? 2 : 1;
    out->type = type;
    out->size = size;
    out->normalized = normalized;
    out->bytes = width * size;
    out->floating = type == GL_FLOAT;
    return YES;
}

void CharonMetalDecodeVertex(MTLVertexFormat format, const uint8_t *bytes, GLfloat out[4])
{
    CharonVertexFormat f;
    out[0] = out[1] = out[2] = 0;
    out[3] = 1;
    if (!CharonMetalVertexFormat(format, &f))
        return;
    for (GLint i = 0; i < f.size; i++) {
        double v;
        switch (f.type) {
        case GL_FLOAT: v = ((const float *)bytes)[i]; break;
        case GL_UNSIGNED_BYTE: v = bytes[i] / (f.normalized ? 255.0 : 1.0); break;
        case GL_BYTE: v = ((const int8_t *)bytes)[i]; v = f.normalized ? fmax(v / 127.0, -1.0) : v; break;
        case GL_UNSIGNED_SHORT: v = ((const uint16_t *)bytes)[i] / (f.normalized ? 65535.0 : 1.0); break;
        default: v = ((const int16_t *)bytes)[i]; v = f.normalized ? fmax(v / 32767.0, -1.0) : v; break;
        }
        out[i] = (GLfloat)v;
    }
}

@implementation CharonMetalPipeline {
    GLuint _program;
    NSDictionary *_vertexReflection, *_fragmentReflection;
    MTLRenderPipelineDescriptor *_descriptor;
    NSMutableDictionary *_locations;
}

@synthesize label;

- (instancetype)initWithDescriptor:(MTLRenderPipelineDescriptor *)descriptor error:(NSError **)error
{
    CharonMetalFunction *vertex = (CharonMetalFunction *)descriptor.vertexFunction;
    CharonMetalFunction *fragment = (CharonMetalFunction *)descriptor.fragmentFunction;
    if (![vertex isKindOfClass:[CharonMetalFunction class]] || ![fragment isKindOfClass:[CharonMetalFunction class]]) {
        if (error)
            *error = CharonMetalError(5, @"a render pipeline needs a vertex function and a fragment function of a translated library");
        return nil;
    }
    for (NSDictionary *input in vertex.reflection[@"inputs"]) {
        MTLVertexAttributeDescriptor *attribute = descriptor.vertexDescriptor ? descriptor.vertexDescriptor.attributes[[input[@"location"] unsignedIntegerValue]] : nil;
        CharonVertexFormat format;
        if ((!attribute || attribute.format == MTLVertexFormatInvalid) && [input[@"optional"] boolValue])
            continue;
        if (!attribute || attribute.format == MTLVertexFormatInvalid) {
            if (error)
                *error = CharonMetalError(6, [NSString stringWithFormat:@"the vertex function reads an input at attribute %@, and the vertex descriptor has none there", input[@"location"]]);
            return nil;
        }
        if (!CharonMetalVertexFormat(attribute.format, &format)) {
            if (error)
                *error = CharonMetalError(10, [NSString stringWithFormat:@"the vertex format %d of attribute %@ has no OpenGL ES 2.0 form", (int)attribute.format, input[@"location"]]);
            return nil;
        }
        MTLVertexBufferLayoutDescriptor *layout = descriptor.vertexDescriptor.layouts[attribute.bufferIndex];
        BOOL known = layout.stepFunction == MTLVertexStepFunctionPerVertex || layout.stepFunction == MTLVertexStepFunctionConstant || layout.stepFunction == MTLVertexStepFunctionPerInstance;
        if (!known || (layout.stepFunction == MTLVertexStepFunctionPerInstance && layout.stepRate == 0) || (layout.stepFunction == MTLVertexStepFunctionPerVertex && layout.stepRate != 1)) {
            if (error)
                *error = CharonMetalError(11, @"the step function of the layout has no OpenGL ES 2.0 form");
            return nil;
        }
    }
    if ((self = [super init])) {
        _descriptor = [descriptor copy];
        _vertexReflection = vertex.reflection;
        _fragmentReflection = fragment.reflection;
        _locations = [NSMutableDictionary dictionary];
        CharonMetalDevice *device = [CharonMetalDevice shared];
        [device acquire];
        NSString *log = nil;
        GLuint v = compile(GL_VERTEX_SHADER, vertex.source, &log);
        GLuint f = v ? compile(GL_FRAGMENT_SHADER, fragment.source, &log) : 0;
        if (!v || !f) {
            if (error)
                *error = CharonMetalError(7, [NSString stringWithFormat:@"shader did not compile: %@", log]);
            [device relinquish];
            return nil;
        }
        _program = glCreateProgram();
        glAttachShader(_program, v);
        glAttachShader(_program, f);
        GLuint index = 0;
        if ([_vertexReflection[@"usesVertexId"] boolValue])
            glBindAttribLocation(_program, index++, "a_vertex_id");
        for (NSDictionary *a in _vertexReflection[@"attributes"])
            glBindAttribLocation(_program, index++, [a[@"name"] UTF8String]);
        for (NSDictionary *a in _vertexReflection[@"inputs"])
            glBindAttribLocation(_program, index++, [a[@"name"] UTF8String]);
        glLinkProgram(_program);
        GLint ok = 0;
        glGetProgramiv(_program, GL_LINK_STATUS, &ok);
        glDeleteShader(v);
        glDeleteShader(f);
        if (!ok) {
            char buffer[1024] = {0};
            glGetProgramInfoLog(_program, sizeof buffer - 1, NULL, buffer);
            if (error)
                *error = CharonMetalError(8, [NSString stringWithFormat:@"program did not link: %s", buffer]);
            glDeleteProgram(_program);
            _program = 0;
            [device relinquish];
            return nil;
        }
        [device relinquish];
    }
    return self;
}

- (void)dealloc
{
    if (_program) {
        CharonMetalDevice *device = [CharonMetalDevice shared];
        [device acquire];
        glDeleteProgram(_program);
        [device relinquish];
    }
}

- (GLuint)program
{
    return _program;
}

- (NSDictionary *)vertexReflection
{
    return _vertexReflection;
}

- (NSDictionary *)fragmentReflection
{
    return _fragmentReflection;
}

- (MTLRenderPipelineDescriptor *)descriptor
{
    return _descriptor;
}

- (GLint)locationForName:(NSString *)name
{
    NSNumber *n = _locations[name];
    if (!n) {
        n = @(glGetUniformLocation(_program, name.UTF8String));
        _locations[name] = n;
    }
    return n.intValue;
}

- (GLint)attributeForName:(NSString *)name
{
    return glGetAttribLocation(_program, name.UTF8String);
}

- (id<MTLDevice>)device
{
    return [CharonMetalDevice shared];
}

@end
