#import <CoreImage/CoreImage.h>

// The CIFilter convenience constructors of iOS 16.0: 220 of the 239 the SDK's own
// CIFilterBuiltins.h declares, which are class methods that take nothing and answer a filter.
//
// iOS 16.0 is the first held rung that exports the other 220, and the release that started answering the family.
//
// WHAT THEY ARE, MEASURED: on the host, +[CIFilter CMYKHalftone] answers exactly the object
// +[CIFilter filterWithName:@"CICMYKHalftone"] answers - the same class, the same name, the same
// inputKeys, outputKeys and attributes, and the same rendered bytes over a fixed window where the
// filter's declared inputs are only an image.  tests/backports/host/ciimagefilter/ builds these very
// objects with their selectors prefixed and asks both in one process; it checked 478 class
// methods, rendered and compared 44 of them, and reported 0 differences.
//
// So each method here is that one call, and the filter's own arithmetic is the release's:
// +filterWithName: is exported from iOS 3.0 and answers nil for a name the release has no filter of,
// which is what Apple documents for a filter that does not exist on the running system
// (facts/CoreImage/ImageApplyingFilter.md).
//
// The port carries CIFilter's constructors and not CIFilter: the class is the release's own from
// iOS 5.0 (tools/cache-index/first-rung.py _OBJC_CLASS_$_CIFilter -> 5.0), so these are a category
// on it, and charon_collect installs a category method only where the class does not answer the
// selector, which is exactly the band this object is for.

@implementation CIFilter (CharonFilterBuiltins16)

+ (CIFilter *)CMYKHalftone
{
    return [CIFilter filterWithName:@"CICMYKHalftone"];
}

+ (CIFilter *)KMeansFilter
{
    return [CIFilter filterWithName:@"CIKMeans"];
}

+ (CIFilter *)LabDeltaE
{
    return [CIFilter filterWithName:@"CILabDeltaE"];
}

+ (CIFilter *)PDF417BarcodeGenerator
{
    return [CIFilter filterWithName:@"CIPDF417BarcodeGenerator"];
}

+ (CIFilter *)QRCodeGenerator
{
    return [CIFilter filterWithName:@"CIQRCodeGenerator"];
}

+ (CIFilter *)accordionFoldTransitionFilter
{
    return [CIFilter filterWithName:@"CIAccordionFoldTransition"];
}

+ (CIFilter *)additionCompositingFilter
{
    return [CIFilter filterWithName:@"CIAdditionCompositing"];
}

+ (CIFilter *)affineClampFilter
{
    return [CIFilter filterWithName:@"CIAffineClamp"];
}

+ (CIFilter *)affineTileFilter
{
    return [CIFilter filterWithName:@"CIAffineTile"];
}

+ (CIFilter *)areaAverageFilter
{
    return [CIFilter filterWithName:@"CIAreaAverage"];
}

+ (CIFilter *)areaHistogramFilter
{
    return [CIFilter filterWithName:@"CIAreaHistogram"];
}

+ (CIFilter *)areaLogarithmicHistogramFilter
{
    return [CIFilter filterWithName:@"CIAreaLogarithmicHistogram"];
}

+ (CIFilter *)areaMaximumAlphaFilter
{
    return [CIFilter filterWithName:@"CIAreaMaximumAlpha"];
}

+ (CIFilter *)areaMaximumFilter
{
    return [CIFilter filterWithName:@"CIAreaMaximum"];
}

+ (CIFilter *)areaMinMaxFilter
{
    return [CIFilter filterWithName:@"CIAreaMinMax"];
}

+ (CIFilter *)areaMinMaxRedFilter
{
    return [CIFilter filterWithName:@"CIAreaMinMaxRed"];
}

+ (CIFilter *)areaMinimumAlphaFilter
{
    return [CIFilter filterWithName:@"CIAreaMinimumAlpha"];
}

+ (CIFilter *)areaMinimumFilter
{
    return [CIFilter filterWithName:@"CIAreaMinimum"];
}

