// The map configurations of iOS 16 and the camera's boundary and zoom range of iOS 13: the values
// a modern program sets on a map view to say what the map should show, on a release whose own map
// view has a mapType and a region and nothing else.
//
// A configuration is a value object: it holds what the caller set and answers it back, and
// -isEqual: and -copyWithZone: and the archiving the headers declare all agree with that. What the
// release's own map view can act on, the MKMapView category in MKMapView+Renderers.m acts on
// (elevationStyle, emphasisStyle, showsTraffic and the point of interest filter have no counterpart
// in a map type, and a map type this configuration stands for is set instead).
#import <MapKit/MapKit.h>
#import <MapKit/MKMapConfiguration.h>
#import <MapKit/MKStandardMapConfiguration.h>
#import <MapKit/MKHybridMapConfiguration.h>
#import <MapKit/MKImageryMapConfiguration.h>
#import <MapKit/MKMapCameraBoundary.h>
#import <MapKit/MKMapCameraZoomRange.h>
#import <MapKit/MKPointOfInterestFilter.h>
#import "CharonMapKit.h"

// The header marks -[MKMapConfiguration init] unavailable, on purpose: a configuration is one of
// the three concrete subclasses. The three of them are initialised from it here, which is the one
// place the marking is in the way of the port's own work, and the marking is not the port's to lift.

@implementation MKMapConfiguration

@synthesize elevationStyle = _elevationStyle;

- (instancetype)init
{
    // The header marks this unavailable: a configuration is one of the three concrete subclasses.
    // It is still implemented, because a program that reaches it through the runtime must get an
    // object and not a crash, and because the 16.4 SDK's own MKMapConfiguration is NSObject's base.
    _elevationStyle = MKMapElevationStyleFlat;
    return [super init];
}

// The three concrete subclasses are built from this, which is where the header's marking of -init as
// unavailable is in the way of the port's own work: the marking is Apple's, and lifting it is not
// the port's to do. Charon's own, so it carries no API.
- (instancetype)charon_baseInit
{
    return [super init];
}

- (id)copyWithZone:(NSZone *)zone
{
    MKMapConfiguration *copy = [[[self class] allocWithZone:zone] init];
    copy.elevationStyle = _elevationStyle;
    return copy;
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[MKMapConfiguration class]]) {
        return NO;
    }
    return [other isKindOfClass:[self class]] && ((MKMapConfiguration *)other).elevationStyle == _elevationStyle;
}

- (NSUInteger)hash
{
    return (NSUInteger)_elevationStyle;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:(NSInteger)_elevationStyle forKey:@"MKMapElevationStyle"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self init];
    if (self) {
        _elevationStyle = (MKMapElevationStyle)[coder decodeIntegerForKey:@"MKMapElevationStyle"];
    }
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end

@implementation MKStandardMapConfiguration {
    MKPointOfInterestFilter *_pointOfInterestFilter;
}

@synthesize emphasisStyle = _emphasisStyle;
@synthesize showsTraffic = _showsTraffic;

// A filter is a value: the property is copy, and the getter gives back what the setter was given,
// not the object the caller may go on to change.
- (void)setPointOfInterestFilter:(MKPointOfInterestFilter *)filter
{
    _pointOfInterestFilter = [filter copy];
}

- (MKPointOfInterestFilter *)pointOfInterestFilter
{
    return _pointOfInterestFilter;
}

- (instancetype)init
{
    self = [self charon_baseInit];
    if (self) {
        _emphasisStyle = MKStandardMapEmphasisStyleDefault;
        _showsTraffic = NO;
    }
    return self;
}

- (instancetype)initWithElevationStyle:(MKMapElevationStyle)elevationStyle
{
    self = [self init];
    if (self) {
        self.elevationStyle = elevationStyle;
    }
    return self;
}

- (instancetype)initWithElevationStyle:(MKMapElevationStyle)elevationStyle emphasisStyle:(MKStandardMapEmphasisStyle)emphasisStyle
{
    self = [self init];
    if (self) {
        self.elevationStyle = elevationStyle;
        _emphasisStyle = emphasisStyle;
    }
    return self;
}

- (instancetype)initWithEmphasisStyle:(MKStandardMapEmphasisStyle)emphasisStyle
{
    return [self initWithElevationStyle:MKMapElevationStyleFlat emphasisStyle:emphasisStyle];
}

@end

@implementation MKHybridMapConfiguration {
    MKPointOfInterestFilter *_pointOfInterestFilter;
}

@synthesize showsTraffic = _showsTraffic;

- (void)setPointOfInterestFilter:(MKPointOfInterestFilter *)filter
{
    _pointOfInterestFilter = [filter copy];
}

- (MKPointOfInterestFilter *)pointOfInterestFilter
{
    return _pointOfInterestFilter;
}

- (instancetype)init
{
    self = [self charon_baseInit];
    if (self) {
        _showsTraffic = NO;
    }
    return self;
}

- (instancetype)initWithElevationStyle:(MKMapElevationStyle)elevationStyle
{
    self = [self init];
    if (self) {
        self.elevationStyle = elevationStyle;
    }
    return self;
}

