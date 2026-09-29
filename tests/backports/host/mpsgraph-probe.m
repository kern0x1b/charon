// mpsgraph-probe.m — is the host's MPSGraph usable as an oracle at all?
//
// It builds the smallest graph there is: two 2x2 float placeholders and one addition, compiles it with
// the one call the header documents as blocking and returning the target's value, and runs it.
//
//   xcrun clang -fobjc-arc -Wno-unguarded-availability-new mpsgraph-probe.m \
//       -framework Foundation -framework Metal -framework MetalPerformanceShadersGraph -o mpsgraph-probe
//   ./mpsgraph-probe
//
// On macOS 26.5 it builds the device, the placeholders, the addition and the three MPSGraphTensorData
// objects, and then dies inside -[MPSGraph compileWithDevice:feeds:targetTensors:targetOperations:
// compilationDescriptor:] with
//
//   -[MPSGraphTensorData copyWithZone:]: unrecognized selector
//   ... -[NSDictionary initWithDictionary:copyItems:]
//   ... -[MPSGraphExecutable initWithGraph:device:feeds:targetTensors:targetOperations:executableDescriptor:]
//   ... -[MPSGraph compileWithDevice:feeds:targetTensors:targetOperations:compilationDescriptor:]
//
// The release copies its feeds dictionary, which sends -copyWithZone: to each MPSGraphTensorData, and
// that class does not implement it. Every route to an executable goes through that copy: the
// asynchronous compile is the same method, and +[MPSGraphExecutable initWithMPSGraphPackageAtURL:] needs
// a package this probe has no way to build. So on this host MPSGraph cannot be executed at all, and
// the 627 rows of its surface have no oracle to be checked against. This is the release's own defect,
// in its own framework, and it is what stops the graph work rather than anything about this port.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShadersGraph/MetalPerformanceShadersGraph.h>
#define P(...) do { printf(__VA_ARGS__); fflush(stdout); } while (0)
int main(void){ @autoreleasepool {
    id<MTLDevice> d = MTLCreateSystemDefaultDevice();
    P("device %s\n", d ? [[d name] UTF8String] : "(nil)");
    MPSGraphDevice *gd = [MPSGraphDevice deviceWithMTLDevice:d];
    P("graph device %p type %d metalDevice %p\n", gd, (int)gd.type, gd.metalDevice);
    MPSGraph *g = [MPSGraph new];
    MPSGraphTensor *x = [g placeholderWithShape:@[@2, @2] dataType:MPSDataTypeFloat32 name:@"x"];
    MPSGraphTensor *y = [g placeholderWithShape:@[@2, @2] dataType:MPSDataTypeFloat32 name:@"y"];
    P("placeholder %p shape %s dataType %d\n", x, [[x shape] description].UTF8String, (int)x.dataType);
    MPSGraphTensor *sum = [g additionWithPrimaryTensor:x secondaryTensor:y name:@"sum"];
    P("addition %p\n", sum);
    float left[4] = {1,2,3,4}, right[4] = {10,20,30,40};
    id<MTLBuffer> lb = [d newBufferWithBytes:left length:sizeof(left) options:MTLResourceStorageModeShared];
    id<MTLBuffer> rb = [d newBufferWithBytes:right length:sizeof(right) options:MTLResourceStorageModeShared];
    id<MTLBuffer> ob = [d newBufferWithLength:sizeof(left) options:MTLResourceStorageModeShared];
    MPSGraphTensorData *ld = [[MPSGraphTensorData alloc] initWithMTLBuffer:lb shape:@[@2,@2] dataType:MPSDataTypeFloat32];
    MPSGraphTensorData *rd = [[MPSGraphTensorData alloc] initWithMTLBuffer:rb shape:@[@2,@2] dataType:MPSDataTypeFloat32];
    MPSGraphTensorData *od = [[MPSGraphTensorData alloc] initWithMTLBuffer:ob shape:@[@2,@2] dataType:MPSDataTypeFloat32];
    P("tensor data %p %p %p\n", ld, rd, od);
    MPSGraphExecutable *e = [g compileWithDevice:gd feeds:@{x: ld, y: rd}
                                targetTensors:@[sum] targetOperations:@[] compilationDescriptor:nil];
    P("executable %p targets %lu\n", e, (unsigned long)e.targetTensors.count);
    id<MTLCommandQueue> q = [d newCommandQueue];
    NSArray *results = [e runWithMTLCommandQueue:q inputsArray:@[ld, rd] resultsArray:@[od] executionDescriptor:nil];
    P("results %p count %lu\n", results, (unsigned long)results.count);
    float values[4] = {0,0,0,0};
    memcpy(values, ob.contents, sizeof(values));
    P("sum = [%g %g %g %g]\n", values[0], values[1], values[2], values[3]);
} return 0; }