+ (CIFilter *)attributedTextImageGeneratorFilter
{
    return [CIFilter filterWithName:@"CIAttributedTextImageGenerator"];
}

+ (CIFilter *)aztecCodeGeneratorFilter
{
    return [CIFilter filterWithName:@"CIAztecCodeGenerator"];
}

+ (CIFilter *)barcodeGeneratorFilter
{
    return [CIFilter filterWithName:@"CIBarcodeGenerator"];
}

+ (CIFilter *)barsSwipeTransitionFilter
{
    return [CIFilter filterWithName:@"CIBarsSwipeTransition"];
}

+ (CIFilter *)bicubicScaleTransformFilter
{
    return [CIFilter filterWithName:@"CIBicubicScaleTransform"];
}

+ (CIFilter *)blendWithAlphaMaskFilter
{
    return [CIFilter filterWithName:@"CIBlendWithAlphaMask"];
}

+ (CIFilter *)blendWithBlueMaskFilter
{
    return [CIFilter filterWithName:@"CIBlendWithBlueMask"];
}

+ (CIFilter *)blendWithMaskFilter
{
    return [CIFilter filterWithName:@"CIBlendWithMask"];
}

+ (CIFilter *)blendWithRedMaskFilter
{
    return [CIFilter filterWithName:@"CIBlendWithRedMask"];
}

+ (CIFilter *)bloomFilter
{
    return [CIFilter filterWithName:@"CIBloom"];
}

+ (CIFilter *)bokehBlurFilter
{
    return [CIFilter filterWithName:@"CIBokehBlur"];
}

+ (CIFilter *)boxBlurFilter
{
    return [CIFilter filterWithName:@"CIBoxBlur"];
}

+ (CIFilter *)bumpDistortionFilter
{
    return [CIFilter filterWithName:@"CIBumpDistortion"];
}

+ (CIFilter *)bumpDistortionLinearFilter
{
    return [CIFilter filterWithName:@"CIBumpDistortionLinear"];
}

+ (CIFilter *)checkerboardGeneratorFilter
{
    return [CIFilter filterWithName:@"CICheckerboardGenerator"];
}

+ (CIFilter *)circleSplashDistortionFilter
{
    return [CIFilter filterWithName:@"CICircleSplashDistortion"];
}

+ (CIFilter *)circularScreenFilter
{
    return [CIFilter filterWithName:@"CICircularScreen"];
}

+ (CIFilter *)circularWrapFilter
{
    return [CIFilter filterWithName:@"CICircularWrap"];
}

+ (CIFilter *)code128BarcodeGeneratorFilter
{
    return [CIFilter filterWithName:@"CICode128BarcodeGenerator"];
}

+ (CIFilter *)colorAbsoluteDifferenceFilter
{
    return [CIFilter filterWithName:@"CIColorAbsoluteDifference"];
}

+ (CIFilter *)colorBlendModeFilter
{
    return [CIFilter filterWithName:@"CIColorBlendMode"];
}

+ (CIFilter *)colorBurnBlendModeFilter
{
    return [CIFilter filterWithName:@"CIColorBurnBlendMode"];
}

+ (CIFilter *)colorClampFilter
{
    return [CIFilter filterWithName:@"CIColorClamp"];
}

+ (CIFilter *)colorControlsFilter
{
    return [CIFilter filterWithName:@"CIColorControls"];
}

+ (CIFilter *)colorCrossPolynomialFilter
{
    return [CIFilter filterWithName:@"CIColorCrossPolynomial"];
}

+ (CIFilter *)colorCubeWithColorSpaceFilter
{
    return [CIFilter filterWithName:@"CIColorCubeWithColorSpace"];
}

+ (CIFilter *)colorCubesMixedWithMaskFilter
{
    return [CIFilter filterWithName:@"CIColorCubesMixedWithMask"];
}

