// Declarations for the ModelIO classes the SDK's own headers do not declare.
//
// The 16.4/26.2 SDK's ModelIO.framework declares 66 classes across 21 headers, and
// MDLLightProbeIrradianceDataSource is not among them - it is an SPI type the umbrella does not reach, and
// a category or an @implementation for it needs the interface to exist. The package supplies the
// declaration, which is what NetworkExtension does for the same reason, so the member is CARRIED rather
// than dropped from the registry. It is a declaration and nothing else: the answer still comes from the
// band object.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MDLLightProbeIrradianceDataSource : NSObject
@end

// MDLUtility is declared by NO header in the SDK the port builds with: the 16.4 ModelIO headers declare 65
// classes and MDLUtility is not among them, while the 26.2 headers declare 66 and DO have an MDLUtility.h.
// The map was built against 26.2 and so emitted an import for a header the gate cannot resolve -
// "fatal error: 'ModelIO/MDLUtility.h' file not found" - and the class then had no declaration at all,
// which is "cannot find interface declaration". The map is now built against the SDK the build uses.
@interface MDLUtility : NSObject
@end


// The per-class categories reach classes the header map does not place, because the map records only
// @interface declarations and these are declared elsewhere or reached through the umbrella indirectly.
@interface MDLColorSpec : NSObject
@end

@interface MDLMeshBuffer : NSObject
@end

@interface MDLMeshBufferAllocator : NSObject
@end

@interface MDLObjectContainerComponent : NSObject
@end

@interface MDLTransformComponent : NSObject
@end

@interface MDLAssetResolver : NSObject
@end

@interface MDLTransformOp : NSObject
@end

NS_ASSUME_NONNULL_END
