#import "CharonAVAudioEngine.h"
#import "CharonAVAudioBuffer.h"
#import <AVFAudio/AVAudioConnectionPoint.h>

extern OSStatus CharonPlayerRenderCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp,
                                           UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

// The real topology this port builds, matching Apple's own default engine wiring: mainMixerNode
// is connected to outputNode from the moment the engine exists, before any application code runs.
// This port's engine does the same - AUGraphConnectNodeInput(mixer -> output) happens in -init,
// not left for a caller to do by hand.
//
// A player node carries no AudioUnit (see AVAudioPlayerNode.m); connecting one installs
// CharonPlayerRenderCallback on the destination's real input bus via AUGraphSetNodeInputCallback
// instead of AUGraphConnectNodeInput - the callback *is* the connection for that side.
//
// Test-only offline output: kAudioUnitSubType_GenericOutput needs no mediaserverd (confirmed via
// AudioComponentFindNext on a real 6.1.3 device - see facts/AVFoundation/AVAudioEngine.md) and
// pulls by hand through AudioUnitRender rather than a hardware I/O thread, which is exactly what
// proves a real application's node graph, format negotiation and buffer scheduling move real
// samples without needing a device. A real application still gets kAudioUnitSubType_RemoteIO -
// this switch is off by default and only ever set by a test binary.

static BOOL CharonOfflineOutput = NO;

@implementation AVAudioEngine {
    AUGraph _charon_graph;
    BOOL _charon_initialized;
    BOOL _charon_running;
    BOOL _charon_autoShutdown;
    AVAudioMixerNode *_charon_mainMixer;
    AVAudioOutputNode *_charon_output;
    AVAudioInputNode *_charon_input;
    NSMutableSet<AVAudioNode *> *_charon_attached;
    // player node (NSValue-wrapped pointer identity) -> (destination node, destination bus):
    // tracked so disconnectNodeOutput: knows which real graph entry point a callback source
    // actually landed on.
    NSMutableDictionary<NSValue *, NSArray *> *_charon_playerRoutes;
    BOOL _charon_offline;
}

static OSStatus CharonAddUnit(AUGraph graph, OSType type, OSType subtype, AUNode *outNode)
{
    AudioComponentDescription desc = {.componentType = type, .componentSubType = subtype, .componentManufacturer = kAudioUnitManufacturer_Apple};
    return AUGraphAddNode(graph, &desc, outNode);
}

- (instancetype)init
{
    if ((self = [super init])) {
        _charon_attached = [NSMutableSet set];
        _charon_playerRoutes = [NSMutableDictionary dictionary];
        _charon_offline = CharonOfflineOutput;

        AUGraph graph = NULL;
        NewAUGraph(&graph);
        AUGraphOpen(graph);
        _charon_graph = graph;

        AUNode outputAUNode = 0, mixerAUNode = 0;
        CharonAddUnit(graph, kAudioUnitType_Output, CharonOfflineOutput ? kAudioUnitSubType_GenericOutput : kAudioUnitSubType_RemoteIO, &outputAUNode);
        CharonAddUnit(graph, kAudioUnitType_Mixer, kAudioUnitSubType_MultiChannelMixer, &mixerAUNode);
        AUGraphConnectNodeInput(graph, mixerAUNode, 0, outputAUNode, 0);

        AudioUnit outputUnit = NULL, mixerUnit = NULL;
        AUGraphNodeInfo(graph, outputAUNode, NULL, &outputUnit);
        AUGraphNodeInfo(graph, mixerAUNode, NULL, &mixerUnit);

        UInt32 maxFrames = 4096;
        AudioUnitSetProperty(outputUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof(maxFrames));

        _charon_output = [AVAudioOutputNode new];
        [_charon_output charon_setEngine:self auNode:outputAUNode audioUnit:outputUnit];

        _charon_mainMixer = [AVAudioMixerNode new];
        [_charon_mainMixer charon_setEngine:self auNode:mixerAUNode audioUnit:mixerUnit];

        _charon_input = [AVAudioInputNode new];   // real capture path is out of this port's scope for now; see facts
    }
    return self;
}

- (void)dealloc
{
    if (_charon_graph) {
        AUGraphStop(_charon_graph);
        AUGraphClose(_charon_graph);
        DisposeAUGraph(_charon_graph);
    }
}