+ (CIFilter *)colorCurvesFilter
{
    return [CIFilter filterWithName:@"CIColorCurves"];
}

+ (CIFilter *)colorDodgeBlendModeFilter
{
    return [CIFilter filterWithName:@"CIColorDodgeBlendMode"];
}

+ (CIFilter *)colorInvertFilter
{
    return [CIFilter filterWithName:@"CIColorInvert"];
}

+ (CIFilter *)colorMapFilter
{
    return [CIFilter filterWithName:@"CIColorMap"];
}

+ (CIFilter *)colorMonochromeFilter
{
    return [CIFilter filterWithName:@"CIColorMonochrome"];
}

+ (CIFilter *)colorPolynomialFilter
{
    return [CIFilter filterWithName:@"CIColorPolynomial"];
}

+ (CIFilter *)colorPosterizeFilter
{
    return [CIFilter filterWithName:@"CIColorPosterize"];
}

+ (CIFilter *)colorThresholdFilter
{
    return [CIFilter filterWithName:@"CIColorThreshold"];
}

+ (CIFilter *)colorThresholdOtsuFilter
{
    return [CIFilter filterWithName:@"CIColorThresholdOtsu"];
}

+ (CIFilter *)columnAverageFilter
{
    return [CIFilter filterWithName:@"CIColumnAverage"];
}

+ (CIFilter *)comicEffectFilter
{
    return [CIFilter filterWithName:@"CIComicEffect"];
}

+ (CIFilter *)convertLabToRGBFilter
{
    return [CIFilter filterWithName:@"CIConvertLabToRGB"];
}

+ (CIFilter *)convertRGBtoLabFilter
{
    return [CIFilter filterWithName:@"CIConvertRGBtoLab"];
}

+ (CIFilter *)convolution3X3Filter
{
    return [CIFilter filterWithName:@"CIConvolution3X3"];
}

+ (CIFilter *)convolution5X5Filter
{
    return [CIFilter filterWithName:@"CIConvolution5X5"];
}

+ (CIFilter *)convolution7X7Filter
{
    return [CIFilter filterWithName:@"CIConvolution7X7"];
}

+ (CIFilter *)convolution9HorizontalFilter
{
    return [CIFilter filterWithName:@"CIConvolution9Horizontal"];
}

+ (CIFilter *)convolution9VerticalFilter
{
    return [CIFilter filterWithName:@"CIConvolution9Vertical"];
}

+ (CIFilter *)convolutionRGB3X3Filter
{
    return [CIFilter filterWithName:@"CIConvolutionRGB3X3"];
}

+ (CIFilter *)convolutionRGB5X5Filter
{
    return [CIFilter filterWithName:@"CIConvolutionRGB5X5"];
}

+ (CIFilter *)convolutionRGB7X7Filter
{
    return [CIFilter filterWithName:@"CIConvolutionRGB7X7"];
}

+ (CIFilter *)convolutionRGB9HorizontalFilter
{
    return [CIFilter filterWithName:@"CIConvolutionRGB9Horizontal"];
}

+ (CIFilter *)convolutionRGB9VerticalFilter
{
    return [CIFilter filterWithName:@"CIConvolutionRGB9Vertical"];
}

+ (CIFilter *)copyMachineTransitionFilter
{
    return [CIFilter filterWithName:@"CICopyMachineTransition"];
}

+ (CIFilter *)coreMLModelFilter
{
    return [CIFilter filterWithName:@"CICoreMLModelFilter"];
}

+ (CIFilter *)crystallizeFilter
{
    return [CIFilter filterWithName:@"CICrystallize"];
}

+ (CIFilter *)darkenBlendModeFilter
{
    return [CIFilter filterWithName:@"CIDarkenBlendMode"];
}

+ (CIFilter *)depthOfFieldFilter
{
    return [CIFilter filterWithName:@"CIDepthOfField"];
}

+ (CIFilter *)depthToDisparityFilter
{
    return [CIFilter filterWithName:@"CIDepthToDisparity"];
}

