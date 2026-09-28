// The GeoJSON decoder, against the host's own -- in TWO PROCESSES, because there is no other honest
// way to do it here.
//
// The port's decoder is Apple's own class name (MKGeoJSONDecoder) because that is what a program
// links, and macOS's MapKit has a class of the same name. Renaming the port's into a static link --
// which is what the first version of this probe did -- produces a class the loader does not finish
// registering: class_getImageName finds it, respondsToSelector: says no, and class_copyMethodList on
// it raises SIGBUS. That is the harness's registration, not the port's source, and this form avoids
// it entirely: each side runs in its own process, so each side's class is its own, nothing is
// renamed, and the two answers are compared as text.
//
//   runner  one document in, one transcript out: the number of objects, each object's class and the
//           image that class came from, a shape's own coordinates, a feature's id and properties. It
//           loads the port's dylib when CHARON_PORT_DYLIB says so, and answers with Apple's own
//           MKGeoJSONDecoder when it does not.
//   run.sh  builds the port's decoder as a dylib, runs the runner twice per case, and diffs.
#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdio.h>

// One decode, and everything about the answer as text. The two processes print the same lines for
// the same document, so a difference in the output is a difference in the decoder.
static void run_one(const char *name, const char *json, int expectRefused)
{
    printf("case %s\n", name);
    printf("  port_dylib %s\n", getenv("CHARON_PORT_DYLIB") ?: "(none: Apple's own decoder)");
    Class decoder = NSClassFromString(@"MKGeoJSONDecoder");
    const char *image = decoder ? class_getImageName(decoder) : "(no class)";
    printf("  decoder_class_image %s\n", image);
    if (decoder == nil) {
        printf("  result no-class\n");
        return;
    }
    NSData *data = [[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSArray *objects = nil;
    @try {
        objects = [[decoder alloc] geoJSONObjectsWithData:data error:&error];
    } @catch (NSException *exception) {
        printf("  raised %s: %s\n", [exception.name UTF8String], [[exception reason] UTF8String]);
        return;
    }
    printf("  refused %d\n", objects == nil ? 1 : 0);
    if (objects == nil) {
        printf("  error %s\n", [[error localizedDescription] UTF8String] ?: "(none)");
        return;
    }
    printf("  error %s\n", [[error localizedDescription] UTF8String] ?: "(none)");
    printf("  count %lu\n", (unsigned long)objects.count);
    for (id object in objects) {
        printf("  object %s image %s\n", class_getName([object class]), class_getImageName([object class]));
        if ([object isKindOfClass:[MKGeoJSONFeature class]]) {
            NSString *identifier = [object valueForKey:@"identifier"];
            NSData *properties = [object valueForKey:@"properties"];
            NSArray *geometry = [object valueForKey:@"geometry"];
            printf("    identifier %s\n", identifier ? [identifier UTF8String] : "(nil)");
            printf("    properties %s\n", properties ? [[properties description] UTF8String] : "(nil)");
            printf("    shapes %lu\n", (unsigned long)geometry.count);
            for (id shape in geometry) {
                printf("    shape %s points %lu\n", class_getName([shape class]),
                       (unsigned long)[(MKMultiPoint *)shape pointCount]);
                if ([shape isKindOfClass:[MKPolyline class]]) {
                    MKPolyline *line = (MKPolyline *)shape;
                    CLLocationCoordinate2D *coordinates = calloc(line.pointCount, sizeof(CLLocationCoordinate2D));
                    [line getCoordinates:coordinates range:NSMakeRange(0, line.pointCount)];
                    for (NSUInteger index = 0; index < line.pointCount; index++) {
                        printf("      point %.9f %.9f\n", coordinates[index].latitude, coordinates[index].longitude);
                    }
                    free(coordinates);
                }
                if ([shape isKindOfClass:[MKPolygon class]]) {
                    MKPolygon *polygon = (MKPolygon *)shape;
                    printf("      holes %lu\n", (unsigned long)polygon.interiorPolygons.count);
                }
            }
        }
    }
    (void)expectRefused;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: runner NAME JSON\n");
        return 2;
    }
    @autoreleasepool {
        run_one(argv[1], argv[2], 0);
    }
    fflush(stdout);
    return 0;
}
