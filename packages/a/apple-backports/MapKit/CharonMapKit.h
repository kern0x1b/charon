// The few pieces of MapKit's arithmetic the release's own C API does not export, in one place, so
// the objects that use them agree with each other to the last bit.
//
// What the release does export is used directly wherever it has it: MKMapPointForCoordinate,
// MKCoordinateForMapPoint, MKMetersPerMapPointAtLatitude, MKMapPointsPerMeterAtLatitude,
// MKCoordinateRegionForMapRect, MKMapRectUnion, MKMapRectIntersection, MKMapSizeWorld and
// MKMapRectWorld are all in the armv7 dyld shared cache of 3.2 and later, so the projection this
// port draws with is the release's own projection and not a copy of it. What is left here is the
// map size of a zoom scale, the map rect of a coordinate region, and the bearing between two
// coordinates, none of which MapKit.framework exports on this release.
//
// Everything here is Charon's own and carries no API: the members are prefixed charon_ because
// apple/backports.lua's added_members() reads any other Objective-C member as an API the package
// carries, and the build's registry check then wants an entry for it.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <MapKit/MKGeometry.h>
#import <MapKit/MKOverlayRenderer.h>
#import <MapKit/MKOverlayPathRenderer.h>
#import <MapKit/MKMultiPoint.h>
#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CharonMapKit : NSObject

// The map size the whole world has at a zoom scale, and the zoom scale a map size is: the world is
// MKMapSizeWorld points square at scale 1 and half that at scale 2, which is what MKZoomScale's own
// documentation says ("1 screen point = 1 MKMapPoint" at 1, "2 MKMapPoints" at 0.5).
+ (MKMapSize)charon_mapSizeAtZoomScale:(MKZoomScale)zoomScale;
+ (MKZoomScale)charon_zoomScaleForMapSize:(MKMapSize)mapSize;

// The distance a map point stands for at a zoom scale, the number a camera's altitude, a line
// width and a scale bar are all built from, through the release's own
// MKMetersPerMapPointAtLatitude at the centre of the map rect it is asked about.
+ (CLLocationDistance)charon_metersPerMapPointAtZoomScale:(MKZoomScale)zoomScale forMapRect:(MKMapRect)mapRect;

// The initial bearing from one coordinate to another, in degrees clockwise from north. Apple's own
// MKMapCamera answers it the same way for -cameraLookingAtCenterCoordinate:fromEyeCoordinate:
//eyeAltitude:, and there is no release function for it.
+ (CLLocationDirection)charon_bearingFromCoordinate:(CLLocationCoordinate2D)from toCoordinate:(CLLocationCoordinate2D)to;

// The map rect of a coordinate region: the inverse of the release's own
// MKCoordinateRegionForMapRect, which is how the two are kept answering each other exactly.
+ (MKMapRect)charon_mapRectForRegion:(MKCoordinateRegion)region;

@end

// The two path renderers' own hooks, which the objects above them answer: how wide the line is at a
// zoom scale, and where the shape is drawn. Declared and not implemented here, so the objects that
// share them can call them across the files that define them.
// The release's own way of reading a shape's points out. -getCoordinates:range: is on MKMultiPoint
// in the armv7 cache of 6.1.3 (measured by selector string) and the SDK's MKMultiPoint.h is where
// it is declared; the 16.4 header has no `coordinates` property, so this is the one spelling there
// is. Declared and not implemented: the class and the method are the release's.
@interface MKMultiPoint (CharonPoints)
- (void)getCoordinates:(CLLocationCoordinate2D *)coords range:(NSRange)range;
@end

@interface MKOverlayRenderer ()
// The release's MKOverlayView behind the renderer, and the overlay the renderer draws: the 16.4
// header declares both read-only, and the renderer has to answer them itself, so this is where the
// readwrite spellings live for every object that needs them.
@property (nonatomic, readwrite) id <MKOverlay> overlay;
@end

@interface MKOverlayPathRenderer (CharonDrawing)
- (CGFloat)charon_lineWidthAtZoomScale:(MKZoomScale)zoomScale;
@end

@interface MKPolylineRenderer (CharonDrawing)
- (CGFloat)charon_lineWidthAtZoomScale:(MKZoomScale)zoomScale;
@end

// A renderer is a UIView at run time -- it is the release's own MKOverlayView -- while the 16.4
// header says it is an NSObject. This is the view half of it, so the objects that build one can
// size it and fill it.
@protocol CharonOverlayView <NSObject>
- (instancetype)initWithFrame:(CGRect)frame;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)setFrame:(CGRect)frame;
- (void)setBounds:(CGRect)bounds;
@property (nonatomic) CGRect bounds;
- (void)setBackgroundColor:(UIColor *)color;
- (void)setOpaque:(BOOL)opaque;
- (CGFloat)alpha;
- (void)setAlpha:(CGFloat)alpha;
- (void)setUserInteractionEnabled:(BOOL)enabled;
- (void)setAutoresizingMask:(NSUInteger)mask;
- (void)removeFromSuperview;
- (void)setNeedsDisplay;
- (void)setNeedsDisplayInRect:(CGRect)rect;
@property (nonatomic, readonly) CALayer *layer;
@end

@interface MKOverlayRenderer (CharonDrawing)
- (void)charon_drawInContext:(CGContextRef)context zoomScale:(MKZoomScale)zoomScale mapRect:(MKMapRect)mapRect;
- (MKZoomScale)charon_zoomScale;
@end

NS_ASSUME_NONNULL_END