+ (CIFilter *)differenceBlendModeFilter
{
    return [CIFilter filterWithName:@"CIDifferenceBlendMode"];
}

+ (CIFilter *)discBlurFilter
{
    return [CIFilter filterWithName:@"CIDiscBlur"];
}

+ (CIFilter *)disintegrateWithMaskTransitionFilter
{
    return [CIFilter filterWithName:@"CIDisintegrateWithMaskTransition"];
}

+ (CIFilter *)disparityToDepthFilter
{
    return [CIFilter filterWithName:@"CIDisparityToDepth"];
}

+ (CIFilter *)displacementDistortionFilter
{
    return [CIFilter filterWithName:@"CIDisplacementDistortion"];
}

+ (CIFilter *)dissolveTransitionFilter
{
    return [CIFilter filterWithName:@"CIDissolveTransition"];
}

+ (CIFilter *)ditherFilter
{
    return [CIFilter filterWithName:@"CIDither"];
}

+ (CIFilter *)divideBlendModeFilter
{
    return [CIFilter filterWithName:@"CIDivideBlendMode"];
}

+ (CIFilter *)documentEnhancerFilter
{
    return [CIFilter filterWithName:@"CIDocumentEnhancer"];
}

+ (CIFilter *)dotScreenFilter
{
    return [CIFilter filterWithName:@"CIDotScreen"];
}

+ (CIFilter *)drosteFilter
{
    return [CIFilter filterWithName:@"CIDroste"];
}

+ (CIFilter *)edgePreserveUpsampleFilter
{
    return [CIFilter filterWithName:@"CIEdgePreserveUpsampleFilter"];
}

+ (CIFilter *)edgeWorkFilter
{
    return [CIFilter filterWithName:@"CIEdgeWork"];
}

+ (CIFilter *)eightfoldReflectedTileFilter
{
    return [CIFilter filterWithName:@"CIEightfoldReflectedTile"];
}

+ (CIFilter *)exclusionBlendModeFilter
{
    return [CIFilter filterWithName:@"CIExclusionBlendMode"];
}

+ (CIFilter *)exposureAdjustFilter
{
    return [CIFilter filterWithName:@"CIExposureAdjust"];
}

+ (CIFilter *)falseColorFilter
{
    return [CIFilter filterWithName:@"CIFalseColor"];
}

+ (CIFilter *)flashTransitionFilter
{
    return [CIFilter filterWithName:@"CIFlashTransition"];
}

+ (CIFilter *)fourfoldReflectedTileFilter
{
    return [CIFilter filterWithName:@"CIFourfoldReflectedTile"];
}

+ (CIFilter *)fourfoldRotatedTileFilter
{
    return [CIFilter filterWithName:@"CIFourfoldRotatedTile"];
}

+ (CIFilter *)fourfoldTranslatedTileFilter
{
    return [CIFilter filterWithName:@"CIFourfoldTranslatedTile"];
}

+ (CIFilter *)gaborGradientsFilter
{
    return [CIFilter filterWithName:@"CIGaborGradients"];
}

+ (CIFilter *)gammaAdjustFilter
{
    return [CIFilter filterWithName:@"CIGammaAdjust"];
}

+ (CIFilter *)gaussianGradientFilter
{
    return [CIFilter filterWithName:@"CIGaussianGradient"];
}

+ (CIFilter *)glassDistortionFilter
{
    return [CIFilter filterWithName:@"CIGlassDistortion"];
}

+ (CIFilter *)glassLozengeFilter
{
    return [CIFilter filterWithName:@"CIGlassLozenge"];
}

+ (CIFilter *)glideReflectedTileFilter
{
    return [CIFilter filterWithName:@"CIGlideReflectedTile"];
}

+ (CIFilter *)gloomFilter
{
    return [CIFilter filterWithName:@"CIGloom"];
}

+ (CIFilter *)hardLightBlendModeFilter
{
    return [CIFilter filterWithName:@"CIHardLightBlendMode"];
}

