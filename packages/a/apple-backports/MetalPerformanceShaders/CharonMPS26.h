// CharonMPS26.h - the names the 26.2 surface has and the SDK this package compiles against does not.
//
// The iPhoneOS 16.4 SDK is what this package compiles against, and MetalPerformanceShaders moved
// between it and 26.2. Where 26.2 declares a member that 16.4 does not, the member is transcribed
// here from the 26.2 headers and the implementation carries it, so an application built against 26.2
// finds what it links for. Each one is a name no header this build compiles against declares, and each
// is an R4 item: the lift's sets have to be re-measured in the push that lands it.
//
// Transcribed from $SDK26/System/Library/Frameworks/MetalPerformanceShaders.framework/Frameworks,
// read on 2026-09-28. Nothing here is invented: it is what 26.2 says, copied.

#ifndef MPS_CHARON_26_H
#define MPS_CHARON_26_H

#import "CharonMPS.h"

// MPSCNNConvolutionDescriptor's third neuron parameter. 16.4 declares neuronType, neuronParameterA
// and neuronParameterB; 26.2 adds C, which the Power, Exponential and Logarithm formulas use.
@interface MPSCNNConvolutionDescriptor (CharonMPS26)
- (float)charon_mps_neuronParameterC;
- (void)charon_mps_setNeuronParameterC:(float)value;
- (BOOL)charon_mps_hasBatchNormalization;
@end

// MPSGraphObject arrived in iOS 17 and every class of the 26.2 surface descends from it; 16.4 has them
// descending from NSObject. Three further 26.2 names are in no 16.4 header at all.
#if !defined(__MAC_OS_X_VERSION_MAX_ALLOWED) || __MAC_OS_X_VERSION_MAX_ALLOWED < 260000
@interface MPSGraphObject : NSObject
@end

// And the three descriptors the 26.2 headers declare that 16.4 does not, transcribed from
// MPSCNNConvolution.h and MPSGraphExecutable.h of 26.2.
@interface MPSGraphFFTDescriptor : NSObject
@end

@interface MPSGraphImToColOpDescriptor : NSObject
@end

@interface MPSGraphExecutableSerializationDescriptor : NSObject
@end
#endif

#endif /* MPS_CHARON_26_H */
