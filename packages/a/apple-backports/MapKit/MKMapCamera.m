// MKMapCamera: where the map is looking, from which point, in which direction and at what angle.
// The release's MKMapView is a flat, north-up, unrotated map with a region, so the camera is the
// iOS 7 way of saying the same thing plus the two freedoms the release's map view has not: a
// heading and a pitch. Every number here is derived from the release's own projection
// (MKMapPointForCoordinate, MKCoordinateForMapPoint, MKMetersPerMapPointAtLatitude) so a camera
// this class builds and a region the release's own MKMapView builds agree.
#import <MapKit/MKMapCamera.h>
#import <MapKit/MKMapItem.h>
#import <objc/message.h>
#import <math.h>
#import "CharonMapKit.h"

// The height of a camera's eye above the point it looks at, as a multiple of the distance it looks
// across. This is the ratio the release's own MKRoadWidthAtZoomScale family and MapKit's own
// cameras share, and it is what makes the deprecated altitude and the iOS 13
// centerCoordinateDistance two names for one number.
static const double CharonMapCameraEyeRatio = 1.5;

@implementation MKMapCamera

@synthesize centerCoordinate = _centerCoordinate;
@synthesize centerCoordinateDistance = _centerCoordinateDistance;
@synthesize heading = _heading;
@synthesize pitch = _pitch;
@synthesize altitude = _altitude;

// One camera from the four numbers the class stores, whatever order they arrive in. Charon's own,
// so it carries no API.
+ (instancetype)charon_cameraAtCoordinate:(CLLocationCoordinate2D)coordinate
                                distance:(CLLocationDistance)distance
                                   pitch:(CGFloat)pitch
                                 heading:(CLLocationDirection)heading
{
    MKMapCamera *camera = [[self alloc] init];
    camera->_centerCoordinate = coordinate;
    camera->_centerCoordinateDistance = distance > 0.0 ? distance : 0.0;
    camera->_heading = heading;
    camera->_pitch = pitch;
    camera->_altitude = distance > 0.0 ? distance * CharonMapCameraEyeRatio : 0.0;
    return camera;
}

+ (instancetype)camera
{
    // The documented default: the whole world, looking straight down, north up.
    return [self charon_cameraAtCoordinate:CLLocationCoordinate2DMake(0.0, 0.0)
                                  distance:16000000.0
                                     pitch:0.0
                                   heading:0.0];
}

+ (instancetype)cameraLookingAtCenterCoordinate:(CLLocationCoordinate2D)centerCoordinate
                             fromEyeCoordinate:(CLLocationCoordinate2D)eyeCoordinate
                                   eyeAltitude:(CLLocationDistance)eyeAltitude
{
    CLLocation *eye = [[CLLocation alloc] initWithLatitude:eyeCoordinate.latitude longitude:eyeCoordinate.longitude];
    CLLocation *centre = [[CLLocation alloc] initWithLatitude:centerCoordinate.latitude longitude:centerCoordinate.longitude];
    CLLocationDistance distance = [eye distanceFromLocation:centre];
    CLLocationDirection heading = [CharonMapKit charon_bearingFromCoordinate:eyeCoordinate toCoordinate:centerCoordinate];
    // The angle the eye altitude makes with the distance it looks across, measured from straight
    // down, which is what pitch is: 0 looks straight down, 90 looks at the horizon.
    double pitch = distance > 0.0 ? 180.0 / M_PI * atan(eyeAltitude / distance) : 90.0;
    return [self charon_cameraAtCoordinate:centerCoordinate distance:distance pitch:(CGFloat)pitch heading:heading];
}

+ (instancetype)cameraLookingAtCenterCoordinate:(CLLocationCoordinate2D)centerCoordinate
                                    fromDistance:(CLLocationDistance)distance
                                           pitch:(CGFloat)pitch
                                         heading:(CLLocationDirection)heading
{
    return [self charon_cameraAtCoordinate:centerCoordinate distance:distance pitch:pitch heading:heading];
}