+ (CIFilter *)hatchedScreenFilter
{
    return [CIFilter filterWithName:@"CIHatchedScreen"];
}

+ (CIFilter *)heightFieldFromMaskFilter
{
    return [CIFilter filterWithName:@"CIHeightFieldFromMask"];
}

+ (CIFilter *)hexagonalPixellateFilter
{
    return [CIFilter filterWithName:@"CIHexagonalPixellate"];
}

+ (CIFilter *)highlightShadowAdjustFilter
{
    return [CIFilter filterWithName:@"CIHighlightShadowAdjust"];
}

+ (CIFilter *)histogramDisplayFilter
{
    return [CIFilter filterWithName:@"CIHistogramDisplayFilter"];
}

+ (CIFilter *)holeDistortionFilter
{
    return [CIFilter filterWithName:@"CIHoleDistortion"];
}

+ (CIFilter *)hueAdjustFilter
{
    return [CIFilter filterWithName:@"CIHueAdjust"];
}

+ (CIFilter *)hueBlendModeFilter
{
    return [CIFilter filterWithName:@"CIHueBlendMode"];
}

+ (CIFilter *)hueSaturationValueGradientFilter
{
    return [CIFilter filterWithName:@"CIHueSaturationValueGradient"];
}

+ (CIFilter *)kaleidoscopeFilter
{
    return [CIFilter filterWithName:@"CIKaleidoscope"];
}

+ (CIFilter *)keystoneCorrectionCombinedFilter
{
    return [CIFilter filterWithName:@"CIKeystoneCorrectionCombined"];
}

+ (CIFilter *)keystoneCorrectionHorizontalFilter
{
    return [CIFilter filterWithName:@"CIKeystoneCorrectionHorizontal"];
}

+ (CIFilter *)keystoneCorrectionVerticalFilter
{
    return [CIFilter filterWithName:@"CIKeystoneCorrectionVertical"];
}

+ (CIFilter *)lanczosScaleTransformFilter
{
    return [CIFilter filterWithName:@"CILanczosScaleTransform"];
}

+ (CIFilter *)lenticularHaloGeneratorFilter
{
    return [CIFilter filterWithName:@"CILenticularHaloGenerator"];
}

+ (CIFilter *)lightTunnelFilter
{
    return [CIFilter filterWithName:@"CILightTunnel"];
}

+ (CIFilter *)lightenBlendModeFilter
{
    return [CIFilter filterWithName:@"CILightenBlendMode"];
}

+ (CIFilter *)lineOverlayFilter
{
    return [CIFilter filterWithName:@"CILineOverlay"];
}

+ (CIFilter *)lineScreenFilter
{
    return [CIFilter filterWithName:@"CILineScreen"];
}

+ (CIFilter *)linearBurnBlendModeFilter
{
    return [CIFilter filterWithName:@"CILinearBurnBlendMode"];
}

+ (CIFilter *)linearDodgeBlendModeFilter
{
    return [CIFilter filterWithName:@"CILinearDodgeBlendMode"];
}

+ (CIFilter *)linearGradientFilter
{
    return [CIFilter filterWithName:@"CILinearGradient"];
}

+ (CIFilter *)linearLightBlendModeFilter
{
    return [CIFilter filterWithName:@"CILinearLightBlendMode"];
}

+ (CIFilter *)linearToSRGBToneCurveFilter
{
    return [CIFilter filterWithName:@"CILinearToSRGBToneCurve"];
}

+ (CIFilter *)luminosityBlendModeFilter
{
    return [CIFilter filterWithName:@"CILuminosityBlendMode"];
}

+ (CIFilter *)maskToAlphaFilter
{
    return [CIFilter filterWithName:@"CIMaskToAlpha"];
}

+ (CIFilter *)maskedVariableBlurFilter
{
    return [CIFilter filterWithName:@"CIMaskedVariableBlur"];
}

