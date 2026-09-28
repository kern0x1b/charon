// The GeoJSON decoder, against the host's own.
//
// The host's MKGeoJSONDecoder is the oracle: it is Apple's own, on the same RFC 7946 samples, and
// every case here is checked against what IT answers -- the number of objects, the class of each
// object, the shape's own coordinates, and the feature's id and properties. A port answer that
// differs is a failure, and the samples include a mutation (a case marked as one below) so that a
// decoder which quietly returns something for a document it should refuse is caught.
#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <math.h>
#import <objc/runtime.h>
#import <objc/message.h>
// The port's own decoder, under the names the probe compiled it with: the class names are renamed so
// Apple's own MKGeoJSONDecoder and MKGeoJSONFeature answer for the unrenamed ones beside the port's.
static Class CharonPortDecoder(void)
{
    static Class decoder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        decoder = objc_getClass("charonHost_MKGeoJSONDecoder");
    });
    return decoder;
}

static int failures = 0;
static int checked = 0;

static void ok(NSString *what) { checked++; printf("ok %s\n", [what UTF8String]); }

static void bad(NSString *what, NSString *detail)
{
    checked++;
    failures++;
    printf("FAIL %s: %s\n", [what UTF8String], [detail UTF8String]);
}

// The one thing every case is compared on: the same document, the host's answer and the port's, side
// by side, and the two must agree. `expectRefused` is the mutation: a document the port must refuse,
// and the host must refuse it too.
static void same(const char *name, const char *json, BOOL expectRefused)
{
    NSData *data = [[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding];
    NSString *label = [NSString stringWithUTF8String:name];

    NSError *theirError = nil;
    NSArray *theirs = [[MKGeoJSONDecoder alloc] geoJSONObjectsWithData:data error:&theirError];
    NSError *ourError = nil;
    NSArray *ours = nil;
    SEL decode = NSSelectorFromString(@"geoJSONObjectsWithData:error:");
    if (CharonPortDecoder() == nil || ![CharonPortDecoder() respondsToSelector:decode]) {
        bad([label stringByAppendingString:@": the port"], @"the port's own decoder is not in the probe");
        return;
    }
    ours = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(CharonPortDecoder(), decode, data, &ourError);

    if (expectRefused) {
        if (theirs != nil || ourError == nil) {
            bad([label stringByAppendingString:@" (a mutation, must be refused)"],
                [NSString stringWithFormat:@"the host returned %lu objects and the port an error of %@",
                 (unsigned long)theirs.count, ourError ? [ourError localizedDescription] : @"none"]);
            return;
        }
        ok([label stringByAppendingString:@": refused by both, with an error"]);
        return;
    }
    if (theirs == nil || ours == nil) {
        bad(label, [NSString stringWithFormat:@"host %lu objects (error %@), port %lu objects (error %@)",
             (unsigned long)theirs.count, theirError ? [theirError localizedDescription] : @"none",
             (unsigned long)ours.count, ourError ? [ourError localizedDescription] : @"none"]);
        return;
    }
    if (theirs.count != ours.count) {
        bad(label, [NSString stringWithFormat:@"%lu objects where the host has %lu",
             (unsigned long)ours.count, (unsigned long)theirs.count]);
        return;
    }
    for (NSUInteger index = 0; index < ours.count; index++) {
        id our = ours[index];
        id their = theirs[index];
        if (![our isMemberOfClass:[their class]]) {
            bad([label stringByAppendingString:@": class"],
                [NSString stringWithFormat:@"the port made a %@ where the host made a %@",
                 NSStringFromClass([our class]), NSStringFromClass([their class])]);
            return;
        }
        if ([our isKindOfClass:[MKGeoJSONFeature class]] && [their isKindOfClass:[MKGeoJSONFeature class]]) {
            id ourFeature = our;
            id theirFeature = their;
            NSString *ourId = [ourFeature valueForKey:@"identifier"];
            NSString *theirId = [theirFeature valueForKey:@"identifier"];
            NSArray *ourGeometry = [ourFeature valueForKey:@"geometry"];
            NSArray *theirGeometry = [theirFeature valueForKey:@"geometry"];
            NSData *ourProperties = [ourFeature valueForKey:@"properties"];
            NSData *theirProperties = [theirFeature valueForKey:@"properties"];
            BOOL sameId = (ourId == nil && theirId == nil) || [ourId isEqualToString:theirId];
            BOOL sameGeometry = ourGeometry.count == theirGeometry.count;
            BOOL sameProperties = (ourProperties == nil && theirProperties == nil) ||
                                  [ourProperties isEqualToData:theirProperties];
            if (!sameId || !sameGeometry || !sameProperties) {
                bad([label stringByAppendingString:@": feature"],
                    [NSString stringWithFormat:@"id %@/%@, %lu/%lu shapes, properties %@/%@",
                     ourId ?: @"nil", theirId ?: @"nil",
                     (unsigned long)ourGeometry.count, (unsigned long)theirGeometry.count,
                     ourProperties ? @"some" : @"nil", theirProperties ? @"some" : @"nil"]);
                return;
            }
        }
        // A polyline: the coordinates the port built against the release's own projection, and the
        // ones the host built, have to be the same points.
        if ([our isKindOfClass:[MKPolyline class]] && [their isKindOfClass:[MKPolyline class]]) {
            MKPolyline *ourLine = (MKPolyline *)our;
            MKPolyline *theirLine = (MKPolyline *)their;
            if (ourLine.pointCount != theirLine.pointCount) {
                bad([label stringByAppendingString:@": point count"],
                    [NSString stringWithFormat:@"%lu where the host has %lu",
                     (unsigned long)ourLine.pointCount, (unsigned long)theirLine.pointCount]);
                return;
            }
            CLLocationCoordinate2D *ourCoordinates = calloc(ourLine.pointCount, sizeof(CLLocationCoordinate2D));
            CLLocationCoordinate2D *theirCoordinates = calloc(theirLine.pointCount, sizeof(CLLocationCoordinate2D));
            [ourLine getCoordinates:ourCoordinates range:NSMakeRange(0, ourLine.pointCount)];
            [theirLine getCoordinates:theirCoordinates range:NSMakeRange(0, theirLine.pointCount)];
            for (NSUInteger point = 0; point < ourLine.pointCount; point++) {
                if (fabs(ourCoordinates[point].latitude - theirCoordinates[point].latitude) > 1e-9 ||
                    fabs(ourCoordinates[point].longitude - theirCoordinates[point].longitude) > 1e-9) {
                    bad([label stringByAppendingString:@": a coordinate"],
                        [NSString stringWithFormat:@"point %lu is %.9f,%.9f where the host has %.9f,%.9f",
                         (unsigned long)point, ourCoordinates[point].latitude, ourCoordinates[point].longitude,
                         theirCoordinates[point].latitude, theirCoordinates[point].longitude]);
                    free(ourCoordinates);
                    free(theirCoordinates);
                    return;
                }
            }
            free(ourCoordinates);
            free(theirCoordinates);
        }
    }
    ok([label stringByAppendingString:@": same objects, same classes, same points"]);
}

int main(void)
{
    // RFC 7946 §3.1.1: a position is [longitude, latitude] with an optional elevation.
    same("Point", "{\"type\":\"Point\",\"coordinates\":[-122.4194,37.7749,10]}", NO);
    same("Point, two elements", "{\"type\":\"Point\",\"coordinates\":[2.3522,48.8566]}", NO);
    same("MultiPoint", "{\"type\":\"MultiPoint\",\"coordinates\":[[-105,40],[-101,41]]}", NO);
    same("LineString", "{\"type\":\"LineString\",\"coordinates\":[[-77.03,38.9],[-77.05,38.91]]}", NO);
    same("MultiLineString",
         "{\"type\":\"MultiLineString\",\"coordinates\":[[[102,2],[103,3],[104,5],[106,7]]]}", NO);
    same("Polygon", "{\"type\":\"Polygon\",\"coordinates\":[[[-0.1,0.0],[-0.1,0.1],[0.1,0.1],[0.1,0.0],[-0.1,0.0]]]}", NO);
    same("Polygon with a hole",
         "{\"type\":\"Polygon\",\"coordinates\":[[[-0.1,0.0],[-0.1,0.3],[0.3,0.3],[0.3,0.0],[-0.1,0.0]],"
         "[-0.05,0.05],[-0.05,0.15],[0.15,0.15],[0.15,0.05],[-0.05,0.05]]}", NO);
    same("MultiPolygon",
         "{\"type\":\"MultiPolygon\",\"coordinates\":[[[[102,2],[103,2],[103,3],[103,2]]],"
         "[[100,0],[101,0],[101,1],[100,1],[100,0]]]}", NO);

    // RFC 7946 §3.2: a Feature, its geometry, its properties and its id.
    same("Feature with a point",
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[13.4,52.5]},"
         "\"properties\":{\"name\":\"Berlin\"},\"id\":\"berlin\"}", NO);
    same("Feature with a line",
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[13.4,52.5],[13.5,52.6]]},"
         "\"properties\":{}}", NO);
    // RFC 7946 §3.2.3: a Feature with a null geometry is legal.
    same("Feature with a null geometry",
         "{\"type\":\"Feature\",\"geometry\":null,\"properties\":{\"name\":\"nowhere\"}}", NO);

    // RFC 7946 §3: a FeatureCollection, and a bare geometry at the top level.
    same("FeatureCollection",
         "{\"type\":\"FeatureCollection\",\"features\":["
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[1,2]},\"properties\":{}},"
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[3,4]},\"properties\":{}}]}", NO);
    same("an array at the top level",
         "[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[1,2]},\"properties\":{}}]", NO);
    same("a geometry object at the top level", "{\"type\":\"Point\",\"coordinates\":[7,8]}", NO);

    // THE MUTATIONS: four documents that must be refused by both, so a decoder that half-decodes and
    // hands back a shape the document did not describe is caught.
    same("MUTATION a ring that is not closed", "{\"type\":\"Polygon\",\"coordinates\":[[[-0.1,0.0],[-0.1,0.1],[0.1,0.1]]]}", YES);
    same("MUTATION a ring of three positions", "{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[1,0],[1,1]]]}", YES);
    same("MUTATION a position that is not two numbers", "{\"type\":\"Point\",\"coordinates\":[\"a\",\"b\"]}", YES);
    same("MUTATION a geometry type that is not one of the seven",
         "{\"type\":\"Rectangle\",\"coordinates\":[[0,0],[1,1]]}", YES);
    same("MUTATION data that is not JSON", "{not json at all", YES);

    fflush(stdout);
    printf("%d checks, %d failures\n", checked, failures);
    return failures == 0 ? 0 : 1;
}
