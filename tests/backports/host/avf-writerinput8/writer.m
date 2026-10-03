//  writer.m
//  The 8.0 multi-pass writer input, asked once and compiled twice.
//
//  THIS ONE FILE, TWICE:
//
//    the host half   compiled with the real <AVFoundation/AVFoundation.h> and linked against this
//                    machine's own AVFoundation. Every answer is Apple's own, and this half is the ORACLE:
//                    the expectations the port is held to are read from it and from nothing else.
//    the port half   compiled with -I standin, so <AVFoundation/AVFoundation.h> is the stand-in release -
//                    an AVAssetWriterInput with no pass machinery, an AVAssetWriter whose -startWriting
//                    means something - and linked with packages/a/apple-backports/AVFoundation/
//                    AVAssetWriterInputMultiPass8.m UNMODIFIED. The port's categories land on the
//                    stand-in's classes and the answers are the port's own.
//
//  Why the stand-in and not Apple's classes with the port linked over them: this Mac's AVAssetWriterInput
//  carries the whole 8.0 family, and the port's guard would - correctly - refuse to install over a release
//  that has it, so a link against the real classes would test the guard and nothing else. The stand-in is
//  shaped like the release the port runs on, which is what the family is written for.
//
//  Because the sequence is ONE source, the two halves cannot drift: every row is asked at the same point
//  in the same order, so a difference in a value is a difference in behaviour and a difference in a ROW is
//  a difference in the sequence itself, which run.sh reports rather than hides.
//
//  Three configurations, because the header makes the family settings-dependent and the port's answer
//  differs between two of them:
//
//    switch-off   the default: -performsMultiPassEncodingIfSupported is never set.
//    switch-on    it is set to YES before the writer starts. Apple's own class answers YES to
//                 -canPerformMultiplePasses and runs a real second pass; the port answers NO, which is
//                 the difference the port's file writes down and run.sh's ALLOWANCES name.
//    only         no member of the family is called at all and the pass is ended with the release's own
//                 -markAsFinished, which is what a 6.1.3 client does.
//
//  Every row is printed as `key | value` so a harness can join the two tables on the key without parsing
//  prose, and a value is never inferred: each one is what the object returned or what it raised.
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdio.h>

static int rowIndex;
static NSString *currentConfiguration = @"";

static void row(const char *key, NSString *value)
{
    rowIndex++;
    printf("%s%s | %s\n", currentConfiguration.UTF8String, key, value.UTF8String);
    fflush(stdout);
}

static void configure(NSString *name)
{
    currentConfiguration = [name stringByAppendingString:@": "];
}

// A real writer input, and a subclass that records the release's own -markAsFinished so a caller can see
// whether marking a PASS finished also finished the INPUT. The port's answer to that question is the
// whole point of the family, and it cannot be read off a source file.
@interface CharonSpyInput : AVAssetWriterInput
@property (nonatomic, strong) NSMutableArray<NSString *> *invoked;
@end

@implementation CharonSpyInput

- (instancetype)initWithProbeMediaType:(AVMediaType)mediaType outputSettings:(NSDictionary *)settings
{
    // The release's own factory, so the instance is a real writer input and not something this probe
    // invented. The release's -initWithMediaType:outputSettings: throws NSInvalidArgumentException
    // without AVVideoWidthKey and AVVideoHeightKey, measured by running this probe with only
    // AVVideoCodecKey, so both keys are always here.
    self = [super initWithMediaType:mediaType outputSettings:settings];
    if (self) {
        _invoked = [NSMutableArray array];
    }
    return self;
}

- (void)markAsFinished
{
    [self.invoked addObject:@"markAsFinished"];
    [super markAsFinished];
}

@end

static NSURL *charon_scratchURL(NSString *name)
{
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                   [NSString stringWithFormat:@"charon-avf-%@-%@-%u.mov", name,
                                       [[NSUUID UUID] UUIDString], getpid()]]];
}