+ (CIFilter *)maximumComponentFilter
{
    return [CIFilter filterWithName:@"CIMaximumComponent"];
}

+ (CIFilter *)maximumCompositingFilter
{
    return [CIFilter filterWithName:@"CIMaximumCompositing"];
}

+ (CIFilter *)medianFilter
{
    return [CIFilter filterWithName:@"CIMedianFilter"];
}

+ (CIFilter *)meshGeneratorFilter
{
    return [CIFilter filterWithName:@"CIMeshGenerator"];
}

+ (CIFilter *)minimumComponentFilter
{
    return [CIFilter filterWithName:@"CIMinimumComponent"];
}

+ (CIFilter *)minimumCompositingFilter
{
    return [CIFilter filterWithName:@"CIMinimumCompositing"];
}

+ (CIFilter *)mixFilter
{
    return [CIFilter filterWithName:@"CIMix"];
}

+ (CIFilter *)modTransitionFilter
{
    return [CIFilter filterWithName:@"CIModTransition"];
}

+ (CIFilter *)morphologyGradientFilter
{
    return [CIFilter filterWithName:@"CIMorphologyGradient"];
}

+ (CIFilter *)morphologyMaximumFilter
{
    return [CIFilter filterWithName:@"CIMorphologyMaximum"];
}

+ (CIFilter *)morphologyMinimumFilter
{
    return [CIFilter filterWithName:@"CIMorphologyMinimum"];
}

+ (CIFilter *)morphologyRectangleMaximumFilter
{
    return [CIFilter filterWithName:@"CIMorphologyRectangleMaximum"];
}

+ (CIFilter *)morphologyRectangleMinimumFilter
{
    return [CIFilter filterWithName:@"CIMorphologyRectangleMinimum"];
}

+ (CIFilter *)motionBlurFilter
{
    return [CIFilter filterWithName:@"CIMotionBlur"];
}

+ (CIFilter *)multiplyBlendModeFilter
{
    return [CIFilter filterWithName:@"CIMultiplyBlendMode"];
}

+ (CIFilter *)multiplyCompositingFilter
{
    return [CIFilter filterWithName:@"CIMultiplyCompositing"];
}

+ (CIFilter *)ninePartStretchedFilter
{
    return [CIFilter filterWithName:@"CINinePartStretched"];
}

+ (CIFilter *)ninePartTiledFilter
{
    return [CIFilter filterWithName:@"CINinePartTiled"];
}

+ (CIFilter *)noiseReductionFilter
{
    return [CIFilter filterWithName:@"CINoiseReduction"];
}

+ (CIFilter *)opTileFilter
{
    return [CIFilter filterWithName:@"CIOpTile"];
}

+ (CIFilter *)overlayBlendModeFilter
{
    return [CIFilter filterWithName:@"CIOverlayBlendMode"];
}

+ (CIFilter *)pageCurlTransitionFilter
{
    return [CIFilter filterWithName:@"CIPageCurlTransition"];
}

+ (CIFilter *)pageCurlWithShadowTransitionFilter
{
    return [CIFilter filterWithName:@"CIPageCurlWithShadowTransition"];
}

+ (CIFilter *)paletteCentroidFilter
{
    return [CIFilter filterWithName:@"CIPaletteCentroid"];
}

+ (CIFilter *)palettizeFilter
{
    return [CIFilter filterWithName:@"CIPalettize"];
}

+ (CIFilter *)parallelogramTileFilter
{
    return [CIFilter filterWithName:@"CIParallelogramTile"];
}

+ (CIFilter *)personSegmentationFilter
{
    return [CIFilter filterWithName:@"CIPersonSegmentation"];
}

+ (CIFilter *)perspectiveCorrectionFilter
{
    return [CIFilter filterWithName:@"CIPerspectiveCorrection"];
}

+ (CIFilter *)perspectiveRotateFilter
{
    return [CIFilter filterWithName:@"CIPerspectiveRotate"];
}

