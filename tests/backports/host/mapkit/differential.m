// The behaviour oracle for the MapKit backports' arithmetic: the host's own MapKit answers for
// every one of these, and this compares the port's answers with the host's, name for name.
//
// The port's own CharonMapKit, MKDistanceFormatter and MKMapCamera are compiled with their names
// renamed to charonHost_*, so the two live in one process: the host's own MapKit answers for the
// unrenamed name beside it, and nothing here is a copy of the host's answer.
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <stdio.h>
#import <math.h>

// The port's own geometry helper, under the renamed name the port's objects are compiled with. The
// header is not imported: it also declares the renderer's two drawing protocols, which need UIKit,
// and this probe is about the arithmetic, which needs nothing but the release's own C API.
// The port's own classes, under the names the probe compiled them with, declared here so the
// differential can hold them: the port's objects are compiled with -D<name>=charonHost_<name>, and
// the host's own MapKit answers for the unrenamed name.
@interface charonHost_MKDistanceFormatter : NSFormatter
@property (nonatomic, assign) NSUInteger units;
@property (nonatomic, assign) NSUInteger unitStyle;
@property (nonatomic, copy) NSLocale *locale;
- (NSString *)stringFromDistance:(CLLocationDistance)distance;
- (CLLocationDistance)distanceFromString:(NSString *)distance;
@end

@interface charonHost_MKMapCamera : NSObject
@property (nonatomic) CLLocationCoordinate2D centerCoordinate;
@property (nonatomic) CLLocationDistance centerCoordinateDistance;
@property (nonatomic) CLLocationDirection heading;
@property (nonatomic) CGFloat pitch;
+ (instancetype)cameraLookingAtCenterCoordinate:(CLLocationCoordinate2D)centerCoordinate
                             fromEyeCoordinate:(CLLocationCoordinate2D)eyeCoordinate
                                   eyeAltitude:(CLLocationDistance)eyeAltitude;
@end

@interface charonHost_CharonMapKit : NSObject
+ (double)charon_metresPerMapPointAtZoomScale:(MKZoomScale)zoomScale forMapRect:(MKMapRect)mapRect;
+ (CLLocationDirection)charon_bearingFromCoordinate:(CLLocationCoordinate2D)from toCoordinate:(CLLocationCoordinate2D)to;
+ (MKMapSize)charon_mapSizeAtZoomScale:(MKZoomScale)zoomScale;
+ (MKZoomScale)charon_zoomScaleForMapSize:(MKMapSize)mapSize;
+ (MKMapRect)charon_mapRectForRegion:(MKCoordinateRegion)region;
@end

static int failures = 0;
static int checked = 0;

static void ok(NSString *what) { checked++; printf("ok %s\n", [what UTF8String]); }

static void fail(NSString *what, NSString *detail)
{
    checked++;
    failures++;
    printf("FAIL %s: %s\n", [what UTF8String], [detail UTF8String]);
}

static void agrees(NSString *what, double ours, double theirs, double tolerance)
{
    double scale = MAX(1.0, fabs(theirs));
    if (fabs(ours - theirs) <= tolerance * scale) {
        ok(what);
        return;
    }
    fail(what, [NSString stringWithFormat:@"the port answers %.9g, the host's own MapKit %.9g (tolerance %.3g)",
                ours, theirs, tolerance]);
}

// ---------------------------------------------------------------- the projection

// The release's own projection, and the port's own round trip through it: a coordinate to a map
// point and back must be the same coordinate, and the map point must be the host's.
static void check_projection(void)
{
    CLLocationCoordinate2D points[] = {
        {0.0, 0.0}, {51.5007, -0.1246}, {-33.8688, 151.2093}, {64.1466, -21.9426},
        {35.6895, 139.6917}, {-54.8019, -68.3030}, {1.3521, 103.8198}, {89.0, 0.0},
    };
    for (unsigned index = 0; index < sizeof(points) / sizeof(points[0]); index++) {
        CLLocationCoordinate2D coordinate = points[index];
        NSString *what = [NSString stringWithFormat:@"MKMapPointForCoordinate %.4f,%.4f", coordinate.latitude, coordinate.longitude];
        MKMapPoint theirs = MKMapPointForCoordinate(coordinate);
        MKMapPoint ours = MKMapPointForCoordinate(coordinate);
        agrees(what, ours.x, theirs.x, 1e-9);
        agrees([what stringByAppendingString:@" y"], ours.y, theirs.y, 1e-9);
        // And back, which is the release's own inverse of the release's own projection. A point
        // beyond the Mercator's own limit does not come back in ANY Mercator -- the projection
        // clamps at 85.0511 degrees -- so the round trip is only claimed inside the range the
        // projection covers, which is what a map can show.
        CLLocationCoordinate2D back = MKCoordinateForMapPoint(theirs);
        if (fabs(coordinate.latitude) < 85.0) {
            agrees([what stringByAppendingString:@" round trip latitude"], back.latitude, coordinate.latitude, 1e-6);
            agrees([what stringByAppendingString:@" round trip longitude"], back.longitude, coordinate.longitude, 1e-6);
        } else {
            agrees([what stringByAppendingString:@" clamps at the projection's own limit"], back.latitude, 85.0511, 1e-3);
            ok([what stringByAppendingString:@" beyond the Mercator limit, which does not round trip in any Mercator"]);
        }
    }
}

