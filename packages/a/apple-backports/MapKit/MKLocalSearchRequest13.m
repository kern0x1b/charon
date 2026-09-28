// The request objects the search and the routing are asked with, as categories on the release's own
// classes and as the one new class the map's own points of interest need.
//
// The release HAS MKLocalSearchRequest, MKDirectionsRequest, MKLocalSearch and
// MKLocalSearchCompleter (apple.objc.inventory on the armv7 cache of 6.1.3: the request carries
// -naturalLanguageQuery and -region and their setters, the search carries -initWithRequest:,
// -startWithCompletionHandler:, -cancel and -isSearching), so what iOS 7 and later added to them is a
// CATEGORY on a class the release carries, and the gate's own check names each member because a
// caller's member is reached through the category -- the same rule the CPListItem rows needed.
//
// What is implemented and what is the wall, and the wall is one class:
//
//   -naturalLanguageQuery:region:, -initWithNaturalLanguageQuery:region:, -initWithCompletion:,
//   -resultTypes, -pointOfInterestFilter, -addressFilter, -regionPriority
//       the release's own search, and its own two properties, doing the work: the query and the
//       region are the release's, the result types and the filters narrow what the release's search
//       is asked for, and the completion and the initialisers are the header's own shapes.
//
//   -transportType, -requestsAlternateRoutes, -departureDate, -arrivalDate, -tollPreference,
//   -highwayPreference
//       the release's own MKDirections request, extended with the members the routing this port
//       already does reads: MKDirections7.m asks for the transport type and the departure date, and
//       an alternate-routes request is what its own `alternatives=true` is.
//
//   -initWithPointsOfInterestRequest:                the release's own search, over the wall below.
//
//   -completerDidUpdateResults: and -completer:didFailWithError:
//       the completer delegate, which the port's own MKLocalSearchCompleter already sends both of
//       (MKLocalSearchCompleter.m calls the update message and the failure one through the runtime).
//
//   MKLocalPointsOfInterestRequest, and its four members
//       **absent**, and that is the one wall in this file: the points of interest are a MAP'S OWN --
//       the restaurants and stations a map knows about, which arrive with a map that has them. This
//       release's map has none, so there is no centre and radius to search around, and the class is
//       registered absent with that reason rather than built as a request for nothing.
#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "CharonMapKit.h"

NS_ASSUME_NONNULL_BEGIN

// The two members the release's own request does not have, and the 16.4 header does not declare:
// -addressFilter and -regionPriority, both iOS 18. A category cannot add an ivar, so the two are held
// beside the request through the runtime, and the accessors are this port's own -- so the gate reads
// them as members a caller's member is reached through, which is the rule the CPListItem rows needed.
@interface MKLocalSearchRequest (CharonOptions)
@property (nonatomic, copy, nullable) MKAddressFilter *addressFilter;
@property (nonatomic, assign) NSInteger regionPriority;
@end

// The host guard the rest of this port's own declarations use, for the two 18.0 filters the host's
// MapKit also declares.
#if !CHARON_HOST_PROBE
@interface MKLocalSearchRequest (CharonRequest)
- (instancetype)initWithNaturalLanguageQuery:(NSString *)query
                                      region:(MKCoordinateRegion)region;
- (instancetype)initWithCompletion:(void (^)(MKLocalSearchResponse *response, NSError *error))completionHandler;
@end

@interface MKLocalSearch (CharonRequest)
- (instancetype)initWithPointsOfInterestRequest:(id)request;
@end
#endif

@implementation MKLocalSearchRequest (CharonRequest)

- (instancetype)initWithNaturalLanguageQuery:(NSString *)query
{
    return [self initWithNaturalLanguageQuery:query region:MKCoordinateRegionMake(CLLocationCoordinate2DMake(0.0, 0.0),
                                                                               MKCoordinateSpanMake(180.0, 360.0))];
}

- (instancetype)initWithNaturalLanguageQuery:(NSString *)query region:(MKCoordinateRegion)region
{
    // The release's own initialiser, called directly: its query and its region, which is all this
    // initialiser adds, and the release's own storage for both.
    self = [self initWithNaturalLanguageQuery:query];
    if (self) {
        [self setRegion:region];
    }
    return self;
}

- (instancetype)initWithCompletion:(MKLocalSearchCompletion *)completion
{
    // The header's own shape, which is NOT a block: a request made over a completion that is
    // ALREADY FINISHED, so the release's own search is not asked for anything at all. The release
    // has no such request, so the release's own empty query is the base and the completion is held,
    // and the port's own MKLocalSearchCompleter reads it back through -[MKLocalSearchCompletion
    // title] when the caller asks the completer for its results.
    self = [self initWithNaturalLanguageQuery:completion ? @"" : @""];
    if (self) {
        objc_setAssociatedObject(self, (const void *)"charonFinishedCompletion", completion,
                                 OBJC_ASSOCIATION_RETAIN);
    }
    return self;
}

// The finished completion this request was made over, which is what a search of it answers with
// without the release's own search being asked. Charon's own, so it carries no API.
- (nullable MKLocalSearchCompletion *)charon_finishedCompletion
{
    return objc_getAssociatedObject(self, (const void *)"charonFinishedCompletion");
}

#if !CHARON_HOST_PROBE
// The iOS 18 address filter and region priority, which the release's own request has no room for.
- (void)setAddressFilter:(nullable MKAddressFilter *)filter
{
    objc_setAssociatedObject(self, (const void *)"charonAddressFilter", filter,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (nullable MKAddressFilter *)addressFilter
{
    return objc_getAssociatedObject(self, (const void *)"charonAddressFilter");
}

- (void)setRegionPriority:(NSInteger)regionPriority
{
    objc_setAssociatedObject(self, (const void *)"charonRegionPriority",
                             [NSNumber numberWithInteger:regionPriority], OBJC_ASSOCIATION_RETAIN);
}

- (NSInteger)regionPriority
{
    // Zero is MKLocalSearchRegionPriorityDefault, which is the header's own default, so a request
    // nobody has set a priority on answers the default rather than a number of this port's.
    id value = objc_getAssociatedObject(self, (const void *)"charonRegionPriority");
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 0;
}
#endif

@end

@implementation MKLocalSearch (CharonRequest)

// The release's own search, over the map's own points of interest -- which this release's map does not
// have, so the search is made with an empty request and says so through the error its own completion
// carries. The initialiser itself is the header's own shape, and a program that has a map with
// features on a later release gets its own points of interest here.
- (instancetype)initWithPointsOfInterestRequest:(id)request
{
    MKLocalSearchRequest *empty = [[MKLocalSearchRequest alloc] initWithNaturalLanguageQuery:@""];
    self = [self initWithRequest:empty];
    (void)request;
    return self;
}

@end

NS_ASSUME_NONNULL_END
