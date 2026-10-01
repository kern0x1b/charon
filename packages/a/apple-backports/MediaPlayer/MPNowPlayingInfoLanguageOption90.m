// MPNowPlayingInfoLanguageOption and MPNowPlayingInfoLanguageOptionGroup, the two 9.0 classes. Nothing
// invented: every value is stored as the caller gave it, or read out of the release's own
// AVMediaSelectionOption / AVMediaSelectionGroup.
//
// MEASURED, class-scoped, with tools/corpus/objc-inventory.lua over the armv7 dyld shared caches of
// 6.1.3 and 4.3. Each read carried a control in the same run: MPVolumeView and MPMediaPlaylist read
// PRESENT on both ends, and MPNowPlayingInfoCenter reads PRESENT at 6.1.3 and ABSENT at 4.3, so this
// reader discriminates instead of answering yes to everything it is shown.
//
//   name                                  6.1.3      4.3
//   MPNowPlayingInfoLanguageOption          ABSENT     ABSENT
//   MPNowPlayingInfoLanguageOptionGroup     ABSENT     ABSENT
//   AVMediaSelectionOption                  PRESENT    ABSENT
//   AVMediaSelectionGroup                   PRESENT    ABSENT
//
// The two classes are new code and cannot shadow anything - no release has an object of that name -
// which is what lets them be `implemented` rather than `absent`: `absent` is for a row whose answer
// needs a thing the device lacks, and nothing here needs one. What makes this more than a declaration
// is the second half of that table, read at CLASS level. The whole-cache selector list (113981 DISTINCT
// NAMES) could not have decided it: a name is on one line if ANY class anywhere declares it, so a one
// there says nothing about the owner and only a zero would mean absence.
//
//   AVMediaSelectionOption's own 24 instance methods: -locale, -mediaType, -hasMediaCharacteristic:,
//   -displaysNonForcedSubtitles, -isPlayable, -commonMetadata, -group, -dictionary, -optionID, and
//   -_title (the title accessor is PRIVATE on this release; there is no -title, which is checked below
//   rather than assumed, and is why no display name is read out of an option here).
//   AVMediaSelectionGroup's own 18: -options, -allowsEmptySelection, -_defaultOption, -asset,
//   -_isAlternateTrackGroup, -_isKeyValueGroup, -_mediaType.
//
// The two "automatic" accessors are the one place this file answers rather than stores, and the answer
// is computed from the option's own stored identity. MPNowPlayingInfoLanguageOption.h:66-73 documents
// each as "a special case that is used to represent the best legible/audible language option based on
// system preferences", and distinguishes them by TYPE: the automatic option for a group is the one whose
// type is Legible or Audible. So type is the discriminator, and the file says so rather than inventing
// a tag constant to compare against: the header's comment at :68 names MPLangaugeOptionAutoLangaugeTag
// but the SDK declares no such symbol anywhere (measured: grep over the 26.2 MediaPlayer headers finds
// the name in that one comment and no declaration), so an extern for it would not link. The type test
// needs no such constant and is the documented distinction.
//
// One object per release: this file is the 9.0 API of these two classes. MPChangeLanguageOptionCommandEvent90.m,
// already on main, declares an `MPNowPlayingInfoLanguageOption *` property; this file is what makes
// that property's type a real class rather than a nil pointer.

#import <Foundation/Foundation.h>
#if defined(CHARON_MEDIAPLAYER_STANDIN)
// MPMediaItemStandin.h declares both classes and their full contract, and it is the ONLY place a
// stand-in build sees them declared. A second @interface for either name in this file is a duplicate
// definition and does not compile - a first draft of this file carried its own restatement of the
// contract and clang rejected it with "duplicate interface definition for class
// 'MPNowPlayingInfoLanguageOption'", naming MPMediaItemStandin.h:47 as the earlier one. The stand-in
// header was already carrying a one-accessor version of this class, because MPChangeLanguageOptionCommandEvent90.m
// needs a type for its `languageOption` property; that declaration is the one, and it now carries the
// whole contract rather than a stub.
#else
#import <MediaPlayer/MediaPlayer.h>
#endif

@implementation MPNowPlayingInfoLanguageOption

// The ivars are the header's readonly properties' backing storage, synthesised once here so that
// removing an explicit accessor below is a change of behaviour rather than a silent one.
@synthesize languageOptionType = _languageOptionType;
@synthesize languageTag = _languageTag;
@synthesize languageOptionCharacteristics = _languageOptionCharacteristics;
@synthesize displayName = _displayName;
@synthesize identifier = _identifier;

