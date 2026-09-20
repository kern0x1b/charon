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
    if (descriptor.vertexDescriptor || [vertex.reflection[@"inputs"] count] > 0) {
        if (error)
            *error = CharonMetalError(6, @"a vertex descriptor is not supported yet; the vertex function has to read its buffers itself");
        return nil;
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
