// The port's own engine, asked the same twenty-one questions through the dylib the library is built as.
//
// The dylib is dlopen'd rather than linked, for the reason the archive is hidden: ggml's symbols are
// compiled -fvisibility=hidden so the engine is never API of an image that links it, and a program cannot
// bind to a hidden symbol in a static archive. The dylib keeps them to itself and exports the one
// CharonMLC entry point this test dlsym's, so the two answers are produced by the same arrangement of
// code the gate builds - not by a program that happens to be able to see the engine's symbols.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "CharonMLCompute.h"
#import "CharonMLCGraph.h"
#import "cases.h"

typedef BOOL (*CharonElementwise)(MLCLayer *layer, MLCTensor *input, MLCTensor *output);

int main(int argc, const char **argv)
{
    setbuf(stdout, NULL);
    if (argc < 2) {
        printf("usage: port <the dylib>\n");
        return 2;
    }
    void *library = dlopen(argv[1], RTLD_NOW);
    if (!library) {
        printf("dlopen failed: %s\n", dlerror());
        return 1;
    }
    CharonElementwise elementwise = (CharonElementwise)dlsym(library, "CharonMLCElementwise");
    if (!elementwise) {
        printf("dlsym failed: %s\n", dlerror());
        return 1;
    }
    @autoreleasepool {
        for (int type = 0; type < CHARON_CASES; type++) {
            MLCTensorDescriptor *descriptor = [MLCTensorDescriptor descriptorWithShape:@[ @1, @1, @2, @2 ] dataType:MLCDataTypeFloat32];
            MLCTensor *input = [MLCTensor tensorWithDescriptor:descriptor fillWithData:@(0)];
            const float numbers[4] = { 1, 2, 3, 4 };
            [input copyDataFromDeviceMemoryToBytes:(void *)numbers length:sizeof(numbers) synchronizeWithDevice:NO];
            MLCTensor *result = [MLCTensor tensorWithDescriptor:descriptor fillWithData:@(0)];
            MLCActivationLayer *layer = [MLCActivationLayer layerWithDescriptor:[MLCActivationDescriptor descriptorWithType:(MLCActivationType)type]];
            if (!elementwise(layer, input, result)) {
                printf("activation %s\t(no answer)\n", charon_case_names[type]);
                continue;
            }
            const float *values = result.data.bytes;
            printf("activation %s\t%g,%g,%g,%g\n", charon_case_names[type], values[0], values[1], values[2], values[3]);
        }
    }
    dlclose(library);
    return 0;
}
