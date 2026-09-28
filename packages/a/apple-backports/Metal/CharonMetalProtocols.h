// CharonMetalProtocols.h — the Metal protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(11.0))
@protocol MTLCaptureScope <NSObject>
- (void)beginScope;
- (void)endScope;
- (NSString * _Nullable)label;
- (void)setLabel:(NSString * _Nullable)label;
- (id<MTLDevice> _Nonnull)device;
- (id<MTLCommandQueue> _Nullable)commandQueue;
- (id<MTL4CommandQueue> _Nullable)mtl4CommandQueue;
@property ()NSString * _Nullable label;;
@property (readonly, )id<MTLDevice> _Nonnull device;;
@property (readonly, )id<MTLCommandQueue> _Nullable commandQueue;;
@property (readonly, )id<MTL4CommandQueue> _Nullable mtl4CommandQueue;;
@end

API_AVAILABLE(ios(8.0))
@protocol MTLBuffer <MTLResource>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLCommandBuffer <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLCommandEncoder <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLCommandQueue <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLDepthStencilState <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLDevice <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLDrawable <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLFunction <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLLibrary <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLRenderCommandEncoder <MTLCommandEncoder>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLRenderPipelineState <MTLAllocation, NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLResource <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLSamplerState <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol MTLTexture <MTLResource>
@end
