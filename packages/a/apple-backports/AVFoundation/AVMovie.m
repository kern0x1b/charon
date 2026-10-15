#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>

// AVMovie and AVMovieTrack, the read side, on a release that has neither (6.1.3).
//
// The 16.4 header makes AVMovie an AVAsset (AVMovie.h:57) and AVMovieTrack an AVAssetTrack (AVMovieTrack.h:22), so
// both are subclasses of classes this release has. A CharonMovie holds one AVURLAsset made from the URL and options
// the caller passed, and every public AVAsset member the header declares and this release carries is overridden to
// answer from that asset: the release's own answer, not a value of ours. Nothing a movie answers is inherited from
// AVAsset's own state, because AVAsset's methods read instance variables a movie does not have, so each member the
// set names is written here (facts/AVFoundation/AVMovie.md lists the set and the members left out, and why).
//
// A CharonMovieTrack wraps one AVAssetTrack of that asset the same way. The movie builds its tracks once, from the
// inner asset's tracks, and hands the same track objects out every time, so trackWithTrackID: and the filters search
// that one array. A track's -asset is the movie that made it, held weakly, because the movie owns its tracks.
//
// A data movie is written to a file in the app's temporary directory and read from there; the file is removed when
// the movie is deallocated. A movie made by -init has no URL and no inner asset: its members answer what a message to
// nil answers, and its track lists are empty.
//
// Nothing here is measured against the host yet. The host differential is the next band's job, and
// facts/AVFoundation/AVMovie.md says which answers are the release's own and which are a design still to be checked.

__attribute__((objc_runtime_name("AVMovie")))
@interface CharonMovie : AVAsset
@end

__attribute__((objc_runtime_name("AVMovieTrack")))
@interface CharonMovieTrack : AVAssetTrack
- (instancetype)initWithAssetTrack:(AVAssetTrack *)track movie:(CharonMovie *)movie;
@end

@interface CharonMovie ()
- (NSArray<AVAssetTrack *> *)charonTracks;
@end

@implementation CharonMovie
{
    NSURL *_charonURL;
    NSData *_charonData;
    NSURL *_charonTemporaryURL;
    AVURLAsset *_charonAsset;
    NSArray<AVAssetTrack *> *_charonTracks;
}

+ (NSArray<AVFileType> *)movieTypes
{
    return [AVURLAsset audiovisualTypes];
}

+ (instancetype)movieWithURL:(NSURL *)URL options:(NSDictionary<NSString *, id> *)options
{
    return [[self alloc] initWithURL:URL options:options];
}

+ (instancetype)movieWithData:(NSData *)data options:(NSDictionary<NSString *, id> *)options
{
    return [[self alloc] initWithData:data options:options];
}

- (instancetype)initWithURL:(NSURL *)URL options:(NSDictionary<NSString *, id> *)options
{
    // The reason is this library's own wording: the host's text for a nil URL is not measured.
    if (!URL)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"AVMovie: a movie opened from a URL needs that URL, and it is nil" userInfo:nil];
    if ((self = [super init])) {
        _charonURL = URL;
        _charonAsset = [[AVURLAsset alloc] initWithURL:URL options:options];
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data options:(NSDictionary<NSString *, id> *)options
{
    if (!data)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"AVMovie: a movie opened from data needs that data, and it is nil" userInfo:nil];
    if ((self = [super init])) {
        NSString *name = [NSString stringWithFormat:@"charon-movie-%@.mov", [[NSUUID UUID] UUIDString]];
        NSURL *URL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
        NSError *error = nil;
        if (![data writeToURL:URL options:NSDataWritingAtomic error:&error]) {
            NSLog(@"AVMovie: the movie data could not be written to %@: %@", URL.path, error);
            return nil;
        }
        _charonData = data;
        _charonTemporaryURL = URL;
        _charonAsset = [[AVURLAsset alloc] initWithURL:URL options:options];
    }
    return self;
}

- (void)dealloc
{
    if (_charonTemporaryURL)
        [[NSFileManager defaultManager] removeItemAtURL:_charonTemporaryURL error:nil];
}

// A movie is immutable: the copy is the movie itself, retained. AVMutableMovie, which is the mutable one, comes later.
- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

// The movie's own members, which the header declares on AVMovie.
- (NSURL *)URL
{
    return _charonURL;
}

- (NSData *)data
{
    return _charonData;
}

// This release keeps no media data storage for a movie, and AVMediaDataStorage is absent here.
- (AVMediaDataStorage *)defaultMediaDataStorage
{
    return nil;
}

// Fragmented movies are not read on this release (AVFragmentedMovie is absent), so no movie contains fragments.
- (BOOL)canContainMovieFragments
{
    return NO;
}

- (BOOL)containsMovieFragments
{
    return NO;
}

- (BOOL)isCompatibleWithFileType:(AVFileType)fileType
{
    return [[[self class] movieTypes] containsObject:fileType];
}

