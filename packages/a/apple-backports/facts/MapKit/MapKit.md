# MapKit on iOS 6: the renderers, the camera, the configurations and the snapshot

iOS 6.1.3 has an `MKMapView` and the whole of the `MKOverlayView` drawing path underneath it. It
has none of what iOS 7 and later put on top: no `MKOverlayRenderer` and no renderer tree, no
overlay levels, no camera, no snapshotter, no map configuration, no marker pin, no cluster, no
annotation view reuse. This is what this port carries, and what it does with what the release
already has.

## The measured floor

`apple.dyld`'s own `first_releases`, walking every held rung of the cache ladder and asking which
release first exports each symbol:

| class | first held release that exports it |
| --- | --- |
| `MKMapView`, `MKAnnotationView`, `MKCircle`, `MKPolygon`, `MKPolyline`, `MKMultiPoint`, `MKOverlayView`, `MKPlacemark` | 3.0 – 3.2 (the release has them) |
| `MKOverlayRenderer`, `MKOverlayPathRenderer`, `MKCircleRenderer`, `MKPolygonRenderer`, `MKPolylineRenderer`, `MKTileOverlay`, `MKTileOverlayRenderer`, `MKMapCamera`, `MKMapSnapshot`, `MKMapSnapshotOptions`, `MKMapSnapshotter`, `MKDistanceFormatter`, `MKScaleView`, `MKGeodesicPolyline` | 7.0 |
| `MKMarkerAnnotationView`, `MKClusterAnnotation` | 11.0 |
| `MKMapConfiguration`, `MKStandardMapConfiguration`, `MKHybridMapConfiguration`, `MKImageryMapConfiguration`, `MKIconStyle`, `MKMapFeatureAnnotation`, `MKMapCameraBoundary`, `MKMapCameraZoomRange`, `MKMultiPolygon`, `MKMultiPolygonRenderer`, `MKMultiPolyline`, `MKMultiPolylineRenderer`, `MKPointOfInterestFilter`, `MKGradientPolylineRenderer` | 16.0 (the 13.0 and 14.0 releases are not held, so 16.0 is the first held rung above them and the SDK header's own 13.0 and 14.0 are the true arrivals) |

Every entry is `minimum: "6.0"`: 6.0 is the port's own floor, and the release has none of these
classes below 7.0, so the whole declared surface of each is carried from 6.0 and from 7.0 on the
release's own class answers. That is why one object file per class, and why the class's later
members (a 14.0 `strokeStart`, a 16.0 `blendMode`) ride along with the class rather than being
split into an object of their own: on the releases where the class is missing, the whole of what
the SDK's header declares on it is what belongs there.

## The renderer is the release's own overlay view

`MKOverlayRenderer` is declared by the SDK 16.4 header as an `NSObject`. It is built here as a
subclass of the release's own `MKOverlayView`, which is `MKOverlayView` at run time and an
`NSObject` in the header. Two reasons, both mechanical:

- the release's `MKMapView` sizes an overlay view and drives it with `canDrawMapRect:zoomScale:`
  and `drawMapRect:zoomScale:inContext:`, so a renderer that is a real overlay view is one the
  release's map view can host and draw without knowing anything new;
- `alpha` is then the view's own alpha, which is what the pixels MapKit draws through the
  renderer are composited at, rather than a number nothing reads.

The 16.4 header hides that superclass, so the objects that build a renderer reach the view half
through the `CharonOverlayView` protocol in `CharonMapKit.h`, and the two initialisers go through
the release's own `-[MKOverlayView initWithOverlay:]` and `-initWithCoder:` because there is no
other way to build one of this class as one of them.

## The transform between map points and the renderer's own points

Apple's renderer is handed a map rect and draws in the overlay's coordinates. Here the renderer is
a view inside a map view, so the two spaces are tied by the overlay's own `boundingMapRect` and the
view's own `bounds`, and the scale is read off the view rather than off the map view's zoom scale
(which the 16.4 header does not even declare) -- the view and the overlay are scaled together, and
the view is the one that can be measured. `pointForMapPoint:`, `mapPointForPoint:`,
`rectForMapRect:` and `mapRectForRect:` are that transform and its inverse, recomputed on every
call, so a stale scale is never drawn with. Where the release exports a projection, it is the
release's own: `MKMapPointForCoordinate`, `MKCoordinateForMapPoint`,
`MKMetersPerMapPointAtLatitude`, `MKMapPointsPerMeterAtLatitude`, `MKCoordinateRegionForMapRect`,
`MKMapRectUnion`, `MKMapRectIntersection`, `MKMapSizeWorld` and `MKMapRectWorld` are all in the
armv7 cache from 3.2 (measured) and are called directly. What MapKit.framework does not export on
this release, and what `CharonMapKit` therefore has, is the map size of a zoom scale, the map rect
of a coordinate region, and the bearing between two coordinates.

## The delegate bridge

This is the part that makes the renderers draw rather than merely exist. The release's map view
asks its delegate for an `MKOverlayView` with `mapView:viewForOverlay:`; a program written since
iOS 7 does not implement that, it implements `mapView:rendererForOverlay:`. So
`-[MKMapView setDelegate:]` puts a `CharonMapKitDelegate` in front of the caller's own object,
that proxy answers the release's two questions out of the program's two, and every other message
goes to the program untouched through `forwardingTargetForSelector:`. `-[MKMapView delegate]`
gives the caller's own object back, so a program that compares its map view's delegate with itself
still finds itself. The release's own implementations are reached through
`class_getInstanceMethod([MKAnnotationView class], ...)`, which is where the property the MKAnnotation
protocol declares is implemented and which `MKMapView` inherits without overriding; this is the one
place in this library that depends on that inheritance, and it is the first thing to re-check if a
future release's `MKMapView` implements `delegate` itself.

## What is honest about a flat map

The release's map view cannot rotate or pitch. `MKMapCamera` therefore stores the heading and the
pitch and derives everything else from the release's own projection: `centerCoordinateDistance`
and the deprecated `altitude` are two names for one number (the eye ratio MapKit's own camera
keeps, 1.5), and `-setCamera:animated:` turns a camera into the region the release's map view can
actually show. `+cameraLookingAtMapItem:forViewSize:allowPitch:` needs a coordinate for the map
item, and iOS 6's `MKMapItem` is a name and an address with no place at all -- the placemark
arrived in iOS 9 -- so where the release has none the camera frames the whole world, which is what
fits in the view, and says so in the registry.

The map configurations are value objects: the elevation style, the emphasis style, the point of
interest filter and showsTraffic are stored, copied, compared and archived, and the
`MKMapView` category does not read most of them, because a map type has no counterpart to them.
`MKMapFeatureAnnotation` is the same: a map feature is something the map itself knows about, and a
release whose map has no features has none for it, so its own parts answer as they are and its
coordinate is the invalid one until a map answers for it.

## The numbers that were read, not chosen

- `MKMapCameraZoomDefault` is `-1.0`, read out of the MapKit image `dyld.extract` took of the
  arm64e dyld shared cache of 18.0: the eight bytes at the address the symbol
  `_MKMapCameraZoomDefault` has there. It is not a distance, it is the end of a zoom range that
  the range does not bound, which is why the one-sided initialisers leave the other end at it and
  the getter gives it back unchanged.
- The `MKPointOfInterestCategory*` strings are **not** in this delivery. Their values have to be
  read out of a real cache, and the arm64e caches this machine holds are stored as a header file
  plus sixty numbered sub-caches, which `tools/cfconst.py` does not read; reading them is the next
  step and is a whole object file of its own (two, by release).

## The checks

- `tests/backports/host/mapkit` compares this port's projection, distance formatter, camera and
  tile-URL arithmetic against macOS's own MapKit, which is the behaviour oracle for all of them.
- The generated call test calls every implemented method on the emulator at 6.1.3, which is the
  only check that touches the parts a host cannot answer for: the drawing (the renderers are asked
  to draw into a bitmap context) and the delegate bridge.