// The video settings this machine can actually encode, asked of the release's own
// -canApplyOutputSettings:forMediaType: on a real writer rather than hard-coded, so the probe measures a
// writer that started and not a writer that refused.
static NSDictionary *charon_encodableSettings(void)
{
    NSDictionary *settings = @{AVVideoCodecKey: AVVideoCodecTypeH264,
                               AVVideoWidthKey: @16, AVVideoHeightKey: @16};
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:charon_scratchURL(@"ask")
                                                     fileType:AVFileTypeQuickTimeMovie
                                                        error:NULL];
    if (![writer canApplyOutputSettings:settings forMediaType:AVMediaTypeVideo])
        return nil;
    return settings;
}

static NSString *describeRanges(AVAssetWriterInputPassDescription *description)
{
    if (!description)
        return @"nil";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSValue *value in description.sourceTimeRanges) {
        CMTimeRange range = value.CMTimeRangeValue;
        [parts addObject:[NSString stringWithFormat:@"{%lld/%d,%lld/%d}",
                          (long long)range.start.value, (int)range.start.timescale,
                          (long long)range.duration.value, (int)range.duration.timescale]];
    }
    return parts.count ? [parts componentsJoinedByString:@" "] : @"[]";
}

static void reportCall(NSString *label, void (^work)(void))
{
    @try {
        work();
        row(label.UTF8String, @"ACCEPTED");
    } @catch (NSException *raised) {
        row(label.UTF8String, [NSString stringWithFormat:@"RAISED %@", raised.name]);
    }
}

// Everything the header says about the state of the pass, read at each state an input passes through.
static void askInputState(NSString *when, AVAssetWriterInput *input)
{
    row([[NSString stringWithFormat:@"canPerformMultiplePasses %@", when] UTF8String],
        input.canPerformMultiplePasses ? @"YES" : @"NO");

    NSString *current = @"NOT-ANSWERED";
    @try {
        current = describeRanges(input.currentPassDescription);
    } @catch (NSException *raised) {
        current = [NSString stringWithFormat:@"RAISED %@", raised.name];
    }
    row([[NSString stringWithFormat:@"currentPassDescription %@", when] UTF8String], current);
}