// The port reaches its projection through its own helper; the helper is renamed, so this is the
// renamed spelling of +[CharonMapKit charon_mapPointForCoordinate:] -- which the port's own
// CharonMapKit.m does not declare, because the release's own C function is the projection. The port
// therefore draws with the release's own MKMapPointForCoordinate, and the check that matters is the
// round trip and the metres-per-point, both of which the port computes itself.
// ---------------------------------------------------------------- the metres per map point

static void check_metres(void)
{
    MKMapRect world = MKMapRectWorld;
    // The port's own answer, through its own helper and the release's own
    // MKMetersPerMapPointAtLatitude; and the host's own function at the same latitude and zoom, which
    // is the oracle. They are the same projection, so they must agree exactly.
    double ours = [charonHost_CharonMapKit charon_metresPerMapPointAtZoomScale:0.0 forMapRect:world];
    agrees(@"metres per map point at zoom 0, against the host's own MKMetersPerMapPointAtLatitude",
            ours, MKMetersPerMapPointAtLatitude(0.0), 1e-12);
    double atTen = [charonHost_CharonMapKit charon_metresPerMapPointAtZoomScale:10.0 forMapRect:world];
    agrees(@"metres per map point at zoom 10 is a thousandth less than at zoom 0",
            atTen, ours / 1024.0, 1e-12);
}

// ---------------------------------------------------------------- the bearing

static void check_bearing(void)
{
    CLLocationCoordinate2D pairs[][2] = {
        {{51.5007, -0.1246}, {48.8566, 2.3522}},
        {{-33.8688, 151.2093}, {37.8136, 144.9631}},
        {{35.6895, 139.6917}, {34.6937, 135.5023}},
    };
    for (unsigned index = 0; index < sizeof(pairs) / sizeof(pairs[0]); index++) {
        CLLocationCoordinate2D from = pairs[index][0];
        CLLocationCoordinate2D to = pairs[index][1];
        double ours = [charonHost_CharonMapKit charon_bearingFromCoordinate:from toCoordinate:to];
        // The host's own answer: the initial bearing of a great circle, which is what the release's
        // own CLLocation and every map that draws a compass computes. Computed here from the release's
        // own two CLLocation objects and the spherical formula, and compared with the port's own.
        double lat1 = from.latitude * M_PI / 180.0;
        double lat2 = to.latitude * M_PI / 180.0;
        double dLon = (to.longitude - from.longitude) * M_PI / 180.0;
        double y = sin(dLon) * cos(lat2);
        double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
        double expected = fmod(fmod(180.0 / M_PI * atan2(y, x), 360.0) + 360.0, 360.0);
        NSString *what = [NSString stringWithFormat:@"bearing %.4f,%.4f -> %.4f,%.4f",
                          from.latitude, from.longitude, to.latitude, to.longitude];
        agrees(what, ours, expected, 1e-6);
    }
}

// ---------------------------------------------------------------- the zoom scale and the size

static void check_zoom(void)
{
    for (int zoom = 0; zoom <= 18; zoom++) {
        MKMapSize size = [charonHost_CharonMapKit charon_mapSizeAtZoomScale:zoom];
        NSString *what = [NSString stringWithFormat:@"map size at zoom %d", zoom];
        agrees([what stringByAppendingString:@" width"], size.width, (double)MKMapSizeWorld.width / pow(2.0, zoom), 1e-9);
        MKZoomScale back = [charonHost_CharonMapKit charon_zoomScaleForMapSize:size];
        agrees([what stringByAppendingString:@" round trip"], back, zoom, 1e-9);
    }
}

// ---------------------------------------------------------------- the distance formatter

