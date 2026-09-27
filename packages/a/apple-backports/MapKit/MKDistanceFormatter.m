// MKDistanceFormatter and MKScaleView.
//
// The distance formatter is the length of a distance in the measure of the reader's locale, in
// the style the reader asked for, and the reader's own locale decides the measure when the caller
// did not name one (MKDistanceFormatterUnitsDefault): the imperial measure for the locales that
// use it and the metric measure for the rest. Its two ways are exact opposites: what one string
// from a distance parses back to that distance, and what a string it cannot parse answers, which
// is the negative number the header documents.
//
// The scale view is the bar in the corner of a map that says how long a piece of the map is. It is
// drawn from the release's own projection: a round number of metres that fits the width the
// legend was given, and then that many metres' worth of the overlay's own map points, which is the
// bar's own length.
#import <MapKit/MapKit.h>
#import <MapKit/MKDistanceFormatter.h>
#import <MapKit/MKScaleView.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import "CharonMapKit.h"

@implementation MKDistanceFormatter {
    MKDistanceFormatterUnits _units;
    MKDistanceFormatterUnitStyle _unitStyle;
    NSLocale *_locale;
}

@synthesize units = _units;
@synthesize unitStyle = _unitStyle;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _units = MKDistanceFormatterUnitsDefault;
        _unitStyle = MKDistanceFormatterUnitStyleDefault;
        _locale = nil;
    }
    return self;
}

- (NSLocale *)locale
{
    return _locale ?: [NSLocale currentLocale];
}

- (void)setLocale:(NSLocale *)locale
{
    _locale = locale;
}

- (MKDistanceFormatterUnits)charon_resolvedUnits
{
    if (_units != MKDistanceFormatterUnitsDefault) {
        return _units;
    }
    // The default measure of the locale, which is the imperial one where the locale uses it.
    // The locale's own measurement system, "Metric" or "UCS", which is the key the header's own
    // comment points at: the default measure of a locale is not the same as whether it uses the
    // metric system for everything.
    NSString *measure = [[self locale] objectForKey:@"NSLocaleMeasurementSystem"];
    return [measure isEqualToString:@"UCS"] ? MKDistanceFormatterUnitsImperial : MKDistanceFormatterUnitsMetric;
}

- (NSString *)stringFromDistance:(CLLocationDistance)distance
{
    double metres = fabs((double)distance);
    BOOL metric = [self charon_resolvedUnits] == MKDistanceFormatterUnitsMetric;
    BOOL yards = [self charon_resolvedUnits] == MKDistanceFormatterUnitsImperialWithYards;
    double value;
    NSString *fullName, *pluralName, *shortName;
    if (metric) {
        if (metres < 1000.0) {
            value = metres;
            fullName = @"metre"; pluralName = @"metres"; shortName = @"m";
        } else {
            value = metres / 1000.0;
            fullName = @"kilometre"; pluralName = @"kilometres"; shortName = @"km";
        }
        NSUInteger count = (NSUInteger)llround(value);
        NSString *full, *abbreviated;
        if (metres < 1000.0) {
            full = [NSString stringWithFormat:@"%.0f %@", value, count == 1 ? fullName : pluralName];
            abbreviated = [NSString stringWithFormat:@"%.0f %@", value, shortName];
        } else {
            // A tenth of a kilometre is ten metres, and that is the finest a kilometre is written.
            full = [NSString stringWithFormat:@"%.1f %@", value, count == 1 ? fullName : pluralName];
            abbreviated = [NSString stringWithFormat:@"%.1f %@", value, shortName];
        }
        if (_unitStyle == MKDistanceFormatterUnitStyleFull) {
            return full;
        }
        if (_unitStyle == MKDistanceFormatterUnitStyleAbbreviated) {
            return abbreviated;
        }
        return abbreviated;
    }
    // The imperial measure: a mile over ten is written in whole miles, a mile under ten with one
    // decimal, and anything under a tenth of a mile in feet (or in yards, when the caller asked for
    // the measure that has them), which is the rule MKDistanceFormatter documents.
    double miles = metres / 1609.344;
    if (miles < 0.1) {
        if (yards) {
            value = metres / 0.9144;
            fullName = @"yard"; pluralName = @"yards"; shortName = @"yd";
        } else {
            value = metres / 0.3048;
            fullName = @"foot"; pluralName = @"feet"; shortName = @"ft";
        }
    } else {
        value = miles;
        fullName = @"mile"; pluralName = @"miles"; shortName = @"mi";
    }
    NSUInteger count = (NSUInteger)llround(value);
    NSString *full, *abbreviated;
    if (miles >= 10.0) {
        full = [NSString stringWithFormat:@"%.0f %@", value, count == 1 ? fullName : pluralName];
        abbreviated = full;
    } else {
        full = [NSString stringWithFormat:@"%.1f %@", value, count == 1 ? fullName : pluralName];
        abbreviated = full;
    }
    if (_unitStyle == MKDistanceFormatterUnitStyleFull) {
        return full;
    }
    if (_unitStyle == MKDistanceFormatterUnitStyleAbbreviated) {
        return abbreviated;
    }
    return abbreviated;
}

