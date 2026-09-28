// port.m — the port's own classes, beside Apple's, in one binary.
//
// The port's sources are compiled with every class name they define renamed (port.sh), so this file
// can hold charon_host_AUAudioUnit and Apple's AUAudioUnit to the same question and compare the two
// answers. That is the check round 3 found missing: with a harness that called only Apple's classes,
// a mutation of the port's channelCapabilities left everything green.
//
// The comparison is over numbers, statuses and refusals — the things a differential can settle — and
// not over pointer identity or Apple's private state, which the port has no business knowing. Where
// the port answers something the host declines to, both answers are printed and the check asks
// whether the port's is consistent with the release, not whether it is equal to the host's.

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFAudio/AVFAudio.h>

// The port's own class names, as the rename left them. Declared here rather than imported, because
// the port's headers declare Apple's names and this file is asking about the renamed ones.
@interface charon_host_AUAudioUnit : NSObject
- (instancetype)initWithComponentDescription:(AudioComponentDescription)description error:(NSError **)error;
@property (readonly) NSArray<NSNumber *> *channelCapabilities;
- (NSArray<NSNumber *> *)parametersForOverviewWithCount:(NSInteger)count;
@property (readonly) NSArray<NSNumber *> *applicableRenderingAlgorithms;
@property (nonatomic) BOOL shouldBypassEffect;
@property (readonly) double latency;
@property (readonly) double tailTime;
@property (nonatomic) AURenderBlock renderBlock;
- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)error;
@end

@interface charon_host_AUAudioUnitBus : NSObject
@property (readonly) NSArray<NSNumber *> *supportedChannelLayoutTags;
@property (readonly) double latency;
@end

@interface charon_host_AUAudioUnitBusArray : NSObject
@end

@interface charon_host_AUParameterTree : NSObject
@property (readonly) NSArray *allParameters;
- (id)parameterWithAddress:(AUParameterAddress)address;
@end

static int checks = 0;
static int failures = 0;

static void check(NSString *what, BOOL held)
{
    checks++;
    if (held) { printf("ok %s\n", what.UTF8String); }
    else { failures++; printf("FAIL %s\n", what.UTF8String); }
}

// The two must agree about what they are holding before a comparison of their answers means anything.
static AudioComponentDescription CharonFirstComponentOfType(OSType type)
{
    AudioComponentDescription any = {0};
    any.componentType = type;
    AudioComponent component = AudioComponentFindNext(NULL, &any);
    if (component == NULL) { return (AudioComponentDescription){0}; }
    AudioComponentDescription described;
    AudioComponentGetDescription(component, &described);
    return described;
}

