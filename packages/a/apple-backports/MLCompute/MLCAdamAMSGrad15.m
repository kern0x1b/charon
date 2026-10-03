// The one factory of MLCAdamOptimizer whose availability the SDK of iOS 16.4 spells differently from
// every other annotation in MLCompute: `MLCOMPUTE_AVAILABLE_STARTING(macos(12.0), ios(15), tvos(15))`,
// with "ios(15)" and not "ios(15.0)" as MLCAdamWOptimizer and the three properties of MLCOptimizer beside
// it are spelled. It is an object of its own for that reason and not in MLCOptimizers15.m: an object
// carries the API of one release, and the band splitter reads these two spellings as two versions of it
// (modules/apple/backports.lua, misplaced()).
//
// Measured against this host's own MLCompute: the five arguments are the caller's, verbatim - 0.4, 0.5,
// 0.6, YES and 9 come back as 0.400000006, 0.5, 0.600000024, YES and 9 - and the descriptor's seven numbers
// come through with them.

#import "CharonMLCompute.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wnullability-completeness"

@implementation MLCAdamOptimizer

+ (instancetype)optimizerWithDescriptor:(MLCOptimizerDescriptor *)optimizerDescriptor
                                  beta1:(float)beta1
                                  beta2:(float)beta2
                                epsilon:(float)epsilon
                            usesAMSGrad:(BOOL)usesAMSGrad
                               timeStep:(NSUInteger)timeStep
{
    MLCAdamOptimizer *optimizer = [self optimizerWithDescriptor:optimizerDescriptor];
    [optimizer charon_mlc_state].beta1 = beta1;
    [optimizer charon_mlc_state].beta2 = beta2;
    [optimizer charon_mlc_state].epsilon = epsilon;
    [optimizer charon_mlc_state].usesAMSGrad = usesAMSGrad;
    [optimizer charon_mlc_state].timeStep = timeStep;
    return optimizer;
}

@end