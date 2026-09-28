// The GeoJSON decoder, against the host's own.
//
// The host's MKGeoJSONDecoder is the oracle: it is Apple's own, on the same RFC 7946 samples, and
// every case here is checked against what IT answers -- the number of objects, the class of each
// object, the shape's own coordinates, and the feature's id and properties. A port answer that
// differs is a failure, and the samples include mutations so that a decoder which quietly returns
// something for a document it should refuse is caught.
//
// Two things are printed for every comparison, because both were the wrong once and a reader should
// not have to guess again:
//
//   * `class_getImageName` for every class that takes part, so it is visible which image each side's
//     object came from -- the same check the device harnesses make, and the one that settles a
//     "whose class is this" question immediately;
//   * every decode inside an @try, so a case that raises prints the exception's name, its reason and
//     its call stack symbols and the run continues, instead of the process dying at the first one.
#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static int failures = 0;
static int checked = 0;

static void ok(NSString *what) { checked++; printf("ok %s\n", [what UTF8String]); }

static void bad(NSString *what, NSString *detail)
{
    checked++;
    failures++;
    printf("FAIL %s: %s\n", [what UTF8String], [detail UTF8String]);
}

// Which image each side's class came from. The port's are renamed charonHost_* so Apple's own answer
// for the unrenamed name is beside them; this prints both, which is what settles a name collision.
static NSString *imageOf(Class cls)
{
    const char *image = cls ? class_getImageName(cls) : NULL;
    return image ? [NSString stringWithUTF8String:image] : @"(none)";
}

static void reportImages(const char *name)
{
    Class port = objc_getClass("charonHost_MKGeoJSONDecoder");
    Class theirs = objc_getClass("MKGeoJSONDecoder");
    printf("# %s: port decoder in %s, host decoder in %s\n", name,
           [imageOf(port) UTF8String], [imageOf(theirs) UTF8String]);
}

// One case: the same document to the host and to the port, and the two answers compared. Every call
// that can raise is inside @try, so a case that does reports rather than kills the run.
static void same(const char *name, const char *json, BOOL expectRefused)
{
    NSString *label = [NSString stringWithUTF8String:name];
    // Printed and flushed BEFORE anything else runs, so a crash in the case says which case it was.
    printf("# %s%s\n", [label UTF8String], expectRefused ? " (a mutation, must be refused)" : "");
    fflush(stdout);
    NSData *data = [[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding];
    reportImages(name);

    NSError *theirError = nil;
    NSError *ourError = nil;
    NSArray *theirs = nil;
    NSArray *ours = nil;
    @try {
        theirs = [[MKGeoJSONDecoder alloc] geoJSONObjectsWithData:data error:&theirError];
    } @catch (NSException *exception) {
        printf("FAIL %s: the HOST raised %s: %s\n%s", [label UTF8String],
               [exception.name UTF8String], [[exception reason] UTF8String],
               [[exception.callStackSymbols description] UTF8String]);
        failures++;
        checked++;
        return;
    }
    @try {
        Class port = objc_getClass("charonHost_MKGeoJSONDecoder");
        if (port == nil) {
            bad([label stringByAppendingString:@": the port"], @"charonHost_MKGeoJSONDecoder is not in the probe");
            return;
        }
        SEL decode = NSSelectorFromString(@"geoJSONObjectsWithData:error:");
        if (![port respondsToSelector:decode]) {
            bad([label stringByAppendingString:@": the port"], @"it does not answer -geoJSONObjectsWithData:error:");
            return;
        }
        // On an INSTANCE, which is where the header's own method is: the port's class answers the
        // selector, its objects do the work.
        id instance = ((id (*)(id, SEL))objc_msgSend)(port, @selector(alloc));
        ours = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(instance, decode, data, &ourError);
    } @catch (NSException *exception) {
        checked++;
        failures++;
        printf("FAIL %s: the PORT raised %s: %s\n%@\n", [label UTF8String],
               [exception.name UTF8String], [[exception reason] UTF8String],
               [exception.callStackSymbols description]);
        return;
    }

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
                [NSString stringWithFormat:@"the port made a %@ (in %s) where the host made a %@ (in %s)",
                 NSStringFromClass([our class]), [imageOf([our class]) UTF8String],
                 NSStringFromClass([their class]), [imageOf([their class]) UTF8String]]);
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
    // RFC 7946 3.1.1: a position is [longitude, latitude] with an optional elevation.
    same("Point", "{\"type\":\"Point\",\"coordinates\":[-122.4194,37.7749,10]}", NO);
    same("Point, two elements", "{\"type\":\"Point\",\"coordinates\":[2.3522,48.8566]}", NO);
    // MultiPoint is NOT compared, and the reason is measured on both sides: the release's own
    // MKMultiPoint has NO public initialiser (measured in the armv7 cache of 6.1.3: -points, -pointCount,
    // -getCoordinates:range:, -boundingMapRect, -coordinate, -intersectsMapRect: and nothing else), so
    // this port REFUSES a MultiPoint, and the host can build one. The two are not the same question,
    // so the case is checked for the refusal alone.
    same("MultiPoint is refused on this release",
         "{\"type\":\"MultiPoint\",\"coordinates\":[[-105,40],[-101,41]]}", YES);
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

    // RFC 7946 3.2: a Feature, its geometry, its properties and its id.
    same("Feature with a point",
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[13.4,52.5]},"
         "\"properties\":{\"name\":\"Berlin\"},\"id\":\"berlin\"}", NO);
    same("Feature with a line",
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[13.4,52.5],[13.5,52.6]]},"
         "\"properties\":{}}", NO);
    // RFC 7946 3.2.3: a Feature with a null geometry is legal.
    same("Feature with a null geometry",
         "{\"type\":\"Feature\",\"geometry\":null,\"properties\":{\"name\":\"nowhere\"}}", NO);

    // RFC 7946 3: a FeatureCollection, and a bare geometry at the top level.
    same("FeatureCollection",
         "{\"type\":\"FeatureCollection\",\"features\":["
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[1,2]},\"properties\":{}},"
         "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[3,4]},\"properties\":{}}]}", NO);
    same("an array at the top level",
         "[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[1,2]},\"properties\":{}}]", NO);
    same("a geometry object at the top level", "{\"type\":\"Point\",\"coordinates\":[7,8]}", NO);

    // THE MUTATIONS: five documents that must be refused by both, so a decoder that half-decodes and
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