- (void)attachNode:(AVAudioNode *)node
{
    if ([node isKindOfClass:[AVAudioPlayerNode class]]) {
        [node charon_setEngine:self auNode:-1 audioUnit:NULL];
        [_charon_attached addObject:node];
        return;
    }
    // Real effect/converter nodes (AVAudioUnitEQ, AVAudioConverter) attach through their own
    // subclass, not implemented in this pass - see facts/AVFoundation/AVAudioEngine.md.
    [_charon_attached addObject:node];
}

- (void)detachNode:(AVAudioNode *)node
{
    [self disconnectNodeOutput:node];
    [self disconnectNodeInput:node];
    [node charon_setEngine:nil auNode:0 audioUnit:NULL];
    [_charon_attached removeObject:node];
}

- (void)connect:(AVAudioNode *)node1 to:(AVAudioNode *)node2 fromBus:(AVAudioNodeBus)bus1 toBus:(AVAudioNodeBus)bus2 format:(AVAudioFormat *)format
{
    AVAudioFormat *useFormat = format ?: [node1 outputFormatForBus:bus1];
    [node1 charon_setFormat:useFormat];
    [node2 charon_setFormat:useFormat];

    CharonAudioNodeImpl *destImpl = [node2 charon_impl];
    if (useFormat && destImpl->audioUnit)
        AudioUnitSetProperty(destImpl->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus2, [useFormat streamDescription], sizeof(AudioStreamBasicDescription));

    // The mixer's own output bus (towards the fixed mixer -> output connection made in -init) is
    // never itself the destination of a -connect:to:format: call, so nothing upstream would ever
    // otherwise set it - propagate here, once, so the whole offline chain shares one format.
    if (node2 == _charon_mainMixer && useFormat) {
        AudioUnitSetProperty(destImpl->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, [useFormat streamDescription], sizeof(AudioStreamBasicDescription));
        CharonAudioNodeImpl *outImpl = [_charon_output charon_impl];
        if (outImpl->audioUnit) {
            AudioUnitSetProperty(outImpl->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, [useFormat streamDescription], sizeof(AudioStreamBasicDescription));
            // The output unit's own Output scope is what AudioUnitRender actually formats `ioData`
            // by - measured, not assumed: every setup call here can return noErr while only the
            // Input scope is set, and AudioUnitRender still fails with -50 (paramErr) on the very
            // first pull. Setting Output scope too is what turned a real signal loss into an exact
            // sample match end to end (a raw AUGraph probe outside this class confirmed it before
            // this fix landed here - see facts/AVFoundation/AVAudioEngine.md).
            AudioUnitSetProperty(outImpl->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, [useFormat streamDescription], sizeof(AudioStreamBasicDescription));
        }
        [_charon_output charon_setFormat:useFormat];
    }

    if ([node1 isKindOfClass:[AVAudioPlayerNode class]]) {
        AURenderCallbackStruct callback = {.inputProc = CharonPlayerRenderCallback, .inputProcRefCon = (__bridge void *)node1};
        AUGraphSetNodeInputCallback(_charon_graph, destImpl->auNode, bus2, &callback);
        _charon_playerRoutes[[NSValue valueWithNonretainedObject:node1]] = @[node2, @(bus2)];
        return;
    }

    CharonAudioNodeImpl *srcImpl = [node1 charon_impl];
    if (srcImpl->audioUnit)
        AudioUnitSetProperty(srcImpl->audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus1, [useFormat streamDescription], sizeof(AudioStreamBasicDescription));
    AUGraphConnectNodeInput(_charon_graph, srcImpl->auNode, bus1, destImpl->auNode, bus2);
}

- (void)connect:(AVAudioNode *)node1 to:(AVAudioNode *)node2 format:(AVAudioFormat *)format
{
    [self connect:node1 to:node2 fromBus:0 toBus:0 format:format];
}

- (void)disconnectNodeInput:(AVAudioNode *)node bus:(AVAudioNodeBus)bus
{
    CharonAudioNodeImpl *impl = [node charon_impl];
    if (impl->auNode)
        AUGraphDisconnectNodeInput(_charon_graph, impl->auNode, bus);
}

- (void)disconnectNodeInput:(AVAudioNode *)node
{
    [self disconnectNodeInput:node bus:0];
}

