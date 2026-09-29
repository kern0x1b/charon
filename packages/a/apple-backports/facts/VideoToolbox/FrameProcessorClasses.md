# The VideoToolbox frame processor: 17 classes and the members they carry

Ranks of `coordination/corpus/band-frameworks.tsv`: VideoToolbox, LOAD-FAIL. iOS 6.1.3 carries
`VideoToolbox.framework` at `/System/Library/Frameworks` with the whole compression and
decompression session API on the armv7 cache ladder since 3.1.3. It carries none of the
seventeen frame-processor classes, which SDK 26.2 marks `API_AVAILABLE(ios(26.0))` and which
the 6.1.3 cache ladder does not export at any release.

## What the port does with a class the release does not have

Each class is a value object: an initialiser puts its arguments in a keyed store under the
property the SDK declares for each of them, and each accessor answers from that store. A
class property's value is kept on the class, because a class property's value belongs to the
type rather than to an instance. A `CVPixelBufferRef` is kept in an ivar and retained, because
the SDK declares `@property(nonatomic, readonly) CVPixelBufferRef buffer;` with no ownership
annotation. A `CMTime` or `CMVideoDimensions` is an `NSValue` box.

## What is NOT carried, and why

`processorSupported` is declared on three of the classes and the SDK marks it
`API_UNAVAILABLE(ios)`, so it is not iOS surface and carrying it would collide with the host's
own header on the armv7 build. It is absent, and the registry says so where a reader will look
for it rather than leaving the gap to be rediscovered.

## The nine VTFrameProcessor methods this series does not carry

`startSessionWithConfiguration:error:`, the four `processWith…` variants, `endSession`,
`+supportedScaleFactorsForFrameWidth:frameHeight:` and
`downloadConfigurationModelWithCompletionHandler:` need a device with a Neural Engine, which no
armv7 release has. They are recorded absent with the reason, and the one that cannot report
failure at all - `processWithCommandBuffer:parameters:` - is in `coordination/crutches.md`,
because it is undetectable by the header's own design.

## The members per class

### VTFrameProcessor

### VTFrameProcessorFrame

### VTFrameProcessorOpticalFlow

### VTFrameRateConversionConfiguration

### VTFrameRateConversionParameters

### VTLowLatencyFrameInterpolationConfiguration

### VTLowLatencyFrameInterpolationParameters

### VTLowLatencySuperResolutionScalerConfiguration

### VTLowLatencySuperResolutionScalerParameters

### VTMotionBlurConfiguration

### VTMotionBlurParameters

### VTOpticalFlowConfiguration

### VTOpticalFlowParameters

### VTSuperResolutionScalerConfiguration

### VTSuperResolutionScalerParameters

### VTTemporalNoiseFilterConfiguration

### VTTemporalNoiseFilterParameters