// The tracks are AVMovieTrack objects, one for each track of the inner asset, built the first time and kept.
- (NSArray<AVAssetTrack *> *)charonTracks
{
    if (!_charonTracks) {
        NSMutableArray<AVAssetTrack *> *tracks = [NSMutableArray array];
        for (AVAssetTrack *track in _charonAsset.tracks)
            [tracks addObject:[[CharonMovieTrack alloc] initWithAssetTrack:track movie:self]];
        _charonTracks = [tracks copy];
    }
    return _charonTracks;
}

- (NSArray<AVAssetTrack *> *)tracks
{
    return [self charonTracks];
}

- (AVAssetTrack *)trackWithTrackID:(CMPersistentTrackID)trackID
{
    for (AVAssetTrack *track in [self charonTracks])
        if (track.trackID == trackID)
            return track;
    return nil;
}

- (NSArray<AVAssetTrack *> *)tracksWithMediaType:(AVMediaType)mediaType
{
    NSMutableArray<AVAssetTrack *> *tracks = [NSMutableArray array];
    for (AVAssetTrack *track in [self charonTracks])
        if ([track.mediaType isEqualToString:mediaType])
            [tracks addObject:track];
    return tracks;
}

- (NSArray<AVAssetTrack *> *)tracksWithMediaCharacteristic:(AVMediaCharacteristic)mediaCharacteristic
{
    NSMutableArray<AVAssetTrack *> *tracks = [NSMutableArray array];
    for (AVAssetTrack *track in [self charonTracks])
        if ([track hasMediaCharacteristic:mediaCharacteristic])
            [tracks addObject:track];
    return tracks;
}

// The AVAsset members the header declares and this release carries, each answered by the inner asset.
- (CMTime)duration
{
    return _charonAsset.duration;
}

- (float)preferredRate
{
    return _charonAsset.preferredRate;
}

- (float)preferredVolume
{
    return _charonAsset.preferredVolume;
}

- (CGAffineTransform)preferredTransform
{
    return _charonAsset.preferredTransform;
}

- (CGSize)naturalSize
{
    return _charonAsset.naturalSize;
}

- (BOOL)providesPreciseDurationAndTiming
{
    return _charonAsset.providesPreciseDurationAndTiming;
}

- (AVAssetReferenceRestrictions)referenceRestrictions
{
    return _charonAsset.referenceRestrictions;
}

- (void)cancelLoading
{
    [_charonAsset cancelLoading];
}

- (NSArray<AVAssetTrackGroup *> *)trackGroups
{
    return _charonAsset.trackGroups ?: @[];
}

- (AVMetadataItem *)creationDate
{
    return _charonAsset.creationDate;
}

- (NSString *)lyrics
{
    return _charonAsset.lyrics;
}

- (NSArray<AVMetadataItem *> *)commonMetadata
{
    return _charonAsset.commonMetadata ?: @[];
}

- (NSArray<AVMetadataFormat> *)availableMetadataFormats
{
    return _charonAsset.availableMetadataFormats ?: @[];
}

- (NSArray<AVMetadataItem *> *)metadataForFormat:(AVMetadataFormat)format
{
    return [_charonAsset metadataForFormat:format] ?: @[];
}

- (NSArray<NSLocale *> *)availableChapterLocales
{
    return _charonAsset.availableChapterLocales ?: @[];
}

- (NSArray<AVTimedMetadataGroup *> *)chapterMetadataGroupsWithTitleLocale:(NSLocale *)locale containingItemsWithCommonKeys:(NSArray<AVMetadataKey> *)commonKeys
{
    return [_charonAsset chapterMetadataGroupsWithTitleLocale:locale containingItemsWithCommonKeys:commonKeys] ?: @[];
}

- (NSArray<AVTimedMetadataGroup *> *)chapterMetadataGroupsBestMatchingPreferredLanguages:(NSArray<NSString *> *)preferredLanguages
{
    return [_charonAsset chapterMetadataGroupsBestMatchingPreferredLanguages:preferredLanguages] ?: @[];
}

- (NSArray<AVMediaCharacteristic> *)availableMediaCharacteristicsWithMediaSelectionOptions
{
    return _charonAsset.availableMediaCharacteristicsWithMediaSelectionOptions ?: @[];
}

- (AVMediaSelectionGroup *)mediaSelectionGroupForMediaCharacteristic:(AVMediaCharacteristic)mediaCharacteristic
{
    return [_charonAsset mediaSelectionGroupForMediaCharacteristic:mediaCharacteristic];
}

- (BOOL)hasProtectedContent
{
    return _charonAsset.hasProtectedContent;
}

- (BOOL)isPlayable
{
    return _charonAsset.playable;
}

- (BOOL)isExportable
{
    return _charonAsset.exportable;
}