- (CLLocationDistance)distanceFromString:(NSString *)distance
{
    NSString *text = [distance stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return -1.0;
    }
    // The number at the front, then whatever unit word the reader wrote: the full and the
    // abbreviated spellings of both measures, and a bare number is metres.
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double value = 0.0;
    if (![scanner scanDouble:&value]) {
        return -1.0;
    }
    NSString *unit = [[text substringFromIndex:scanner.scanLocation]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    unit = [unit lowercaseString];
    if (unit.length == 0) {
        return (CLLocationDistance)value;
    }
    if ([unit hasPrefix:@"kilo"] || [unit isEqualToString:@"km"] || [unit isEqualToString:@"kilometre"] ||
        [unit isEqualToString:@"kilometres"] || [unit isEqualToString:@"kilometer"] || [unit isEqualToString:@"kilometers"]) {
        return (CLLocationDistance)value * 1000.0;
    }
    if ([unit hasPrefix:@"mi"] || [unit isEqualToString:@"mile"] || [unit isEqualToString:@"miles"]) {
        return (CLLocationDistance)value * 1609.344;
    }
    if ([unit hasPrefix:@"yd"] || [unit hasPrefix:@"yard"]) {
        return (CLLocationDistance)value * 0.9144;
    }
    if ([unit hasPrefix:@"f"] || [unit hasPrefix:@"foot"]) {
        return (CLLocationDistance)value * 0.3048;
    }
    if ([unit hasPrefix:@"m"]) {
        return (CLLocationDistance)value;
    }
    return -1.0;
}

@end

@implementation MKScaleView {
    MKMapView *_mapView;
    MKFeatureVisibility _scaleVisibility;
    MKScaleViewAlignment _legendAlignment;
    UILabel *_legend;
    UIView *_bar;
}

@synthesize scaleVisibility = _scaleVisibility;
@synthesize legendAlignment = _legendAlignment;

+ (instancetype)scaleViewWithMapView:(MKMapView *)mapView
{
    MKScaleView *scale = [[self alloc] initWithFrame:CGRectMake(0.0, 0.0, 120.0, 24.0)];
    if (scale) {
        scale->_mapView = mapView;
        [scale charon_build];
    }
    return scale;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _scaleVisibility = MKFeatureVisibilityAdaptive;
        _legendAlignment = MKScaleViewAlignmentTrailing;
        [self charon_build];
    }
    return self;
}

- (MKMapView *)mapView
{
    return _mapView;
}

- (void)setMapView:(MKMapView *)mapView
{
    _mapView = mapView;
    [self charon_update];
}

- (void)charon_build
{
    self.backgroundColor = [UIColor clearColor];
    _legend = [[UILabel alloc] initWithFrame:CGRectZero];
    _legend.font = [UIFont systemFontOfSize:10.0];
    _legend.textColor = [UIColor blackColor];
    _legend.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    _legend.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_legend];
    _bar = [[UIView alloc] initWithFrame:CGRectZero];
    _bar.backgroundColor = [UIColor blackColor];
    [self addSubview:_bar];
    [self charon_update];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self charon_update];
}

// The bar: a round number of metres that fits the width of the view, and then the map points that
// many metres stand for, which is the bar's own length. Charon's own, so it carries no API.
- (void)charon_update
{
    MKMapView *mapView = _mapView;
    CGRect box = self.bounds;
    if (!mapView || _scaleVisibility == MKFeatureVisibilityHidden || CGRectIsEmpty(box)) {
        _bar.hidden = YES;
        _legend.hidden = YES;
        return;
    }
    // The map view's own scale, out of the two things its 16.4 header declares: the visible map rect
    // is so many map points across, and the view is so many points across.
    MKMapRect visible = mapView.visibleMapRect;
    double pointsWide = 0.0;
    if (mapView.bounds.size.width > 0.0 && visible.size.width > 0.0) {
        pointsWide = visible.size.width * (double)box.size.width / (double)mapView.bounds.size.width;
    }
    double metresWide = pointsWide * MKMetersPerMapPointAtLatitude(mapView.centerCoordinate.latitude);
    if (!(metresWide > 0.0)) {
        _bar.hidden = YES;
        _legend.hidden = YES;
        return;
    }
    // The largest 1, 2 or 5 times a power of ten of metres that leaves room for the legend above.
    double target = metresWide / 2.5;
    double scale = pow(10.0, floor(log10(target)));
    double multiple = 1.0;
    for (double step = 1.0; step <= 5.0; step *= 2.0) {
        if (step * scale <= target) {
            multiple = step;
        }
    }
    double metres = multiple * scale;
    NSString *text;
    if (metres >= 1000.0) {
        text = [NSString stringWithFormat:@"%.0f km", metres / 1000.0];
    } else {
        text = [NSString stringWithFormat:@"%.0f m", metres];
    }
    double pointsPerMapPoint = metres / MKMetersPerMapPointAtLatitude(mapView.centerCoordinate.latitude);
    double barPoints = pointsPerMapPoint > 0.0 ? metres / pointsPerMapPoint : 0.0;
    if (pointsWide > 0.0 && visible.size.width > 0.0) {
        barPoints = barPoints * (double)box.size.width / (double)mapView.bounds.size.width * (double)mapView.bounds.size.width / (double)box.size.width;
    }
    CGFloat barHeight = 2.0;
    CGFloat barY = CGRectGetHeight(box) - barHeight - 2.0;
    CGFloat barX = CGRectGetMinX(box) + 2.0;
    _bar.hidden = NO;
    _bar.frame = CGRectMake(barX, barY, (CGFloat)barPoints, barHeight);
    _legend.hidden = NO;
    _legend.text = text;
    _legend.frame = CGRectMake(barX, barY - 14.0, (CGFloat)barPoints, 14.0);
}

@end