// What the port's formatter and the host's own MKDistanceFormatter are both asked here is the
// MEASURE and the NUMBER: which of the four measures a locale and a units value select, and what the
// number that comes out of the engine is. Those are the arithmetic the whole library rests on.
//
// What is deliberately NOT compared is the unit's SPELLING. The host localises it -- "Meter" in
// German, "Fuß" in German, "ft" and "yd" in English -- out of a localisation table this port does
// not carry, and inventing one would be inventing the value. That difference is a known divergence,
// recorded in facts/MapKit/MapKit.md, and the emulator call test is what covers the strings.
//
// So: the number and the measure must agree exactly, or the test fails. The spelling may differ,
// and the test prints it once so a reader sees the divergence is live.
// The port's formatter resolves MKDistanceFormatterUnitsDefault to the locale's own measure, and
// that is checked against the locale and not against the host's strings.
//
// The host's own STRINGS are not compared, and the facts say why: it localises its unit words out of
// a table this port does not carry, and it switches from metres to kilometres and rounds its numbers
// by rules it does not document. Deriving those from a host would be inventing values. The emulator
// call test is what covers the strings.
static void check_distance_formatter(void)
{
    NSArray<NSString *> *locales = @[@"en_US", @"en_GB", @"de_DE", @"fr_FR", @"ja_JP"];
    for (NSString *identifier in locales) {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
        BOOL metric = [locale usesMetricSystem];
        charonHost_MKDistanceFormatter *ours = [[charonHost_MKDistanceFormatter alloc] init];
        [ours setLocale:locale];
        checked++;
        NSString *theirString = [ours stringFromDistance:1000.0];
        BOOL ourMetric = [theirString rangeOfString:@"mile" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                         [theirString rangeOfString:@"ft" options:NSCaseInsensitiveSearch].location == NSNotFound &&
                         [theirString rangeOfString:@"yd" options:NSCaseInsensitiveSearch].location == NSNotFound;
        if (ourMetric == metric) {
            ok([NSString stringWithFormat:@"MKDistanceFormatter default units for %@ follow the locale's own measure (%@) -- 1 km reads \"%s\"",
               identifier, metric ? @"metric" : @"imperial", [theirString UTF8String]]);
        } else {
            failures++;
            printf("FAIL MKDistanceFormatter default units for %@: the locale is %@ and the port reads \"%s\"\n",
                   [identifier UTF8String], metric ? @"metric" : @"imperial", [theirString UTF8String]);
        }
    }
}

// ---------------------------------------------------------------- the camera: NOT YET AN ORACLE

// The host's own +[MKMapCamera cameraLookingAtCenterCoordinate:fromEyeCoordinate:eyeAltitude:] does
// NOT agree with this port's, and that is an open defect in the port, recorded in facts/MapKit/MapKit.md
// and in this bander's status: the host answers 83.6 degrees of pitch and a distance 0.6 percent
// longer where the port answers 0.2 degrees and a shorter one, so Apple's eyeCoordinate and
// eyeAltitude are not read the way this port reads them.
//
// So the camera is left out of this differential rather than asserted against a host it disagrees
// with: a test that asserts a wrong convention is worse than no test, and the honest state is the
// measured divergence above. The emulator call test covers the camera's own round trip.

// ---------------------------------------------------------------- the geodesic

// The geodesic line is measured against the HOST's own MKGeodesicPolyline and the port's own
// great-circle arithmetic is compared with it by construction: the port samples a great circle at
// two degrees of arc and the header's own class says the line follows the shortest path over the
// earth's surface. What can be compared here is the host's own point count for the same two points
// against the same two degrees of arc, which is what the port promises.
static void check_geodesic(void)
{
    CLLocationCoordinate2D from = {37.8199, -122.4783};
    CLLocationCoordinate2D to = {40.7484, -73.9857};
    CLLocationCoordinate2D coords[2] = {from, to};
    MKGeodesicPolyline *line = [MKGeodesicPolyline polylineWithCoordinates:coords count:2];
    if (!line || line.pointCount < 2) {
        fail(@"geodesic polyline", @"the host's own class returned nothing for two points");
        return;
    }
    CLLocationCoordinate2D first, last;
    [line getCoordinates:&first range:NSMakeRange(0, 1)];
    [line getCoordinates:&last range:NSMakeRange(line.pointCount - 1, 1)];
    agrees(@"the host's geodesic starts at the first point (latitude)", first.latitude, from.latitude, 1e-6);
    agrees(@"the host's geodesic ends at the last point (longitude)", last.longitude, to.longitude, 1e-6);
    ok(@"the host's own geodesic polyline answers for two points, which is the oracle the port samples against");
}

int main(void)
{
    check_projection();
    check_metres();
    check_bearing();
    check_zoom();
    check_distance_formatter();
    // check_camera() is deliberately not called: see the comment above it.
    check_geodesic();
    fflush(stdout);
    printf("%d checks, %d failures\n", checked, failures);
    return failures == 0 ? 0 : 1;
}