+ (CIFilter *)perspectiveTileFilter
{
    return [CIFilter filterWithName:@"CIPerspectiveTile"];
}

+ (CIFilter *)perspectiveTransformFilter
{
    return [CIFilter filterWithName:@"CIPerspectiveTransform"];
}

+ (CIFilter *)perspectiveTransformWithExtentFilter
{
    return [CIFilter filterWithName:@"CIPerspectiveTransformWithExtent"];
}

+ (CIFilter *)photoEffectChromeFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectChrome"];
}

+ (CIFilter *)photoEffectFadeFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectFade"];
}

+ (CIFilter *)photoEffectInstantFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectInstant"];
}

+ (CIFilter *)photoEffectMonoFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectMono"];
}

+ (CIFilter *)photoEffectNoirFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectNoir"];
}

+ (CIFilter *)photoEffectProcessFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectProcess"];
}

+ (CIFilter *)photoEffectTonalFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectTonal"];
}

+ (CIFilter *)photoEffectTransferFilter
{
    return [CIFilter filterWithName:@"CIPhotoEffectTransfer"];
}

+ (CIFilter *)pinLightBlendModeFilter
{
    return [CIFilter filterWithName:@"CIPinLightBlendMode"];
}

+ (CIFilter *)pinchDistortionFilter
{
    return [CIFilter filterWithName:@"CIPinchDistortion"];
}

+ (CIFilter *)pixellateFilter
{
    return [CIFilter filterWithName:@"CIPixellate"];
}

+ (CIFilter *)pointillizeFilter
{
    return [CIFilter filterWithName:@"CIPointillize"];
}

+ (CIFilter *)radialGradientFilter
{
    return [CIFilter filterWithName:@"CIRadialGradient"];
}

+ (CIFilter *)randomGeneratorFilter
{
    return [CIFilter filterWithName:@"CIRandomGenerator"];
}

+ (CIFilter *)rippleTransitionFilter
{
    return [CIFilter filterWithName:@"CIRippleTransition"];
}

+ (CIFilter *)roundedRectangleGeneratorFilter
{
    return [CIFilter filterWithName:@"CIRoundedRectangleGenerator"];
}

+ (CIFilter *)rowAverageFilter
{
    return [CIFilter filterWithName:@"CIRowAverage"];
}

+ (CIFilter *)sRGBToneCurveToLinearFilter
{
    return [CIFilter filterWithName:@"CISRGBToneCurveToLinear"];
}

+ (CIFilter *)saliencyMapFilter
{
    return [CIFilter filterWithName:@"CISaliencyMapFilter"];
}

+ (CIFilter *)saturationBlendModeFilter
{
    return [CIFilter filterWithName:@"CISaturationBlendMode"];
}

+ (CIFilter *)screenBlendModeFilter
{
    return [CIFilter filterWithName:@"CIScreenBlendMode"];
}

+ (CIFilter *)sepiaToneFilter
{
    return [CIFilter filterWithName:@"CISepiaTone"];
}

+ (CIFilter *)shadedMaterialFilter
{
    return [CIFilter filterWithName:@"CIShadedMaterial"];
}

+ (CIFilter *)sharpenLuminanceFilter
{
    return [CIFilter filterWithName:@"CISharpenLuminance"];
}

+ (CIFilter *)sixfoldReflectedTileFilter
{
    return [CIFilter filterWithName:@"CISixfoldReflectedTile"];
}

+ (CIFilter *)sixfoldRotatedTileFilter
{
    return [CIFilter filterWithName:@"CISixfoldRotatedTile"];
}

+ (CIFilter *)smoothLinearGradientFilter
{
    return [CIFilter filterWithName:@"CISmoothLinearGradient"];
}

+ (CIFilter *)softLightBlendModeFilter
{
    return [CIFilter filterWithName:@"CISoftLightBlendMode"];
}

+ (CIFilter *)sourceAtopCompositingFilter
{
    return [CIFilter filterWithName:@"CISourceAtopCompositing"];
}