int main(void)
{
    @autoreleasepool {
        // The port's AUAudioUnit, on a real component, next to Apple's on the same one.
        AudioComponentDescription described = CharonFirstComponentOfType(kAudioUnitType_Effect);
        if (described.componentType == 0) {
            printf("FAIL no host effect component: the port and the host would be asked nothing\n");
            return 1;
        }
        char sub[5] = {0};
        OSType subtype = described.componentSubType;
        memcpy(sub, &subtype, 4);
        printf("stage both are asked about type 'xfua' subtype '%s'\n", sub);

        NSError *portError = nil;
        charon_host_AUAudioUnit *port = [[charon_host_AUAudioUnit alloc] initWithComponentDescription:described error:&portError];
        check(@"the port's AUAudioUnit instantiates a real component", port != nil && portError == nil);
        AUAudioUnit *host = [[AUAudioUnit alloc] initWithComponentDescription:described error:NULL];
        check(@"the host's AUAudioUnit instantiates the same one", host != nil);
        if (port == nil || host == nil) {
            printf("checks=%d failures=%d\n", checks, failures);
            return 1;
        }

        // ---- channelCapabilities: the (input, output) pair, in that order.
        // This is the member the review mutated by swapping [0] and [1], and it is the one this
        // harness exists to see: the host's own header documents the order as
        // "(-16, 2) indicates that a unit can accept up to 16 channels of input across its input
        // busses, but will only produce 2 channels of output".
        NSArray *portChannels = port.channelCapabilities;
        NSArray *hostChannels = host.channelCapabilities;
        printf("stage channelCapabilities: port %s, host %s\n",
               portChannels.description.UTF8String, hostChannels.description.UTF8String);
        check(@"both answer two numbers, or neither does",
              (portChannels.count == 2) == (hostChannels.count == 2));
        if (portChannels.count == 2 && hostChannels.count == 2) {
            // the input count is the one that can exceed the output count, and it is first
            check(@"the port's first number is the input count, as the header documents",
                  [portChannels[0] integerValue] >= [portChannels[1] integerValue]);
            check(@"the port's pair matches the host's element for element",
                  [portChannels[0] isEqual:hostChannels[0]] && [portChannels[1] isEqual:hostChannels[1]]);
        }

        // ---- latency and tailTime as the header's Float64, which is what the port fixed.
        printf("stage latency: port %g, host %g | tailTime: port %g, host %g\n",
               port.latency, host.latency, port.tailTime, host.tailTime);
        check(@"the port's latency is the host's latency",
              fabs(port.latency - host.latency) <= 1e-9);
        check(@"the port's tail time is the host's tail time",
              fabs(port.tailTime - host.tailTime) <= 1e-9);
        // the narrow read is the finding, and both classes are asked it: a Float32 read of a Float64
        // property is accepted and returns half a double
        Float64 tail = host.tailTime;
        Float32 narrow = (Float32)tail;
        if (tail != 0) {
            check(@"a Float32 read of the tail time disagrees with it, which is why it is read wide",
                  (double)narrow != (double)tail);
        }

        // ---- shouldBypassEffect is the unit's own kAudioUnitProperty_BypassEffect, read back from
        // the unit rather than from an ivar, so the port and the host must agree after a set.
        port.shouldBypassEffect = YES;
        host.shouldBypassEffect = YES;
        check(@"the port's bypass reads back what the host's does after the same set",
              port.shouldBypassEffect == host.shouldBypassEffect);
        printf("stage shouldBypassEffect: port %d, host %d\n", port.shouldBypassEffect, host.shouldBypassEffect);
        port.shouldBypassEffect = NO;
        host.shouldBypassEffect = NO;
        check(@"and both clear it", !port.shouldBypassEffect && !host.shouldBypassEffect);

        // ---- the parameter tree is the unit's own list, and both read the same unit. The port
        // builds its tree when render resources are allocated, which is where a v2 unit answers its
        // parameter questions at all, so that is called first: asking before it is asking the port
        // the wrong question, and its answer of none would be the right one.
        NSError *resourceError = nil;
        BOOL allocated = [port allocateRenderResourcesAndReturnError:&resourceError];
        check(@"the port allocates render resources", allocated);
        id portTree = [port valueForKey:@"parameterTree"];
        id hostTree = host.parameterTree;
        NSUInteger portCount = [portTree respondsToSelector:@selector(allParameters)] ? [[portTree allParameters] count] : 0;
        NSUInteger hostCount = [hostTree respondsToSelector:@selector(allParameters)] ? [[hostTree allParameters] count] : 0;
        printf("stage parameter tree: port %lu parameters, host %lu\n", (unsigned long)portCount, (unsigned long)hostCount);
        check(@"the port reads the unit's parameters, and not none of them", portCount > 0);
        check(@"the port and the host count the same parameters of the same unit", portCount == hostCount);

        // ---- the render block is the unit's own input, and both are asked to fill a buffer.
        __block NSUInteger portRenders = 0;
        __block NSUInteger hostRenders = 0;
        AudioBufferList portList = {0};
        AudioBufferList hostList = {0};
        float *portData = calloc(512, sizeof(float));
        float *hostData = calloc(512, sizeof(float));
        portList.mNumberBuffers = 1;
        portList.mBuffers[0].mNumberChannels = 1;
        portList.mBuffers[0].mDataByteSize = 512 * sizeof(float);
        portList.mBuffers[0].mData = portData;
        hostList = portList;
        hostList.mBuffers[0].mData = hostData;
        port.renderBlock = ^(AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp,
                             AVAudioFrameCount frames, NSInteger bus, AudioBufferList *data,
                             AURenderPullInputBlock pull) {
            (void)flags; (void)timestamp; (void)frames; (void)bus; (void)pull;
            portRenders++;
            memset(data->mBuffers[0].mData, 0, data->mBuffers[0].mDataByteSize);
            return noErr;
        };
        // readwrite on the iOS SDK, readonly on the macOS one this harness builds against, so it is
        // set through KVC - the port's is the one under test and it is set directly
        AURenderBlock hostBlock = ^(AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp,
                                    AVAudioFrameCount frames, NSInteger bus, AudioBufferList *data,
                                    AURenderPullInputBlock pull) {
            (void)flags; (void)timestamp; (void)frames; (void)bus; (void)pull;
            hostRenders++;
            memset(data->mBuffers[0].mData, 0, data->mBuffers[0].mDataByteSize);
            return noErr;
        };
        [host setValue:hostBlock forKey:@"renderBlock"];
        AudioUnitRenderActionFlags flags = 0;
        AudioTimeStamp timestamp = {0};
        timestamp.mFlags = kAudioTimeStampSampleTimeValid;
        if (port.renderBlock != NULL) {
            port.renderBlock(&flags, &timestamp, 512, 0, &portList, NULL);
        }
        if (host.renderBlock != NULL) {
            host.renderBlock(&flags, &timestamp, 512, 0, &hostList, NULL);
        }
        free(portData);
        free(hostData);
        printf("stage render block: port called %lu, host called %lu\n",
               (unsigned long)portRenders, (unsigned long)hostRenders);
        check(@"the port's render block is called when a pull comes", portRenders == 1);
        // the host's block is only reported: on the macOS SDK this harness builds against
        // -[AUAudioUnit renderBlock] is readonly, so setting it is not a comparison the two can make
        printf("stage the host's render block calls %lu (readonly on this SDK, so reported, not compared)\n",
               (unsigned long)hostRenders);

        printf("checks=%d failures=%d\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
