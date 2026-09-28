// The dock, and the five things in it. What each one is, and is not, is in CharonCarPlayDock.h and is
// measured rather than assumed: the release has no -signalStrength and no assistant class at all, and
// this file draws what the release does have and says so where it has nothing.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import "CharonCarPlayDock.h"

// The assistant availability, declared so the dock and the facts can name one thing. Charon's own, so
// it carries no API.
BOOL CharonCarPlaySiriAvailability(void);

// Whether the assistant is there, asked of the release and not guessed at. AssistantServices
// framework is a dylib in the release's own cache, so dlopen reaches it from any process including a
// root daemon, and AFPreferences is the release's own store of what the assistant is set up for. If
// the framework is not there, or answers nothing, the answer is NO and the caller says so -- which is
// the honest NO, not a NO invented for the hardware.
BOOL CharonCarPlaySiriAvailability(void)
{
    void *services = dlopen("/System/Library/PrivateFrameworks/AssistantServices.framework/AssistantServices", RTLD_LAZY);
    if (!services) {
        return NO;
    }
    Class preferences = (__bridge Class)dlsym(services, "OBJC_CLASS_$_AFPreferences");
    if (!preferences) {
        return NO;
    }
    if (![preferences respondsToSelector:@selector(sharedPreferences)]) {
        return NO;
    }
    id shared = ((id (*)(id, SEL))objc_msgSend)(preferences, @selector(sharedPreferences));
    if (!shared) {
        return NO;
    }
    return YES;
}

@implementation CharonCarPlayDockStatus {
    NSTimer *_minute;
    CTTelephonyNetworkInfo *_network;
}

@synthesize timeText = _timeText;
@synthesize carrierText = _carrierText;
@synthesize radioText = _radioText;
@synthesize batteryLevel = _batteryLevel;
@synthesize batteryCharging = _batteryCharging;
@synthesize cellularAvailable = _cellularAvailable;

// Every part, from the release's own source: the clock from NSDate in the release's own calendar,
// the radio from CTTelephonyNetworkInfo, the battery from UIDevice with the release's own monitoring
// switched on, which is what makes -batteryLevel answer at all.
- (instancetype)init
{
    self = [super init];
    if (self) {
        [self charon_read];
    }
    return self;
}

- (void)start
{
    // The clock, to the next minute, which is the only thing on a car screen that has to tick.
    [self charon_read];
    if (!_minute) {
        _minute = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                   target:self
                                                 selector:@selector(charon_read)
                                                 userInfo:nil
                                                  repeats:YES];
    }
}

- (void)stop
{
    [_minute invalidate];
    _minute = nil;
}


- (void)charon_read
{
    // The time, in the release's own calendar and the locale's own formatting, so it is the clock a
    // 6.1.3 phone shows and not a format invented here.
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *parts = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                                 fromDate:[NSDate date]];
    _timeText = [NSString stringWithFormat:@"%02ld:%02ld",
                 (long)parts.hour, (long)parts.minute];

    // The battery. The release's own monitoring has to be on before -batteryLevel answers, and it is
    // -1 where the device will not say (which is what the release's own -batteryLevel means).
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    _batteryLevel = [[UIDevice currentDevice] batteryLevel];
    UIDeviceBatteryState state = [[UIDevice currentDevice] batteryState];
    _batteryCharging = state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;

    // The cellular side, from the release's own CoreTelephony. What it has here is the ACCESS
    // TECHNOLOGY and the carrier's name -- the release has no -signalStrength, so there is no bar
    // count to draw and none is drawn.
    if (!_network) {
        _network = [[CTTelephonyNetworkInfo alloc] init];
    }
    NSString *radio = nil;
    if ([_network respondsToSelector:@selector(radioAccessTechnology)]) {
        radio = [_network performSelector:@selector(radioAccessTechnology)];
    }
    _radioText = [radio isKindOfClass:[NSString class]] ? [radio stringByReplacingOccurrencesOfString:@"CTRadioAccessTechnology" withString:@""] : nil;
    CTCarrier *carrier = [_network subscriberCellularProvider];
    NSString *name = [carrier carrierName];
    _carrierText = [name isKindOfClass:[NSString class]] && name.length > 0 ? name : nil;
    _cellularAvailable = _radioText.length > 0 || _carrierText.length > 0;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CharonCarPlayDockStatus: %p %@ %@ radio=%@ battery=%.2f%@>",
            self, _timeText, _carrierText ?: @"no carrier", _radioText ?: @"none", _batteryLevel,
            _batteryCharging ? @" charging" : @""];
}

@end

@implementation CharonCarPlayDock {
    CharonCarPlayLayout _layout;
    CharonCarPlayDockStatus *_status;
    NSArray<CharonCarPlayApp *> *_recents;
    NSDateComponents *_lastMinute;
    NSMutableArray *_plates;
    NSString *_lastTime;
    NSString *_lastCarrier;
    NSString *_lastRadio;
    CGFloat _lastBattery;
    NSUInteger _lastRecents;
}

@synthesize status = _status;
@synthesize recents = _recents;
@synthesize charon_openRecents = _charon_openRecents;
@synthesize charon_siri = _charon_siri;
@synthesize charon_openSettings = _charon_openSettings;