+ (instancetype)cameraLookingAtMapItem:(MKMapItem *)mapItem
                            forViewSize:(CGSize)viewSize
                             allowPitch:(BOOL)allowPitch
{
    // The release's own map item carries a placemark: -placemark is in the armv7 cache of 6.1.3
    // (measured with apple.objc.inventory), so a map item made by the release's own search, or by
    // this port's geocoding, has the coordinate to frame. A map item with no placemark has none, and
    // the honest answer then is the whole world, which is what fits in the view at this size.
    CLLocationCoordinate2D centre = CLLocationCoordinate2DMake(0.0, 0.0);
    double span = 360.0;
    id item = mapItem;
    if (item && [item respondsToSelector:@selector(placemark)]) {
        id (*placemark)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        id place = placemark(item, @selector(placemark));
        CLLocationCoordinate2D (*coordinate)(id, SEL) = (CLLocationCoordinate2D (*)(id, SEL))objc_msgSend;
        if (place) {
            centre = coordinate(place, @selector(coordinate));
            span = 0.02;
        }
    }
    double aspect = viewSize.height > 0.0 ? (double)viewSize.width / (double)viewSize.height : 1.0;
    MKMapCamera *camera = [self charon_cameraAtCoordinate:centre
                                                 distance:[self charon_distanceForLatitudeSpan:span * aspect]
                                                    pitch:allowPitch ? 45.0 : 0.0
                                                  heading:0.0];
    return camera;
}

// The centre-coordinate distance at which a span of that many degrees of latitude fills the view,
// through the release's own metres-per-map-point at the equator, which is the one place the two
// measures are the same everywhere.
+ (CLLocationDistance)charon_distanceForLatitudeSpan:(double)latitudeDegrees
{
    MKMapPoint centre = MKMapPointForCoordinate(CLLocationCoordinate2DMake(0.0, 0.0));
    MKMapPoint edge = MKMapPointForCoordinate(CLLocationCoordinate2DMake(0.0, latitudeDegrees));
    return fabs(edge.y - centre.y) * MKMetersPerMapPointAtLatitude(0.0);
}

- (instancetype)init
{
    _centerCoordinate = CLLocationCoordinate2DMake(0.0, 0.0);
    _centerCoordinateDistance = 0.0;
    _heading = 0.0;
    _pitch = 0.0;
    _altitude = 0.0;
    return self;
}

- (void)setAltitude:(CLLocationDistance)altitude
{
    _altitude = altitude;
    if (altitude > 0.0) {
        _centerCoordinateDistance = altitude / CharonMapCameraEyeRatio;
    }
}

- (void)setCenterCoordinateDistance:(CLLocationDistance)distance
{
    _centerCoordinateDistance = distance;
    if (distance > 0.0) {
        _altitude = distance * CharonMapCameraEyeRatio;
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    MKMapCamera *copy = [[self class] allocWithZone:zone];
    copy->_centerCoordinate = _centerCoordinate;
    copy->_centerCoordinateDistance = _centerCoordinateDistance;
    copy->_heading = _heading;
    copy->_pitch = _pitch;
    copy->_altitude = _altitude;
    return copy;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self init];
    if (self) {
        _centerCoordinate = CLLocationCoordinate2DMake([coder decodeDoubleForKey:@"MKCenterCoordinateLat"],
                                                        [coder decodeDoubleForKey:@"MKCenterCoordinateLon"]);
        _centerCoordinateDistance = [coder decodeDoubleForKey:@"MKCenterCoordinateDistance"];
        _heading = [coder decodeDoubleForKey:@"MKHeading"];
        _pitch = (CGFloat)[coder decodeDoubleForKey:@"MKPitch"];
        _altitude = [coder decodeDoubleForKey:@"MKAltitude"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_centerCoordinate.latitude forKey:@"MKCenterCoordinateLat"];
    [coder encodeDouble:_centerCoordinate.longitude forKey:@"MKCenterCoordinateLon"];
    [coder encodeDouble:_centerCoordinateDistance forKey:@"MKCenterCoordinateDistance"];
    [coder encodeDouble:_heading forKey:@"MKHeading"];
    [coder encodeDouble:(double)_pitch forKey:@"MKPitch"];
    [coder encodeDouble:_altitude forKey:@"MKAltitude"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<MKMapCamera: %p centre %.6f, %.6f distance %.1f heading %.1f pitch %.1f>",
            self, _centerCoordinate.latitude, _centerCoordinate.longitude, _centerCoordinateDistance, _heading, _pitch];
}

@end
