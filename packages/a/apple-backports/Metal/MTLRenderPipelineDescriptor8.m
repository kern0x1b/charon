#import "CharonMetal.h"

#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

@implementation MTLRenderPipelineColorAttachmentDescriptor

- (instancetype)init
{
    if ((self = [super init])) {
        self.writeMask = MTLColorWriteMaskAll;
        self.sourceRGBBlendFactor = MTLBlendFactorOne;
        self.sourceAlphaBlendFactor = MTLBlendFactorOne;
        self.destinationRGBBlendFactor = MTLBlendFactorZero;
        self.destinationAlphaBlendFactor = MTLBlendFactorZero;
        self.rgbBlendOperation = MTLBlendOperationAdd;
        self.alphaBlendOperation = MTLBlendOperationAdd;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    MTLRenderPipelineColorAttachmentDescriptor *d = [[MTLRenderPipelineColorAttachmentDescriptor alloc] init];
    d.pixelFormat = self.pixelFormat;
    d.blendingEnabled = self.blendingEnabled;
    d.sourceRGBBlendFactor = self.sourceRGBBlendFactor;
    d.destinationRGBBlendFactor = self.destinationRGBBlendFactor;
    d.rgbBlendOperation = self.rgbBlendOperation;
    d.sourceAlphaBlendFactor = self.sourceAlphaBlendFactor;
    d.destinationAlphaBlendFactor = self.destinationAlphaBlendFactor;
    d.alphaBlendOperation = self.alphaBlendOperation;
    d.writeMask = self.writeMask;
    return d;
}

@end

@implementation MTLRenderPipelineColorAttachmentDescriptorArray {
    NSMutableArray *_items;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        for (int i = 0; i < 8; i++)
            [_items addObject:[[MTLRenderPipelineColorAttachmentDescriptor alloc] init]];
    }
    return self;
}

- (MTLRenderPipelineColorAttachmentDescriptor *)objectAtIndexedSubscript:(NSUInteger)attachmentIndex
{
    return _items[attachmentIndex];
}

- (void)setObject:(MTLRenderPipelineColorAttachmentDescriptor *)attachment atIndexedSubscript:(NSUInteger)attachmentIndex
{
    _items[attachmentIndex] = [attachment copy];
}

@end

@implementation MTLRenderPipelineDescriptor {
    MTLRenderPipelineColorAttachmentDescriptorArray *_colorAttachments;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _colorAttachments = [[MTLRenderPipelineColorAttachmentDescriptorArray alloc] init];
        self.rasterSampleCount = 1;
        self.rasterizationEnabled = YES;
    }
    return self;
}

- (MTLRenderPipelineColorAttachmentDescriptorArray *)colorAttachments
{
    return _colorAttachments;
}

- (id)copyWithZone:(NSZone *)zone
{
    MTLRenderPipelineDescriptor *d = [[MTLRenderPipelineDescriptor alloc] init];
    d.vertexFunction = self.vertexFunction;
    d.fragmentFunction = self.fragmentFunction;
    d.label = self.label;
    for (int i = 0; i < 8; i++)
        d.colorAttachments[i] = self.colorAttachments[i];
    d.depthAttachmentPixelFormat = self.depthAttachmentPixelFormat;
    d.vertexDescriptor = self.vertexDescriptor;
    return d;
}

@end