- (BOOL)isReadable
{
    return _charonAsset.readable;
}

- (BOOL)isComposable
{
    return _charonAsset.composable;
}

- (BOOL)isCompatibleWithSavedPhotosAlbum
{
    return _charonAsset.compatibleWithSavedPhotosAlbum;
}

// The asynchronous key-value loading protocol. A movie with no inner asset has nothing to load, so the handler is
// still called, on the main queue as the inner asset's would be called, and the status is the release's unknown.
- (AVKeyValueStatus)statusOfValueForKey:(NSString *)key error:(NSError * _Nullable __autoreleasing *)outError
{
    return [_charonAsset statusOfValueForKey:key error:outError];
}

- (void)loadValuesAsynchronouslyForKeys:(NSArray<NSString *> *)keys completionHandler:(void (^)(void))handler
{
    if (_charonAsset) {
        [_charonAsset loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
        return;
    }
    if (handler)
        dispatch_async(dispatch_get_main_queue(), handler);
}

@end

@implementation CharonMovieTrack
{
    AVAssetTrack *_charonTrack;
    __weak CharonMovie *_charonMovie;
}

// AVAssetTrack.h:40 makes -init unavailable to a caller, and the initializers the release takes a track through are
// private. So the release's own -init is sent to the superclass by name, as AVAssetAsyncLoading15.m sends the accessors
// the header does not declare; facts/AVFoundation/AVMovie.md says what that leaves unmeasured.
- (instancetype)initWithAssetTrack:(AVAssetTrack *)track movie:(CharonMovie *)movie
{
    struct objc_super parent = {self, [AVAssetTrack class]};
    if ((self = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, @selector(init)))) {
        _charonTrack = track;
        _charonMovie = movie;
    }
    return self;
}

// The movie that made the track, not the inner asset that holds it.
- (AVAsset *)asset
{
    return _charonMovie;
}

// The AVAssetTrack members the header declares and this release carries, each answered by the inner track.
- (NSArray<AVMetadataItem *> *)commonMetadata
{
    return _charonTrack.commonMetadata;
}

- (NSArray<AVMetadataFormat> *)availableMetadataFormats
{
    return _charonTrack.availableMetadataFormats;
}

- (NSArray<AVMetadataItem *> *)metadataForFormat:(AVMetadataFormat)format
{
    return [_charonTrack metadataForFormat:format];
}

- (float)estimatedDataRate
{
    return _charonTrack.estimatedDataRate;
}

- (NSString *)extendedLanguageTag
{
    return _charonTrack.extendedLanguageTag;
}

- (NSArray *)formatDescriptions
{
    return _charonTrack.formatDescriptions;
}

- (BOOL)hasMediaCharacteristic:(AVMediaCharacteristic)mediaCharacteristic
{
    return [_charonTrack hasMediaCharacteristic:mediaCharacteristic];
}

- (BOOL)isEnabled
{
    return _charonTrack.enabled;
}

- (BOOL)isPlayable
{
    return _charonTrack.playable;
}

- (BOOL)isSelfContained
{
    return _charonTrack.selfContained;
}

- (NSString *)languageCode
{
    return _charonTrack.languageCode;
}

- (AVMediaType)mediaType
{
    return _charonTrack.mediaType;
}

- (CGSize)naturalSize
{
    return _charonTrack.naturalSize;
}

- (CMTimeScale)naturalTimeScale
{
    return _charonTrack.naturalTimeScale;
}

- (float)nominalFrameRate
{
    return _charonTrack.nominalFrameRate;
}

- (CGAffineTransform)preferredTransform
{
    return _charonTrack.preferredTransform;
}

- (float)preferredVolume
{
    return _charonTrack.preferredVolume;
}

- (CMTime)samplePresentationTimeForTrackTime:(CMTime)trackTime
{
    return [_charonTrack samplePresentationTimeForTrackTime:trackTime];
}

- (AVAssetTrackSegment *)segmentForTrackTime:(CMTime)trackTime
{
    return [_charonTrack segmentForTrackTime:trackTime];
}

- (NSArray<AVAssetTrackSegment *> *)segments
{
    return _charonTrack.segments;
}

- (AVKeyValueStatus)statusOfValueForKey:(NSString *)key error:(NSError * _Nullable __autoreleasing *)outError
{
    return [_charonTrack statusOfValueForKey:key error:outError];
}

- (void)loadValuesAsynchronouslyForKeys:(NSArray<NSString *> *)keys completionHandler:(void (^)(void))handler
{
    [_charonTrack loadValuesAsynchronouslyForKeys:keys completionHandler:handler];
}

- (CMTimeRange)timeRange
{
    return _charonTrack.timeRange;
}

- (long long)totalSampleDataLength
{
    return _charonTrack.totalSampleDataLength;
}

- (CMPersistentTrackID)trackID
{
    return _charonTrack.trackID;
}

@end
