// MKGeoJSONDecoder and MKGeoJSONFeature: RFC 7946 GeoJSON turned into the release's own shapes.
//
// This is the one family left on MapKit that is both small and complete, and it is the release's
// own work throughout: the geometry comes out as the release's MKPointAnnotation, MKMultiPoint,
// MKPolyline, MKMultiPolyline, MKPolygon and MKMultiPolygon, which the release has carried since 3.2
// (measured with apple.objc.inventory on the armv7 cache of 6.1.3), and the projection is the
// release's own MKMapPointForCoordinate, so a shape this decodes is a shape the release's own
// renderer draws. There is no wall here and nothing is invented.
//
// What RFC 7946 asks for, and what this does with it:
//   * a Feature's "geometry" is a geometry object, and the decoder hands back ONE array of shapes --
//     the header's own -geometry is NSArray<MKShape<MKGeoJSONObject> *> -- so a MultiPoint is one
//     shape with its points and a MultiPolygon is one shape with its polygons;
//   * a bare geometry object at the top level decodes to itself, not wrapped in a Feature, which is
//     what the header's own NSArray<id<MKGeoJSONObject>> is for;
//   * "properties" and "id" come back as the Feature's own NSData and NSString, byte for byte as they
//     were written, because the header types them as data and a string and a caller round-trips them;
//   * coordinates are longitude, latitude, optional elevation, in that order, per RFC 7946 §3.1.1, and
//     a bare 2-element position is accepted as well as a 3-element one;
//   * a "bbox", a foreign member and an unrecognised "type" are refused with an error rather than
//     half-decoded, so a caller finds out rather than getting a shape it did not ask for.
#import <MapKit/MapKit.h>
#import "CharonMapKit.h"

NS_ASSUME_NONNULL_BEGIN