// ---- the controls: the tables this run read at all. A run that read nothing must not print a table
//      that reads like a measurement. ----
static void askControls(void)
{
    configure(@"CONTROL");
    Class inputClass = [AVAssetWriterInput class];
    Class passClass = NSClassFromString(@"AVAssetWriterInputPassDescription");
    row("CLASS AVAssetWriterInput", inputClass ? @"PRESENT" : @"ABSENT");
    row("CLASS AVAssetWriterInputPassDescription", passClass ? @"PRESENT" : @"ABSENT");
    SEL (^member)(const char *) = ^SEL(const char *name) {
        return NSSelectorFromString([NSString stringWithUTF8String:name]);
    };
    row("SELECTOR markAsFinished",
        class_getInstanceMethod(inputClass, @selector(markAsFinished)) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR charonProbeNoSuchSelector",
        class_getInstanceMethod(inputClass, member("charonProbeNoSuchSelector")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR performsMultiPassEncodingIfSupported",
        class_getInstanceMethod(inputClass, member("performsMultiPassEncodingIfSupported")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR setPerformsMultiPassEncodingIfSupported:",
        class_getInstanceMethod(inputClass, member("setPerformsMultiPassEncodingIfSupported:")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR canPerformMultiplePasses",
        class_getInstanceMethod(inputClass, member("canPerformMultiplePasses")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR currentPassDescription",
        class_getInstanceMethod(inputClass, member("currentPassDescription")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR respondToEachPassDescriptionOnQueue:usingBlock:",
        class_getInstanceMethod(inputClass, member("respondToEachPassDescriptionOnQueue:usingBlock:")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR markCurrentPassAsFinished",
        class_getInstanceMethod(inputClass, member("markCurrentPassAsFinished")) ? @"PRESENT" : @"ABSENT");
    row("SELECTOR sourceTimeRanges",
        passClass && class_getInstanceMethod(passClass, @selector(sourceTimeRanges)) ? @"PRESENT" : @"ABSENT");
}

// ---- the three states before any writer is involved. The switch is set only where the configuration
//      says it is: asking "what does canPerformMultiplePasses read back after the switch is set" inside
//      the switch-OFF configuration would print the same row twice under two names, and a row that is
//      there twice is a row nobody reads twice.
static void askUnattachedStates(NSDictionary *settings, BOOL requestMultiplePasses)
{
    configure(requestMultiplePasses ? @"switch-on unattached" : @"switch-off unattached");
    CharonSpyInput *lonely = [[CharonSpyInput alloc] initWithProbeMediaType:AVMediaTypeVideo
                                                             outputSettings:settings];
    askInputState(@"unattached", lonely);
    if (!requestMultiplePasses)
        return;

    reportCall(@"performsMultiPassEncodingIfSupported set YES", ^{
        lonely.performsMultiPassEncodingIfSupported = YES;
    });
    row(@"performsMultiPassEncodingIfSupported reads back".UTF8String,
        lonely.performsMultiPassEncodingIfSupported ? @"YES" : @"NO");
    askInputState(@"unattached after setting the switch", lonely);
}

// ---- the precondition the header states, asked on an input that is attached but whose writer has not
//      started: "Before calling this method, you must ensure that the receiver is attached to an
//      AVAssetWriter via a prior call to -addInput: and that -startWriting has been called" ----
static void askBeforeStartWriting(NSDictionary *settings, BOOL requestMultiplePasses)
{
    configure(requestMultiplePasses ? @"switch-on before startWriting" : @"switch-off before startWriting");
    NSURL *url = charon_scratchURL(@"early");
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie
                                                         error:NULL];
    CharonSpyInput *input = [[CharonSpyInput alloc] initWithProbeMediaType:AVMediaTypeVideo
                                                            outputSettings:settings];
    if (requestMultiplePasses)
        input.performsMultiPassEncodingIfSupported = YES;
    row(@"canAddInput:".UTF8String, [writer canAddInput:input] ? @"ACCEPTED" : @"REFUSED");
    [writer addInput:input];
    askInputState(@"attached before startWriting", input);

    // A SERIAL queue, and a specific on it, so "how many times did the block run" and "did it run on the
    // queue it was given" are both answered by a wait rather than by a race. dispatch_sync on a serial
    // queue returns only after everything enqueued before it has run.
    dispatch_queue_t queue = dispatch_queue_create("charon.avf.writerinput8", DISPATCH_QUEUE_SERIAL);
    static const char key = 'c';
    dispatch_queue_set_specific(queue, &key, (void *)1, NULL);

    __block NSInteger calls = 0;
    __block NSMutableArray *seen = [NSMutableArray array];
    __block NSInteger onTheGivenQueue = 0;
    void (^record)(void) = ^{
        calls++;
        [seen addObject:describeRanges(input.currentPassDescription)];
        if (dispatch_get_specific(&key))
            onTheGivenQueue++;
    };
    reportCall(@"respondToEachPassDescription before startWriting", ^{
        [input respondToEachPassDescriptionOnQueue:queue usingBlock:record];
    });
    reportCall(@"respondToEachPassDescription a second time", ^{
        [input respondToEachPassDescriptionOnQueue:queue usingBlock:record];
    });
    dispatch_sync(queue, ^{});
    row(@"block calls before startWriting".UTF8String, [NSString stringWithFormat:@"%ld", (long)calls]);
    row(@"block on the given queue before startWriting".UTF8String, [NSString stringWithFormat:@"%ld", (long)onTheGivenQueue]);

    reportCall(@"markCurrentPassAsFinished before startWriting", ^{
        [input markCurrentPassAsFinished];
    });
    reportCall(@"markAsFinished before startWriting", ^{
        [input markAsFinished];
    });
    row(@"markCurrentPassAsFinished called markAsFinished itself".UTF8String,
        input.invoked.count ? [input.invoked componentsJoinedByString:@","] : @"NO");
    [writer cancelWriting];
}

// ---- the whole sequence on one started writer, twice: the switch off, and the switch on ----
static void askFullSequence(NSDictionary *settings, BOOL requestMultiplePasses)
{
    configure(requestMultiplePasses ? @"switch-on" : @"switch-off");
    NSURL *url = charon_scratchURL(@"run");
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie
                                                         error:NULL];
    CharonSpyInput *input = [[CharonSpyInput alloc] initWithProbeMediaType:AVMediaTypeVideo
                                                            outputSettings:settings];
    [writer addInput:input];

    dispatch_queue_t queue = dispatch_queue_create("charon.avf.writerinput8", DISPATCH_QUEUE_SERIAL);
    static const char key = 'c';
    dispatch_queue_set_specific(queue, &key, (void *)1, NULL);
    __block NSInteger calls = 0;
    __block NSMutableArray *seen = [NSMutableArray array];
    __block NSInteger onTheGivenQueue = 0;

    if (requestMultiplePasses) {
        input.performsMultiPassEncodingIfSupported = YES;
        row(@"performsMultiPassEncodingIfSupported reads back before startWriting".UTF8String,
            input.performsMultiPassEncodingIfSupported ? @"YES" : @"NO");
    }

    row(@"startWriting".UTF8String, [writer startWriting] ? @"YES" : @"NO");
    askInputState(@"after startWriting", input);

    // the header: the switch "cannot be set after writing on the receiver's AVAssetWriter has started"
    reportCall(@"performsMultiPassEncodingIfSupported set YES after startWriting", ^{
        input.performsMultiPassEncodingIfSupported = YES;
    });
    row(@"performsMultiPassEncodingIfSupported reads back after startWriting".UTF8String,
        input.performsMultiPassEncodingIfSupported ? @"YES" : @"NO");
    askInputState(@"after setting the switch post-start", input);

    // the callback the header describes, registered where the header allows it: after -addInput: and
    // after -startWriting
    reportCall(@"respondToEachPassDescription after startWriting", ^{
        [input respondToEachPassDescriptionOnQueue:queue usingBlock:^{
            calls++;
            [seen addObject:describeRanges(input.currentPassDescription)];
            if (dispatch_get_specific(&key))
                onTheGivenQueue++;
        }];
    });
    dispatch_sync(queue, ^{});
    row(@"block calls on registration".UTF8String, [NSString stringWithFormat:@"%ld", (long)calls]);
    row(@"block on the given queue on registration".UTF8String, [NSString stringWithFormat:@"%ld", (long)onTheGivenQueue]);

    reportCall(@"respondToEachPassDescription a second time after startWriting", ^{
        [input respondToEachPassDescriptionOnQueue:queue usingBlock:^{
            calls++;
        }];
    });

    // the header: with canPerformMultiplePasses NO, currentPassDescription "will immediately become nil
    // after calling this method", and the block "will be invoked one final time so the client can invoke
    // -markAsFinished in response"
    [input.invoked removeAllObjects];
    reportCall(@"markCurrentPassAsFinished after startWriting", ^{
        [input markCurrentPassAsFinished];
    });
    askInputState(@"after markCurrentPassAsFinished", input);
    row(@"markCurrentPassAsFinished called markAsFinished itself".UTF8String,
        input.invoked.count ? [input.invoked componentsJoinedByString:@","] : @"NO");
    dispatch_sync(queue, ^{});
    row(@"block calls after markCurrentPassAsFinished".UTF8String, [NSString stringWithFormat:@"%ld", (long)calls]);
    row(@"block on the given queue after markCurrentPassAsFinished".UTF8String,
        [NSString stringWithFormat:@"%ld", (long)onTheGivenQueue]);
    row(@"block saw".UTF8String, seen.count ? [seen componentsJoinedByString:@" then "] : @"NONE");

    // a second -markCurrentPassAsFinished, now that there is no pass left to mark: the header does not
    // say it is refused, so it is asked rather than assumed either way
    reportCall(@"markCurrentPassAsFinished a second time", ^{
        [input markCurrentPassAsFinished];
    });
    dispatch_sync(queue, ^{});
    row(@"block calls after a second markCurrentPassAsFinished".UTF8String, [NSString stringWithFormat:@"%ld", (long)calls]);

    // and the client does what the final invocation told it to. With the switch on, Apple's own class
    // is between passes here and refuses, so this is caught like every other refusal: a run that dies
    // half way through prints a table that reads like a measurement and is not one.
    reportCall(@"markAsFinished after the final pass invocation", ^{
        [input markAsFinished];
    });
    askInputState(@"after markAsFinished", input);
    row(@"finishWriting".UTF8String, [writer finishWriting] ? @"YES" : @"NO");
    askInputState(@"after finishWriting", input);

    // The AVAssetExportSession member of the same mechanism, asked of a REAL asset: the release's own
    // -initWithAsset:presetName: answers nil for a nil asset, so nothing would be measured, and a row
    // that answers NOT-ANSWERED is not a measurement.
AVURLAsset *written = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:written
                                                                    presetName:AVAssetExportPresetPassthrough];
    if (!session) {
        row(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData".UTF8String, @"NO-SESSION");
    } else {
        @try {
            row(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData".UTF8String,
                session.canPerformMultiplePassesOverSourceMediaData ? @"YES" : @"NO");
        } @catch (NSException *raised) {
            row(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData".UTF8String,
                [NSString stringWithFormat:@"RAISED %@", raised.name]);
        }
        // the read/write pair, and the header's own "This property cannot be set after the export has
        // started" - asked with an export actually in flight, because a property that cannot be set after
        // a start is a different answer from one that cannot be set after nothing.
        reportCall(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData set YES", ^{
            session.canPerformMultiplePassesOverSourceMediaData = YES;
        });
        row(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData reads back".UTF8String,
            session.canPerformMultiplePassesOverSourceMediaData ? @"YES" : @"NO");
        dispatch_semaphore_t exported = dispatch_semaphore_create(0);
        // the release's own two members an export needs, or -exportAsynchronouslyWithCompletionHandler:
        // raises "outputURL cannot be nil" and nothing below would be measured
        session.outputURL = charon_scratchURL(@"export");
        session.outputFileType = AVFileTypeQuickTimeMovie;
        [session exportAsynchronouslyWithCompletionHandler:^{
            dispatch_semaphore_signal(exported);
        }];
        reportCall(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData set YES after the export started", ^{
            session.canPerformMultiplePassesOverSourceMediaData = YES;
        });
        // and what it read back afterwards, which is the whole of what a stored switch can tell a caller
        row(@"AVAssetExportSession canPerformMultiplePassesOverSourceMediaData reads back after the export started".UTF8String,
            session.canPerformMultiplePassesOverSourceMediaData ? @"YES" : @"NO");
        dispatch_semaphore_wait(exported, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    }
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

// ---- the release's own way of ending a pass, with none of the 8.0 family called at all: what the port
//      has to answer for a client that only ever uses -markAsFinished ----
static void askMarkAsFinishedOnly(NSDictionary *settings)
{
    configure(@"markAsFinished only");
    NSURL *url = charon_scratchURL(@"only");
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie
                                                         error:NULL];
    CharonSpyInput *input = [[CharonSpyInput alloc] initWithProbeMediaType:AVMediaTypeVideo
                                                            outputSettings:settings];
    [writer addInput:input];
    row(@"startWriting".UTF8String, [writer startWriting] ? @"YES" : @"NO");
    askInputState(@"after startWriting", input);
    [input markAsFinished];
    askInputState(@"after markAsFinished with no pass callback", input);
    [writer finishWriting];
    [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

int main(void)
{
    @autoreleasepool {
        askControls();
        NSDictionary *settings = charon_encodableSettings();
        if (!settings) {
            configure(@"CONFIGURATION");
            row(@"h264 16x16, no bitrate".UTF8String, @"THIS-MACHINE-ENCODES-NO-H264 so nothing below ran");
            printf("rows: %d\n", rowIndex);
            return 0;
        }
        configure(@"CONFIGURATION");
        row(@"h264 16x16, no bitrate".UTF8String, @"the settings this machine accepts, asked of -canApplyOutputSettings:forMediaType:");

        askUnattachedStates(settings, NO);
        askUnattachedStates(settings, YES);
        askBeforeStartWriting(settings, NO);
        askBeforeStartWriting(settings, YES);
        askFullSequence(settings, NO);
        askFullSequence(settings, YES);
        askMarkAsFinishedOnly(settings);

        configure(@"COUNT");
        row(@"rows".UTF8String, [NSString stringWithFormat:@"%d", rowIndex]);
    }
    return 0;
}