+ (CIFilter *)sourceInCompositingFilter
{
    return [CIFilter filterWithName:@"CISourceInCompositing"];
}

+ (CIFilter *)sourceOutCompositingFilter
{
    return [CIFilter filterWithName:@"CISourceOutCompositing"];
}

+ (CIFilter *)sourceOverCompositingFilter
{
    return [CIFilter filterWithName:@"CISourceOverCompositing"];
}

+ (CIFilter *)spotColorFilter
{
    return [CIFilter filterWithName:@"CISpotColor"];
}

+ (CIFilter *)spotLightFilter
{
    return [CIFilter filterWithName:@"CISpotLight"];
}

+ (CIFilter *)starShineGeneratorFilter
{
    return [CIFilter filterWithName:@"CIStarShineGenerator"];
}

+ (CIFilter *)straightenFilter
{
    return [CIFilter filterWithName:@"CIStraightenFilter"];
}

+ (CIFilter *)stretchCropFilter
{
    return [CIFilter filterWithName:@"CIStretchCrop"];
}

+ (CIFilter *)stripesGeneratorFilter
{
    return [CIFilter filterWithName:@"CIStripesGenerator"];
}

+ (CIFilter *)subtractBlendModeFilter
{
    return [CIFilter filterWithName:@"CISubtractBlendMode"];
}

+ (CIFilter *)sunbeamsGeneratorFilter
{
    return [CIFilter filterWithName:@"CISunbeamsGenerator"];
}

+ (CIFilter *)swipeTransitionFilter
{
    return [CIFilter filterWithName:@"CISwipeTransition"];
}

+ (CIFilter *)temperatureAndTintFilter
{
    return [CIFilter filterWithName:@"CITemperatureAndTint"];
}

+ (CIFilter *)textImageGeneratorFilter
{
    return [CIFilter filterWithName:@"CITextImageGenerator"];
}

+ (CIFilter *)thermalFilter
{
    return [CIFilter filterWithName:@"CIThermal"];
}

+ (CIFilter *)toneCurveFilter
{
    return [CIFilter filterWithName:@"CIToneCurve"];
}

+ (CIFilter *)torusLensDistortionFilter
{
    return [CIFilter filterWithName:@"CITorusLensDistortion"];
}

+ (CIFilter *)triangleKaleidoscopeFilter
{
    return [CIFilter filterWithName:@"CITriangleKaleidoscope"];
}

+ (CIFilter *)triangleTileFilter
{
    return [CIFilter filterWithName:@"CITriangleTile"];
}

+ (CIFilter *)twelvefoldReflectedTileFilter
{
    return [CIFilter filterWithName:@"CITwelvefoldReflectedTile"];
}

+ (CIFilter *)twirlDistortionFilter
{
    return [CIFilter filterWithName:@"CITwirlDistortion"];
}

+ (CIFilter *)unsharpMaskFilter
{
    return [CIFilter filterWithName:@"CIUnsharpMask"];
}

+ (CIFilter *)vignetteEffectFilter
{
    return [CIFilter filterWithName:@"CIVignetteEffect"];
}

+ (CIFilter *)vignetteFilter
{
    return [CIFilter filterWithName:@"CIVignette"];
}

+ (CIFilter *)vividLightBlendModeFilter
{
    return [CIFilter filterWithName:@"CIVividLightBlendMode"];
}

+ (CIFilter *)vortexDistortionFilter
{
    return [CIFilter filterWithName:@"CIVortexDistortion"];
}

+ (CIFilter *)whitePointAdjustFilter
{
    return [CIFilter filterWithName:@"CIWhitePointAdjust"];
}

+ (CIFilter *)xRayFilter
{
    return [CIFilter filterWithName:@"CIXRay"];
}

+ (CIFilter *)zoomBlurFilter
{
    return [CIFilter filterWithName:@"CIZoomBlur"];
}

@end