- (void)disconnectNodeOutput:(AVAudioNode *)node bus:(AVAudioNodeBus)bus
{
    if ([node isKindOfClass:[AVAudioPlayerNode class]]) {
        NSValue *key = [NSValue valueWithNonretainedObject:node];
        NSArray *route = _charon_playerRoutes[key];
        if (route) {
            AVAudioNode *dest = route[0];
            AVAudioNodeBus destBus = [route[1] unsignedIntValue];
            AURenderCallbackStruct empty = {.inputProc = NULL, .inputProcRefCon = NULL};
            AUGraphSetNodeInputCallback(_charon_graph, [dest charon_impl]->auNode, destBus, &empty);
            [_charon_playerRoutes removeObjectForKey:key];
        }
        return;
    }
    // Disconnecting the output of a real (non-player) node beyond the mixer/output pair this pass
    // wires is future work - see facts/AVFoundation/AVAudioEngine.md.
}

- (void)disconnectNodeOutput:(AVAudioNode *)node
{
    [self disconnectNodeOutput:node bus:0];
}

- (NSArray<AVAudioConnectionPoint *> *)outputConnectionPointsForNode:(AVAudioNode *)node outputBus:(AVAudioNodeBus)bus
{
    if ([node isKindOfClass:[AVAudioPlayerNode class]]) {
        NSArray *route = _charon_playerRoutes[[NSValue valueWithNonretainedObject:node]];
        if (!route)
            return @[];
        return @[[[AVAudioConnectionPoint alloc] initWithNode:route[0] bus:[route[1] unsignedIntValue]]];
    }
    if (node == _charon_mainMixer)
        return @[[[AVAudioConnectionPoint alloc] initWithNode:_charon_output bus:0]];
    return @[];
}

- (void)prepare
{
    if (!_charon_initialized) {
        AUGraphInitialize(_charon_graph);
        _charon_initialized = YES;
    }
}

// A GenericOutput-terminated graph has no I/O thread for AUGraphStart to hand control to -
// AUGraphStart expects a real hardware output driving the pull, which offline rendering never has
// by definition; calling it anyway measured as `AudioUnitRender` returning -50 (paramErr) on every
// following manual pull. AUGraphInitialize is still real work (readies every unit in the graph);
// only the "hand it to a hardware thread" step is specific to a live RemoteIO output and skipped
// here - see facts/AVFoundation/AVAudioEngine.md.
- (BOOL)startAndReturnError:(NSError **)outError
{
    [self prepare];
    if (_charon_offline) {
        _charon_running = YES;
        return YES;
    }
    OSStatus status = AUGraphStart(_charon_graph);
    _charon_running = status == noErr;
    if (status != noErr && outError)
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return status == noErr;
}

- (void)pause
{
    if (!_charon_offline)
        AUGraphStop(_charon_graph);
    _charon_running = NO;
}

- (void)stop
{
    if (!_charon_offline)
        AUGraphStop(_charon_graph);
    _charon_running = NO;
}

- (void)reset
{
    for (AVAudioNode *node in _charon_attached)
        [node reset];
}

- (AVAudioOutputNode *)outputNode
{
    return _charon_output;
}

- (AVAudioInputNode *)inputNode
{
    return _charon_input;
}

- (AVAudioMixerNode *)mainMixerNode
{
    return _charon_mainMixer;
}

- (BOOL)isRunning
{
    return _charon_running;
}

- (BOOL)isAutoShutdownEnabled
{
    return _charon_autoShutdown;
}

- (void)setAutoShutdownEnabled:(BOOL)autoShutdownEnabled
{
    _charon_autoShutdown = autoShutdownEnabled;
}

@end

@implementation CharonAudioEngineTestSupport

+ (void)setForcedOfflineOutput:(BOOL)offline
{
    CharonOfflineOutput = offline;
}

+ (OSStatus)pullOutput:(AudioBufferList *)ioData frames:(AVAudioFrameCount)frames fromEngine:(AVAudioEngine *)engine
{
    CharonAudioNodeImpl *impl = [[engine outputNode] charon_impl];
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp timestamp = {0};
    timestamp.mSampleTime = 0;
    timestamp.mFlags = kAudioTimeStampSampleTimeValid;
    return AudioUnitRender(impl->audioUnit, &flags, &timestamp, 0, frames, ioData);
}

@end