@end

@implementation MKImageryMapConfiguration

- (instancetype)init
{
    return [self charon_baseInit];
}

- (instancetype)initWithElevationStyle:(MKMapElevationStyle)elevationStyle
{
    self = [self init];
    if (self) {
        self.elevationStyle = elevationStyle;
    }
    return self;
}

@end

@implementation MKMapCameraBoundary

@synthesize mapRect = _mapRect;
@synthesize region = _region;

- (instancetype)initWithMapRect:(MKMapRect)mapRect
{
    self = [super init];
    if (self) {
        _mapRect = mapRect;
        _region = MKCoordinateRegionForMapRect(mapRect);
    }
    return self;
}

- (instancetype)initWithCoordinateRegion:(MKCoordinateRegion)region
{
    self = [super init];
    if (self) {
        _region = region;
        _mapRect = [CharonMapKit charon_mapRectForRegion:region];
    }
    return self;
}

// The four numbers of the map rect, written out by name: a map rect is a struct of two points and
// a size, which no archiver on this release knows how to carry whole.
- (instancetype)initWithCoder:(NSCoder *)coder
{
    MKMapRect rect = MKMapRectMake([coder decodeDoubleForKey:@"MKMapRectX"],
                                   [coder decodeDoubleForKey:@"MKMapRectY"],
                                   [coder decodeDoubleForKey:@"MKMapRectWidth"],
                                   [coder decodeDoubleForKey:@"MKMapRectHeight"]);
    return [self initWithMapRect:rect];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_mapRect.origin.x forKey:@"MKMapRectX"];
    [coder encodeDouble:_mapRect.origin.y forKey:@"MKMapRectY"];
    [coder encodeDouble:_mapRect.size.width forKey:@"MKMapRectWidth"];
    [coder encodeDouble:_mapRect.size.height forKey:@"MKMapRectHeight"];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithMapRect:_mapRect];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[MKMapCameraBoundary class]]) {
        return NO;
    }
    return MKMapRectEqualToRect(((MKMapCameraBoundary *)other).mapRect, _mapRect);
}

- (NSUInteger)hash
{
    return (NSUInteger)(long)_mapRect.origin.x ^ (NSUInteger)(long)_mapRect.size.height;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end

@implementation MKMapCameraZoomRange

@synthesize minCenterCoordinateDistance = _minCenterCoordinateDistance;
@synthesize maxCenterCoordinateDistance = _maxCenterCoordinateDistance;

// The header makes this the designated initialiser and returns nil for an empty range. A bound of
// MKMapCameraZoomDefault (-1.0) is not a distance, it is the end of the range that the range does
// not bound, and the getter gives it back exactly as it came in, which is what the constant means.
- (instancetype)initWithMinCenterCoordinateDistance:(CLLocationDistance)minDistance maxCenterCoordinateDistance:(CLLocationDistance)maxDistance
{
    if ((minDistance > 0.0 && maxDistance > 0.0 && minDistance > maxDistance) ||
        (minDistance <= 0.0 && minDistance != MKMapCameraZoomDefault) ||
        (maxDistance <= 0.0 && maxDistance != MKMapCameraZoomDefault)) {
        return nil;
    }
    self = [super init];
    if (self) {
        _minCenterCoordinateDistance = minDistance;
        _maxCenterCoordinateDistance = maxDistance;
    }
    return self;
}

- (instancetype)initWithMinCenterCoordinateDistance:(CLLocationDistance)minDistance
{
    return [self initWithMinCenterCoordinateDistance:minDistance maxCenterCoordinateDistance:MKMapCameraZoomDefault];
}

- (instancetype)initWithMaxCenterCoordinateDistance:(CLLocationDistance)maxDistance
{
    return [self initWithMinCenterCoordinateDistance:MKMapCameraZoomDefault maxCenterCoordinateDistance:maxDistance];
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithMinCenterCoordinateDistance:_minCenterCoordinateDistance
                                                        maxCenterCoordinateDistance:_maxCenterCoordinateDistance];
}

- (BOOL)isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[MKMapCameraZoomRange class]]) {
        return NO;
    }
    MKMapCameraZoomRange *range = other;
    return range.minCenterCoordinateDistance == _minCenterCoordinateDistance &&
           range.maxCenterCoordinateDistance == _maxCenterCoordinateDistance;
}

- (NSUInteger)hash
{
    return (NSUInteger)(long)_minCenterCoordinateDistance ^ (NSUInteger)(long)_maxCenterCoordinateDistance;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_minCenterCoordinateDistance forKey:@"MKMinCenterCoordinateDistance"];
    [coder encodeDouble:_maxCenterCoordinateDistance forKey:@"MKMaxCenterCoordinateDistance"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    CLLocationDistance lowest = [coder decodeDoubleForKey:@"MKMinCenterCoordinateDistance"];
    CLLocationDistance highest = [coder decodeDoubleForKey:@"MKMaxCenterCoordinateDistance"];
    return [self initWithMinCenterCoordinateDistance:lowest maxCenterCoordinateDistance:highest];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
