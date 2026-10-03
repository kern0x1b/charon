#import "CharonAVMetrics18.h"
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// The part of the metric surface that arrived at iOS 26, one release's worth: AVMetricMediaRendition and
// the three rendition properties each variant-switch class gained. The classes those two categories are
// written on are the port's own, defined in AVFoundationMetrics18.m; a category adds a selector to a
// class and not to its subclasses, which is what these three are - three properties of two classes, not
// three properties of the hierarchy.
//
// The release is measured and not annotated, and here measurement and annotation agree that no held cache
// places any of it: `_OBJC_CLASS_$_AVMetricMediaRendition` and every one of these selectors answer `none`
// over the ladder (tools/symbol-first-release.lua), because the ladder ends at 18.0. So the band is the
// registry row's own introduced version, which is the tree's rule for a name no held release exports.
//
// Open source checked: no candidate. A rendition's stableID and URL are facts about the stream an
// application is playing, not something an open implementation holds.

// AVMetricMediaRendition is a plain container: the stableID the media declares for this rendition and the
// URL it is served from. There is no computation here and none to copy - an instance holds what it was
// given, and nothing in this port constructs one.
@implementation AVMetricMediaRendition

@synthesize stableID = _stableID;
@synthesize URL = _URL;

@end

// THE THREE PROPERTIES ARE STORED AS ASSOCIATED OBJECTS, and that is forced rather than chosen.
//
// A category may not declare instance variables: `instance variables may not be placed in categories` is
// an error, twelve of them for six ivars across two categories, and it is not a warning this port can
// silence. The alternatives were an ivar block on the class in the 18.0 object - which would put 26.0
// storage in an 18.0 band, the thing the one-release rule exists to prevent - or an object association
// per property, which is what the tree already does wherever a category has to carry state
// (AVPlayerMediaSelectionCriteria7's own -charon_preferredLanguages reads one).
//
// The key is the class's own name plus the property's, so the two categories cannot collide and neither
// can collide with anything else on the class.
static id CharonAVMetricRenditionValue(id object, NSString *property)
{
    return objc_getAssociatedObject(object, property.UTF8String);
}

static void CharonAVMetricSetRenditionValue(id object, NSString *property, id value)
{
    objc_setAssociatedObject(object, property.UTF8String, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#define CHARON_AVF_RENDITION_GETTER(CLASS, PROPERTY)                                          \
    - (AVMetricMediaRendition *)PROPERTY                                                       \
    {                                                                                          \
        NSString *key = [NSString stringWithFormat:@"%@.%@", @#CLASS, @#PROPERTY];              \
        return CharonAVMetricRenditionValue(self, key);                                        \
    }

// An instance that nothing has filled reads nil, which is what "If not available, value is nil" means
// for a rendition this port has not been told about. Both sides are the same here: there is no setter,
// the header declares the property readonly, and there is nothing in this port that constructs an
// AVMetricMediaRendition to associate.
@implementation AVMetricPlayerItemVariantSwitchEvent (Renditions26)
CHARON_AVF_RENDITION_GETTER(AVMetricPlayerItemVariantSwitchEvent, videoRendition)
CHARON_AVF_RENDITION_GETTER(AVMetricPlayerItemVariantSwitchEvent, audioRendition)
CHARON_AVF_RENDITION_GETTER(AVMetricPlayerItemVariantSwitchEvent, subtitleRendition)
@end

@implementation AVMetricPlayerItemVariantSwitchStartEvent (Renditions26)
CHARON_AVF_RENDITION_GETTER(AVMetricPlayerItemVariantSwitchStartEvent, videoRendition)
CHARON_AVF_RENDITION_GETTER(AVMetricPlayerItemVariantSwitchStartEvent, audioRendition)
CHARON_AVF_RENDITION_GETTER(AVMetricPlayerItemVariantSwitchStartEvent, subtitleRendition)
@end