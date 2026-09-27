#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>

typedef void (^VisionRecorder)(NSString *name, NSString *value);

/* The containers the Core ML case runs, by name, or NULL when the test has none: the Vision
 * differential is a host check and the models live beside it, and a run without them says so
 * rather than skipping the case quietly. */
typedef struct {
    NSURL *glm_classifier;
} CoreMLModels;

CoreMLModels vision_coreml_models(void);
/* A picture of the given size, made in memory, for a request handler to be given. */
CGImageRef vision_picture(size_t wide, size_t high);

void vision_run(VisionRecorder record, CoreMLModels models);
