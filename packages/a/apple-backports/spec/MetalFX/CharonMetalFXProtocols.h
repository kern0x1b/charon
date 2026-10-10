// CharonMetalFXProtocols.h - the MetalFX protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <MetalFX/MetalFX.h> for that body, and
#import <MetalFX/MetalFX.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
@protocol MTL4CommandBuffer;

API_AVAILABLE(ios(26.0))
@protocol MTL4FXFrameInterpolator <MTLFXFrameInterpolatorBase>
- (void)encodeToCommandBuffer:(id<MTL4CommandBuffer>  _Nonnull)commandBuffer;
@end

API_AVAILABLE(ios(26.0))
@protocol MTL4FXSpatialScaler <MTLFXSpatialScalerBase>
- (void)encodeToCommandBuffer:(id<MTL4CommandBuffer>  _Nonnull)commandBuffer;
@end

API_AVAILABLE(ios(26.0))
@protocol MTL4FXTemporalDenoisedScaler <MTLFXTemporalDenoisedScalerBase>
- (void)encodeToCommandBuffer:(id<MTL4CommandBuffer>  _Nonnull)commandBuffer;
@end

API_AVAILABLE(ios(26.0))
@protocol MTL4FXTemporalScaler <MTLFXTemporalScalerBase>
- (void)encodeToCommandBuffer:(id<MTL4CommandBuffer>  _Nonnull)commandBuffer;
@end

API_AVAILABLE(ios(26.0))
@protocol MTLFXFrameInterpolator <MTLFXFrameInterpolatorBase>
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>  _Nonnull)commandBuffer;
@end

API_AVAILABLE(ios(26.0))
@protocol MTLFXFrameInterpolatorBase <NSObject>
@property (nonatomic, readonly) MTLTextureUsage colorTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage outputTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage depthTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage motionTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage uiTextureUsage;
@property (nonatomic, readonly) MTLPixelFormat colorTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat depthTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat motionTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat outputTextureFormat;
@property (nonatomic, readonly) NSUInteger inputWidth;
@property (nonatomic, readonly) NSUInteger inputHeight;
@property (nonatomic, readonly) NSUInteger outputWidth;
@property (nonatomic, readonly) NSUInteger outputHeight;
@property (nonatomic, readonly) MTLPixelFormat uiTextureFormat;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable colorTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable prevColorTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable depthTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable motionTexture;
@property (nonatomic, readwrite, assign, unsafe_unretained) float motionVectorScaleX;
@property (nonatomic, readwrite, assign, unsafe_unretained) float motionVectorScaleY;
@property (nonatomic, readwrite, assign, unsafe_unretained) float deltaTime;
@property (nonatomic, readwrite, assign, unsafe_unretained) float nearPlane;
@property (nonatomic, readwrite, assign, unsafe_unretained) float farPlane;
@property (nonatomic, readwrite, assign, unsafe_unretained) float fieldOfView;
@property (nonatomic, readwrite, assign, unsafe_unretained) float aspectRatio;
@property (nonatomic, readwrite, retain, setter=setUITexture:) id<MTLTexture> _Nullable uiTexture;
@property (nonatomic, readwrite, assign, unsafe_unretained) float jitterOffsetX;
@property (nonatomic, readwrite, assign, unsafe_unretained) float jitterOffsetY;
@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isUITextureComposited, setter=setIsUITextureComposited:) BOOL uiTextureComposited;
@property (nonatomic, readwrite, assign, unsafe_unretained) BOOL shouldResetHistory;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable outputTexture;
@property (nonatomic, readwrite, retain) id<MTLFence> _Nullable fence;
@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isDepthReversed) BOOL depthReversed;
@end

@protocol MTLFXSpatialScaler;

API_AVAILABLE(ios(18.0))
@protocol MTLFXTemporalDenoisedScaler <MTLFXTemporalDenoisedScalerBase>
- (void)encodeToCommandBuffer:(id<MTLCommandBuffer>  _Nonnull)commandBuffer;
@end

@class simd_float4x4;
API_AVAILABLE(ios(26.0))
@protocol MTLFXTemporalDenoisedScalerBase <MTLFXFrameInterpolatableScaler>
@property (nonatomic, readonly) MTLTextureUsage colorTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage depthTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage motionTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage reactiveTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage diffuseAlbedoTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage specularAlbedoTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage normalTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage roughnessTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage specularHitDistanceTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage denoiseStrengthMaskTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage transparencyOverlayTextureUsage;
@property (nonatomic, readonly) MTLTextureUsage outputTextureUsage;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable colorTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable depthTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable motionTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable diffuseAlbedoTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable specularAlbedoTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable normalTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable roughnessTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable specularHitDistanceTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable denoiseStrengthMaskTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable transparencyOverlayTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable outputTexture;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable exposureTexture;
@property (nonatomic, readwrite, assign, unsafe_unretained) float preExposure;
@property (nonatomic, readwrite, retain) id<MTLTexture> _Nullable reactiveMaskTexture;
@property (nonatomic, readwrite, assign, unsafe_unretained) float jitterOffsetX;
@property (nonatomic, readwrite, assign, unsafe_unretained) float jitterOffsetY;
@property (nonatomic, readwrite, assign, unsafe_unretained) float motionVectorScaleX;
@property (nonatomic, readwrite, assign, unsafe_unretained) float motionVectorScaleY;
@property (nonatomic, readwrite, assign, unsafe_unretained) BOOL shouldResetHistory;
@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isDepthReversed) BOOL depthReversed;
@property (nonatomic, readonly) MTLPixelFormat colorTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat depthTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat motionTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat diffuseAlbedoTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat specularAlbedoTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat normalTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat roughnessTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat specularHitDistanceTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat denoiseStrengthMaskTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat transparencyOverlayTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat reactiveMaskTextureFormat;
@property (nonatomic, readonly) MTLPixelFormat outputTextureFormat;
@property (nonatomic, readonly) NSUInteger inputWidth;
@property (nonatomic, readonly) NSUInteger inputHeight;
@property (nonatomic, readonly) NSUInteger outputWidth;
@property (nonatomic, readonly) NSUInteger outputHeight;
@property (nonatomic, readonly) float inputContentMinScale;
@property (nonatomic, readonly) float inputContentMaxScale;
@property (nonatomic, readwrite, assign, unsafe_unretained) simd_float4x4 worldToViewMatrix;
@property (nonatomic, readwrite, assign, unsafe_unretained) simd_float4x4 viewToClipMatrix;
@property (nonatomic, readwrite, retain) id<MTLFence> _Nullable fence;
@end

@protocol MTLFXTemporalScaler;