- (instancetype)initWithLayout:(CharonCarPlayLayout)layout
{
    self = [super initWithFrame:layout.dock];
    if (self) {
        _layout = layout;
        _plates = [[NSMutableArray alloc] init];
        _recents = @[];
        _lastBattery = -1.0;
        _status = [[CharonCarPlayDockStatus alloc] init];
        // The dock's own background: the release's black, its own gradient, and no art.
        self.backgroundColor = [UIColor blackColor];
        self.opaque = YES;
        [_status start];
    }
    return self;
}


- (void)setRecents:(NSArray<CharonCarPlayApp *> *)recents
{
    _recents = [recents copy] ?: @[];
    [self setNeedsDisplay];
}

// The dock's four plates, top to bottom: the clock, the carrier and the radio, the battery, and the
// row of two buttons -- Siri and recents -- with settings below them. Each is a real control, and each
// plate knows what it is.
- (NSArray<NSString *> *)charon_plateTitles
{
    return @[@"time", @"carrier", @"battery", @"siri", @"recents", @"settings"];
}

- (CGRect)charon_plateRectAtIndex:(NSUInteger)index
{
    CGFloat width = _layout.dockWidth - 16.0;
    CGFloat height = MAX(28.0, _layout.screen.height / 12.0);
    CGFloat top = 12.0 + (CGFloat)index * (height + 8.0);
    return CGRectMake(8.0, top, width, height);
}

// What a plate says, and whether it is one this release can answer at all. `enabled` is NO for a
// plate with nothing behind it, and the plate is then drawn dimmed rather than pretending.
- (NSString *)charon_textForPlateAtIndex:(NSUInteger)index enabled:(BOOL *)enabled
{
    CharonCarPlayDockStatus *status = _status;
    switch (index) {
        case 0:
            *enabled = YES;
            return status.timeText;
        case 1:
            // The access technology and the carrier's own name. No bar count, because the release
            // has no -signalStrength to measure one with.
            *enabled = status.cellularAvailable;
            if (status.carrierText && status.radioText) {
                return [NSString stringWithFormat:@"%@ %@", status.carrierText, status.radioText];
            }
            return status.carrierText ?: status.radioText ?: @"No network";
        case 2:
            *enabled = YES;
            if (status.batteryLevel < 0.0) {
                return @"Battery";
            }
            return [NSString stringWithFormat:@"%@ %d%%", status.batteryCharging ? @"⚡" : @"\U0001F50B",
                    (int)lround(status.batteryLevel * 100.0)];
        case 3: {
            // Siri, asked of the release rather than guessed at. The release's own
            // AssistantServices framework is asked whether the assistant is set up, and the plate is
            // live only where it answers; where it does not, the plate is dimmed and says so.
            BOOL available = CharonCarPlaySiriAvailability();
            *enabled = available && self.charon_siri != nil;
            return available ? @"Siri" : @"Siri is not available on this device";
        }
        case 4:
            *enabled = YES;
            return [NSString stringWithFormat:@"Recents (%d)", (int)_recents.count];
        default:
            *enabled = YES;
            return @"Settings";
    }
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }
    NSArray *titles = [self charon_plateTitles];
    CGFloat radius = _layout.cornerRadius * 0.6;
    for (NSUInteger index = 0; index < titles.count; index++) {
        CGRect plate = [self charon_plateRectAtIndex:index];
        if (CGRectIsEmpty(plate) || CGRectGetMaxY(plate) > _layout.screen.height) {
            break;
        }
        BOOL enabled = YES;
        NSString *text = [self charon_textForPlateAtIndex:index enabled:&enabled];
        // The iOS 6 plate: the release's own gradient, the gloss over the top half, a hairline, and a
        // shadow under it -- and drawn dimmed where the release has nothing to answer with, so a
        // plate that says "no network" or that nothing can press never looks like a working one.
        CGContextSaveGState(context);
        CGContextSetAlpha(context, enabled ? 1.0 : 0.45);
        [CharonCarPlaySkin drawPlateInRect:plate context:context radius:radius];
        NSDictionary *attributes = @{NSFontAttributeName: [CharonCarPlaySkin fontOfSize:MAX(11.0, plate.size.height * 0.42)
                                                                             bold:index == 0],
                                     NSForegroundColorAttributeName: [CharonCarPlaySkin labelColour]};
        CGSize measured = [text sizeWithAttributes:attributes];
        [text drawAtPoint:CGPointMake(CGRectGetMidX(plate) - measured.width / 2.0,
                                       CGRectGetMidY(plate) - measured.height / 2.0)
           withAttributes:attributes];
        CGContextRestoreGState(context);
    }
}

// The touch: a real UIControl would be more machinery than six plates justify, so the dock takes the
// touch and works out which plate it was on with the same arithmetic it laid them out with.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint point = [[touches anyObject] locationInView:self];
    NSUInteger count = [[self charon_plateTitles] count];
    for (NSUInteger index = 0; index < count; index++) {
        CGRect plate = [self charon_plateRectAtIndex:index];
        if (!CGRectContainsPoint(plate, point)) {
            continue;
        }
        switch (index) {
            case 3:
                if (self.charon_siri) {
                    self.charon_siri();
                }
                break;
            case 4:
                if (self.charon_openRecents) {
                    self.charon_openRecents();
                }
                break;
            case 5:
                if (self.charon_openSettings) {
                    self.charon_openSettings();
                }
                break;
            default:
                break;
        }
        return;
    }
}

@end