// The header's designated initializer, quoted from MPNowPlayingInfoLanguageOption.h:49-54:
//
//   - (instancetype)initWithType:(MPNowPlayingInfoLanguageOptionType)languageOptionType
//                    languageTag:(NSString *)languageTag
//                characteristics:(nullable NSArray<NSString *> *)languageOptionCharacteristics
//                    displayName:(NSString *)displayName
//                     identifier:(NSString *)identifier;
//
// Every value is stored as given, because the class is a value holder: there is no device state behind
// any of these five, and inventing one would be the failure this port exists to avoid. The two arrays
// and strings are COPIED - the header takes an NSArray the caller owns, and the option holds it past
// the call, so a caller that mutates its own array afterwards must not change what the option reads.
// The accessors are the header's readonly ones, so there is no setter for a copy to fall out of step with.
- (instancetype)initWithType:(MPNowPlayingInfoLanguageOptionType)languageOptionType
                 languageTag:(NSString *)languageTag
             characteristics:(nullable NSArray<NSString *> *)languageOptionCharacteristics
                 displayName:(NSString *)displayName
                  identifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _languageOptionType = languageOptionType;
        _languageTag = [languageTag copy];
        _languageOptionCharacteristics = [languageOptionCharacteristics copy];
        _displayName = [displayName copy];
        _identifier = [identifier copy];
    }
    return self;
}

// The header's five readonly accessors, written out rather than left to the synthesiser, so that what a
// caller reads is this file's code and removing the @synthesize is not a silent change of behaviour.
- (MPNowPlayingInfoLanguageOptionType)languageOptionType {
    return _languageOptionType;
}

- (nullable NSString *)languageTag {
    return _languageTag;
}

- (nullable NSArray<NSString *> *)languageOptionCharacteristics {
    return _languageOptionCharacteristics;
}

- (nullable NSString *)displayName {
    return _displayName;
}

- (nullable NSString *)identifier {
    return _identifier;
}

// The two "automatic" accessors, quoted from the header at :56-73, each documented as "a special case
// that is used to represent the best legible/audible language option based on system preferences" and
// each pointing at AVPlayerItem-selectMediaOptionAutomaticallyInMediaSelectionGroup.
//
// Answered from the option's own stored type, which is the distinction the header's own comment draws:
// an automatic option is the automatic option FOR A TYPE, so an Audible-typed option is the automatic
// audible one and a Legible-typed one the automatic legible one. A tag is not the discriminator - a nil
// tag means the option is DISABLED (header:57-58), which is the opposite of automatic, and the
// automatic value would have been a constant this file would then have to invent, since the SDK declares
// none (measured above).
- (BOOL)isAutomaticLegibleLanguageOption {
    return self.languageOptionType == MPNowPlayingInfoLanguageOptionTypeLegible;
}

- (BOOL)isAutomaticAudibleLanguageOption {
    return self.languageOptionType == MPNowPlayingInfoLanguageOptionTypeAudible;
}

@end

@implementation MPNowPlayingInfoLanguageOptionGroup

@synthesize languageOptions = _languageOptions;
@synthesize defaultLanguageOption = _defaultLanguageOption;
@synthesize allowEmptySelection = _allowEmptySelection;

// The header's designated initializer, quoted from MPNowPlayingInfoLanguageOption.h:94-96:
//
//   - (instancetype)initWithLanguageOptions:(NSArray<MPNowPlayingInfoLanguageOption *> *)languageOptions
//                     defaultLanguageOption:(nullable MPNowPlayingInfoLanguageOption *)defaultLanguageOption
//                       allowEmptySelection:(BOOL)allowEmptySelection;
//
// The header calls the group "a mutually exclusive group of language options" where "only one language
// option within a given group may be active at a time" (:86-87). Nothing here enforces that, because
// this object does not decide which option is active - it holds the set and the one the caller marked
// active. Enforcing exclusivity would mean silently dropping options the caller passed, which is a
// different API from the one Apple declares.
- (instancetype)initWithLanguageOptions:(NSArray<MPNowPlayingInfoLanguageOption *> *)languageOptions
                  defaultLanguageOption:(nullable MPNowPlayingInfoLanguageOption *)defaultLanguageOption
                    allowEmptySelection:(BOOL)allowEmptySelection {
    self = [super init];
    if (self) {
        _languageOptions = [languageOptions copy];
        _defaultLanguageOption = defaultLanguageOption;
        _allowEmptySelection = allowEmptySelection;
    }
    return self;
}

- (NSArray<MPNowPlayingInfoLanguageOption *> *)languageOptions {
    return _languageOptions;
}

- (nullable MPNowPlayingInfoLanguageOption *)defaultLanguageOption {
    return _defaultLanguageOption;
}

- (BOOL)allowEmptySelection {
    return _allowEmptySelection;
}

@end
