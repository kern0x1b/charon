// The host's own MLCompute, asked what each of the twenty-one activation types computes for a 2x2 image
// of one channel holding 1, 2, 3, 4. This is the side the port is held to, and it is the same question
// tests/backports/host/mlcompute/engine.m asked when the measurements were taken.
#import <Foundation/Foundation.h>
#import <MLCompute/MLCompute.h>
#import "cases.h"

int main(void)
{
    setbuf(stdout, NULL);
    @autoreleasepool {
        for (int type = 0; type < CHARON_CASES; type++) {
            MLCTensorDescriptor *descriptor = [MLCTensorDescriptor descriptorWithShape:@[ @1, @1, @2, @2 ] dataType:MLCDataTypeFloat32];
            MLCTensor *input = [MLCTensor tensorWithDescriptor:descriptor];
            [input bindAndWriteData:[MLCTensorData dataWithBytesNoCopy:(float[4]){ 1, 2, 3, 4 } length:4 * sizeof(float)] toDevice:nil];
            MLCTensor *result = [MLCTensor tensorWithDescriptor:descriptor];
            [result bindAndWriteData:[MLCTensorData dataWithBytesNoCopy:calloc(1, 4 * sizeof(float)) length:4 * sizeof(float)] toDevice:nil];
            MLCActivationLayer *layer = [MLCActivationLayer layerWithDescriptor:[MLCActivationDescriptor descriptorWithType:type]];

            MLCDevice *cpu = [MLCDevice cpuDevice];
            MLCGraph *graph = [MLCGraph graph];
            MLCTensor *output = [graph nodeWithLayer:layer source:input];
            MLCInferenceGraph *inference = [MLCInferenceGraph graphWithGraphObjects:@[ graph ]];
            BOOL ready = [inference addInputs:@{ @"input": input }] && [inference addOutputs:@{ @"output": output }] &&
                         [inference compileWithOptions:MLCGraphCompilationOptionsNone device:cpu];
            __block BOOL done = NO;
            __block NSString *outcome = nil;
            if (ready) {
                [inference executeWithInputsData:@{ @"input": [MLCTensorData dataWithBytesNoCopy:(float[4]){ 1, 2, 3, 4 } length:4 * sizeof(float)] }
                                     outputsData:@{ @"output": [MLCTensorData dataWithBytesNoCopy:calloc(1, 4 * sizeof(float)) length:4 * sizeof(float)] }
                                       batchSize:0 options:MLCExecutionOptionsSynchronous
                                completionHandler:^(MLCTensor *tensor, NSError *error, NSTimeInterval time) {
                                    done = YES;
                                    outcome = error ? @"error" : @"ok";
                                }];
                for (int spin = 0; spin < 2000 && !done; spin++) {
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
                }
            }
            if (!done || ![outcome isEqualToString:@"ok"]) {
                printf("activation %s\t(no answer: %s)\n", charon_case_names[type], outcome.UTF8String ?: "did not compile");
                continue;
            }
            const float *values = result.data.bytes;
            printf("activation %s\t%g,%g,%g,%g\n", charon_case_names[type], values[0], values[1], values[2], values[3]);
        }
    }
    return 0;
}