// The decoder's own error, in the domain MapKit uses, with the reason a caller can act on.
static NSError *CharonGeoJSONError(NSString *reason)
{
    return [NSError errorWithDomain:@"MKErrorDomain" code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
}

// One coordinate out of an RFC 7946 position, through the release's own projection. A position is
// [longitude, latitude] with an optional elevation, in that order.
static BOOL CharonGeoJSONCoordinate(id position, CLLocationCoordinate2D *out)
{
    if (![position isKindOfClass:[NSArray class]] || [position count] < 2) {
        return NO;
    }
    id first = [position objectAtIndex:0];
    id second = [position objectAtIndex:1];
    if (![first isKindOfClass:[NSNumber class]] || ![second isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    double longitude = [first doubleValue];
    double latitude = [second doubleValue];
    if (longitude < -180.0 || longitude > 180.0 || latitude < -90.0 || latitude > 90.0) {
        return NO;
    }
    *out = CLLocationCoordinate2DMake(latitude, longitude);
    return YES;
}

// The positions of a LineString or a ring, into the release's own coordinates. `closed` is a ring's
// extra requirement: RFC 7946 §3.1.6 wants a LinearRing to have at least four positions and to be
// closed, and this enforces both rather than drawing a polygon the ring did not describe.
static NSArray<NSValue *> *CharonGeoJSONPositions(id coordinates, NSUInteger minimum, BOOL closed)
{
    if (![coordinates isKindOfClass:[NSArray class]] || [coordinates count] < minimum) {
        return nil;
    }
    NSMutableArray *values = [NSMutableArray array];
    for (id position in coordinates) {
        CLLocationCoordinate2D coordinate;
        if (!CharonGeoJSONCoordinate(position, &coordinate)) {
            return nil;
        }
        [values addObject:[NSValue valueWithBytes:&coordinate objCType:@encode(CLLocationCoordinate2D)]];
    }
    if (closed) {
        CLLocationCoordinate2D first, last;
        [values[0] getValue:&first];
        [values[values.count - 1] getValue:&last];
        if (first.latitude != last.latitude || first.longitude != last.longitude) {
            return nil;
        }
    }
    return values;
}

// The coordinates out of a shape the release owns, which is what every shape here ends up as.
static const CLLocationCoordinate2D *CharonGeoJSONCoordinates(NSArray<NSValue *> *values, NSUInteger *count)
{
    *count = values.count;
    /* Every caller has already refused an empty array, so the first value is there; the fallback is
     * spelled as a real pointer rather than a null the header's own nonnull would warn about. */
    return values.count > 0 ? (const CLLocationCoordinate2D *)[values[0] pointerValue]
                            : (const CLLocationCoordinate2D *)"";
}

@interface MKGeoJSONFeature ()
// The port's own initialiser: the header's class has none, and the decoder is what makes one.
- (instancetype)initWithGeometry:(NSArray<MKShape<MKGeoJSONObject> *> *)geometry
                       properties:(NSData *)featureProperties
                      identifier:(NSString *)featureIdentifier;
@end

// MKMultiPoint's map-point initialiser, which the 16.4 header does not declare and which the release
// carries (measured: MKMultiPoint has -initWithMapPoints:count: in the armv7 cache of 6.1.3).
@interface MKMultiPoint (CharonGeoJSONPoints)
- (instancetype)initWithMapPoints:(MKMapPoint *)points count:(NSUInteger)count;
@end

@implementation MKGeoJSONFeature {
    NSArray<MKShape<MKGeoJSONObject> *> *_geometry;
    NSData *_properties;
    NSString *_identifier;
}

@synthesize geometry = _geometry;
@synthesize properties = _properties;
@synthesize identifier = _identifier;

// A feature, built from what the decoder read out of it. The class extension's own initialiser,
// because the header's class has no initialiser and the decoder is what makes one. The `init` family
// because a feature is built once and never re-built.
- (instancetype)initWithGeometry:(NSArray<MKShape<MKGeoJSONObject> *> *)geometry
                       properties:(NSData *)featureProperties
                      identifier:(NSString *)featureIdentifier
{
    self = [super init];
    if (self) {
        _geometry = [geometry copy] ?: @[];
        _properties = [featureProperties copy];
        _identifier = [featureIdentifier copy];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MKGeoJSONFeature: %p %@ %lu shapes%@>",
            self, _identifier ?: @"(no id)", (unsigned long)_geometry.count,
            _properties ? @" with properties" : @""];
}

@end

@implementation MKGeoJSONDecoder

// One geometry object, into the release's own shape for it. The types are RFC 7946's seven and each
// one maps onto the class the release has carried since 3.2.
- (id<MKGeoJSONObject>)charon_geometryOfObject:(NSDictionary *)object error:(NSError **)error
{
    NSString *type = [object objectForKey:@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        if (error) {
            *error = CharonGeoJSONError(@"a GeoJSON geometry has no string type");
        }
        return nil;
    }
    if ([type isEqualToString:@"Point"]) {
        CLLocationCoordinate2D coordinate;
        if (!CharonGeoJSONCoordinate([object objectForKey:@"coordinates"], &coordinate)) {
            if (error) {
                *error = CharonGeoJSONError(@"a Point's coordinates are not a longitude and a latitude");
            }
            return nil;
        }
        // The release's own point annotation, at the release's own projection of the position.
        MKPointAnnotation *point = [[MKPointAnnotation alloc] init];
        point.coordinate = coordinate;
        return point;
    }
    if ([type isEqualToString:@"MultiPoint"]) {
        // The release's own MKMultiPoint CANNOT BE BUILT on this release, and that is measured: its
        // whole surface in the armv7 cache of 6.1.3 is -points, -pointCount, -getCoordinates:range:,
        // -boundingMapRect, -coordinate and -intersectsMapRect: -- no +polylineWithCoordinates:count:
        // and no -initWithMapPoints:count:, so there is no public route to an instance at all. (And
        // the host's own decoder raises NSInvalidArgumentException on a MultiPoint for the same
        // reason on a host build, which is how this was found.)
        //
        // So a MultiPoint is REFUSED, with the reason, rather than handed back as a MKPolyline: an
        // MKPolyline is a different class with a different meaning, and a caller that asked for a
        // MultiPoint would not know it had been given one. The registry row for the MultiPoint case
        // says this, and the host differential does not compare the case -- the host can make one and
        // this device cannot, so the two are not the same question.
        NSArray<NSValue *> *values = CharonGeoJSONPositions([object objectForKey:@"coordinates"], 1, NO);
        if (values.count == 0) {
            if (error) {
                *error = CharonGeoJSONError(@"a MultiPoint's coordinates are not positions");
            }
            return nil;
        }
        if (error) {
            *error = CharonGeoJSONError(@"a MultiPoint cannot be decoded on this release: its MKMultiPoint "
                                        "has no public initialiser at all, measured in the armv7 cache of 6.1.3");
        }
        return nil;
    }
    if ([type isEqualToString:@"LineString"]) {
        NSArray<NSValue *> *values = CharonGeoJSONPositions([object objectForKey:@"coordinates"], 2, NO);
        if (values == nil) {
            if (error) {
                *error = CharonGeoJSONError(@"a LineString's coordinates are not at least two positions");
            }
            return nil;
        }
        NSUInteger count = 0;
        const CLLocationCoordinate2D *coordinates = CharonGeoJSONCoordinates(values, &count);
        return [MKPolyline polylineWithCoordinates:coordinates count:count];
    }
    if ([type isEqualToString:@"MultiLineString"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (id line in [object objectForKey:@"coordinates"]) {
            NSArray<NSValue *> *values = CharonGeoJSONPositions(line, 2, NO);
            if (values == nil) {
                if (error) {
                    *error = CharonGeoJSONError(@"a MultiLineString has a line that is not at least two positions");
                }
                return nil;
            }
            NSUInteger count = 0;
            const CLLocationCoordinate2D *coordinates = CharonGeoJSONCoordinates(values, &count);
            [lines addObject:[MKPolyline polylineWithCoordinates:coordinates count:count]];
        }
        if (lines.count == 0) {
            if (error) {
                *error = CharonGeoJSONError(@"a MultiLineString has no lines");
            }
            return nil;
        }
        // MKMultiPolyline is NOT in the 6.1.3 cache (measured: absent), so this is the class this
        // library carries, not the release's, and a caller is getting one of ours.
        return [[MKMultiPolyline alloc] initWithPolylines:lines];
    }
    if ([type isEqualToString:@"Polygon"]) {
        MKPolygon *polygon = [self charon_polygonOfRings:[object objectForKey:@"coordinates"] error:error];
        return polygon;
    }
    if ([type isEqualToString:@"MultiPolygon"]) {
        NSMutableArray *polygons = [NSMutableArray array];
        for (id rings in [object objectForKey:@"coordinates"]) {
            MKPolygon *polygon = [self charon_polygonOfRings:rings error:error];
            if (polygon == nil) {
                return nil;
            }
            [polygons addObject:polygon];
        }
        if (polygons.count == 0) {
            if (error) {
                *error = CharonGeoJSONError(@"a MultiPolygon has no polygons");
            }
            return nil;
        }
        // As with the MultiLineString: MKMultiPolygon is absent from the 6.1.3 cache, so this is the
        // class this library carries.
        return [[MKMultiPolygon alloc] initWithPolygons:polygons];
    }
    if (error) {
        *error = CharonGeoJSONError([NSString stringWithFormat:@"%@ is not a GeoJSON geometry type this port knows",
                                     type]);
    }
    return nil;
}

// A polygon: the exterior ring and then the interior rings, each a LinearRing of at least four closed
// positions, per RFC 7946 §3.1.6. The release's own MKPolygon takes the interior rings as polygons
// of their own, which is how the release has always carried holes.
- (MKPolygon *)charon_polygonOfRings:(id)rings error:(NSError **)error
{
    if (![rings isKindOfClass:[NSArray class]] || [rings count] == 0) {
        if (error) {
            *error = CharonGeoJSONError(@"a Polygon has no rings");
        }
        return nil;
    }
    NSMutableArray *holes = [NSMutableArray array];
    MKPolygon *exterior = nil;
    NSArray<NSValue *> *exteriorValues = nil;
    NSUInteger exteriorCount = 0;
    NSUInteger ringIndex = 0;
    for (id ring in rings) {
        NSArray<NSValue *> *values = CharonGeoJSONPositions(ring, 4, YES);
        if (values == nil) {
            if (error) {
                *error = CharonGeoJSONError(@"a Polygon ring is not four or more closed positions");
            }
            return nil;
        }
        NSUInteger count = 0;
        const CLLocationCoordinate2D *coordinates = CharonGeoJSONCoordinates(values, &count);
        if (ringIndex == 0) {
            exterior = [MKPolygon polygonWithCoordinates:coordinates count:count];
            exteriorValues = values;
            exteriorCount = count;
        } else {
            [holes addObject:[MKPolygon polygonWithCoordinates:coordinates count:count]];
        }
        ringIndex++;
    }
    if (holes.count == 0) {
        return exterior;
    }
    return [MKPolygon polygonWithCoordinates:CharonGeoJSONCoordinates(exteriorValues, &exteriorCount)
                                       count:exteriorCount
                          interiorPolygons:holes];
}

- (nullable NSArray<id<MKGeoJSONObject>> *)geoJSONObjectsWithData:(NSData *)data
                                            error:(NSError **)errorPtr
{
    if (data.length == 0) {
        if (errorPtr) {
            *errorPtr = CharonGeoJSONError(@"there is no GeoJSON to decode");
        }
        return nil;
    }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (root == nil) {
        if (errorPtr) {
            *errorPtr = CharonGeoJSONError(@"the data is not JSON");
        }
        return nil;
    }
    NSError *inner = nil;
    NSArray *objects = nil;
    if ([root isKindOfClass:[NSDictionary class]]) {
        objects = [self charon_objectsOfRoot:root error:&inner];
    } else if ([root isKindOfClass:[NSArray class]]) {
        NSMutableArray *made = [NSMutableArray array];
        for (id item in root) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                if (errorPtr) {
                    *errorPtr = CharonGeoJSONError(@"an array at the top level holds something that is not a GeoJSON object");
                }
                return nil;
            }
            NSArray *one = [self charon_objectsOfRoot:item error:&inner];
            if (one == nil) {
                if (errorPtr) {
                    *errorPtr = inner;
                }
                return nil;
            }
            [made addObjectsFromArray:one];
        }
        objects = made;
    }
    if (objects == nil) {
        if (errorPtr) {
            *errorPtr = inner ?: CharonGeoJSONError(@"the top level is not a GeoJSON object or an array of them");
        }
        return nil;
    }
    return objects;
}

// One top-level object: a Feature, a FeatureCollection, or a bare geometry -- RFC 7946 §3.
- (NSArray *)charon_objectsOfRoot:(NSDictionary *)root error:(NSError **)error
{
    NSString *type = [root objectForKey:@"type"];
    if (![type isKindOfClass:[NSString class]]) {
        if (error) {
            *error = CharonGeoJSONError(@"a GeoJSON object has no string type");
        }
        return nil;
    }
    if ([type isEqualToString:@"Feature"]) {
        id geometry = [root objectForKey:@"geometry"];
        if (geometry != nil && ![geometry isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = CharonGeoJSONError(@"a Feature's geometry is not an object");
            }
            return nil;
        }
        NSArray<MKShape<MKGeoJSONObject> *> *shapes = @[];
        if (geometry != nil) {
            id<MKGeoJSONObject> one = [self charon_geometryOfObject:geometry error:error];
            if (one == nil) {
                return nil;
            }
            shapes = @[(MKShape<MKGeoJSONObject> *)one];
        }
        id identifier = [root objectForKey:@"id"];
        id properties = [root objectForKey:@"properties"];
        MKGeoJSONFeature *feature = [[MKGeoJSONFeature alloc] initWithGeometry:shapes
                                                                           properties:[properties isKindOfClass:[NSDictionary class]]
                                                                                      ? [NSJSONSerialization dataWithJSONObject:properties options:0 error:NULL]
                                                                                      : nil
                                                                          identifier:[identifier isKindOfClass:[NSString class]]
                                                                                      ? identifier
                                                                                      : (identifier ? [NSString stringWithFormat:@"%@", identifier] : nil)];
        return @[feature];
    }
    if ([type isEqualToString:@"FeatureCollection"]) {
        id features = [root objectForKey:@"features"];
        if (![features isKindOfClass:[NSArray class]]) {
            if (error) {
                *error = CharonGeoJSONError(@"a FeatureCollection has no features array");
            }
            return nil;
        }
        NSMutableArray *made = [NSMutableArray array];
        for (id feature in features) {
            if (![feature isKindOfClass:[NSDictionary class]] ||
                ![[feature objectForKey:@"type"] isEqual:@"Feature"]) {
                if (error) {
                    *error = CharonGeoJSONError(@"a FeatureCollection holds something that is not a Feature");
                }
                return nil;
            }
            NSArray *one = [self charon_objectsOfRoot:feature error:error];
            if (one == nil) {
                return nil;
            }
            [made addObjectsFromArray:one];
        }
        return made;
    }
    // A bare geometry, which RFC 7946 §3 allows and the header's own NSArray<id<MKGeoJSONObject>>
    // is shaped for.
    id<MKGeoJSONObject> one = [self charon_geometryOfObject:root error:error];
    return one ? @[one] : nil;
}

@end

NS_ASSUME_NONNULL_END
