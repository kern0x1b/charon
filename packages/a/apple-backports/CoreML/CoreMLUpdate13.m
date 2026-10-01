// The four Core ML update classes of iOS 13 - MLTask, MLUpdateTask, MLUpdateContext and
// MLUpdateProgressHandlers - from MLTask.h, MLUpdateTask.h, MLUpdateContext.h and
// MLUpdateProgressHandlers.h of the iPhoneOS 16.4 surface.
//
// One object for one release: all four are annotated API_AVAILABLE(macos(10.15), ios(13.0), tvos(14.0))
// - MLTask.h:29, MLUpdateTask.h:19, MLUpdateContext.h:20 and MLUpdateProgressHandlers.h:18 - and
// nothing else is in this file. MLWritable, the protocol MLUpdateContext names in its own declaration,
// is NOT here and NOT carried: see the row, which says so with the measurement that proves it.
//
// WHAT MLTask IS, in the header's own words: "Class that abstracts state transitions and basic task
// controls" (MLTask.h:26-27). Its three properties are a taskIdentifier (:32-33), a state (:35-36) and
// an error (:38-39), and its two methods are given as their effect and nothing else:
//     -resume  "When called, resumes the task and changes state to \"Running\"."   (MLTask.h:41-42)
//     -cancel  "When called, starts cancelling the task and changes the state to \"Cancelling\"." (:44-45)
// The states are MLTaskState's own five cases (MLTask.h:16-24): Suspended 1, Running 2, Cancelling 3,
// Completed 4, Failed 5. So a transition from a state the header does not describe moving out of is
// refused by name, with the state printed, rather than forced: the header says what -resume does to a
// SUSPENDED task and nothing about resuming a cancelling one.
//
// -init and +new are NS_UNAVAILABLE on MLTask (MLTask.h:47-51) and again on MLUpdateTask
// (MLUpdateTask.h:53-56) and MLUpdateProgressHandlers (MLUpdateProgressHandlers.h:25-29), each with the
// header's own reason - "cannot construct MLTask without parameters" - so each refuses by name instead
// of making an object that has nothing in it.
//
// MLUpdateContext declares five readonly properties (MLUpdateContext.h:24-36) and NO initialiser at
// all, which is why it has the one below: the release builds a context inside its own training loop
// and hands it to the handlers, and there is no public way to make one, so neither is there here. What
// the getters answer is the state the context was built with, and nothing invents one.
//
// WHAT IS NOT CLAIMED. No number in this file is a measurement of Apple's code. What is written here is
// transcribed from the four headers above; what has been checked is the armv7 link, that this object
// defines the four classes it says. What is NOT here and is named rather than hidden: the model-update
// TRAINING loop. MLUpdateTask's only two initialisers are API_AVAILABLE(macos(11.0), ios(14.0))
// (MLUpdateTask.h:31 and :46), so at 13.0 the class carries none, and nothing in this port produces an
// MLUpdateProgressEvent - which is what MLUpdateProgressHandlers' two blocks would be called with. That
// is why that class's row is `inert` and not `implemented`: the class loads and its initialiser answers,
// and nothing in this port applies what it holds.

#import <CoreML/CoreML.h>

#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// What MPS's CharonMPSRefuse is - an NSLog - under this folder's own name, and a macro rather than a
// function so that no CoreML file depends on another one's symbols, for the reason CharonMPS.h gives
// for the same choice there. CoreML's own files return nil without saying so; a refusal here says
// which of the header's rules the call broke, because the header is what a reader will check against.
#define CharonMLRefuse(...) NSLog(__VA_ARGS__)

@implementation MLTask {
    NSString *_taskIdentifier;
    MLTaskState _state;
    NSError *_error;
}

// MLTask.h:47-51, "cannot construct MLTask without parameters". A task with no identifier and no state
// is not a task, so this refuses rather than making one whose every getter answers nil.
- (instancetype)init
{
    CharonMLRefuse(@"CoreML: MLTask.h:47 marks -init NS_UNAVAILABLE with the reason \"cannot construct MLTask"
                    @" without parameters\"; a task is made by the framework that runs it");
    return nil;
}

+ (instancetype)new
{
    // NSObject's +new is [[self alloc] init], so the refusal above is what this would reach anyway;
    // naming it here is what makes the refusal the caller's own answer rather than a chain through
    // NSObject's convenience.
    CharonMLRefuse(@"CoreML: MLTask.h:51 marks +new NS_UNAVAILABLE for the same reason -init is");
    return nil;
}

- (NSString *)taskIdentifier { return _taskIdentifier; }
- (MLTaskState)state { return _state; }
- (NSError *)error { return _error; }

// -resume, MLTask.h:41-42: "resumes the task and changes state to \"Running\"". The state it resumes
// FROM is the one the header describes, so a task that is not suspended says so and does not move.
- (void)resume
{
    if (_state != MLTaskStateSuspended) {
        CharonMLRefuse(@"CoreML: -[MLTask resume] was called on a task whose state is %ld, and MLTask.h:41"
                        @" describes resuming a Suspended task; nothing was changed",
                        (long)_state);
        return;
    }
    _state = MLTaskStateRunning;
}

// -cancel, MLTask.h:44-45: "starts cancelling the task and changes the state to \"Cancelling\"". A task
// that has already finished, failed or is already cancelling has nothing left to cancel.
- (void)cancel
{
    if (_state != MLTaskStateSuspended && _state != MLTaskStateRunning) {
        CharonMLRefuse(@"CoreML: -[MLTask cancel] was called on a task whose state is %ld, and MLTask.h:44"
                        @" describes cancelling a task that is Suspended or Running; nothing was changed",
                        (long)_state);
        return;
    }
    _state = MLTaskStateCancelling;
}

@end

// MLUpdateTask is MLTask's one subclass on the 13.0 surface (MLUpdateTask.h:20). Both of its
// initialisers are API_AVAILABLE(ios(14.0)) and neither is carried here, so the class is what this
// object holds: the identifier and the state machine above, with its own two constructors refused as
// the header marks them.
@implementation MLUpdateTask

- (instancetype)init
{
    CharonMLRefuse(@"CoreML: MLUpdateTask.h:53 marks -init NS_UNAVAILABLE with the reason \"cannot construct"
                    @" MLUpdateTask without parameters\", and both of its initialisers are API_AVAILABLE(ios(14.0))");
    return nil;
}

+ (instancetype)new
{
    CharonMLRefuse(@"CoreML: MLUpdateTask.h:56 marks +new NS_UNAVAILABLE for the same reason -init is");
    return nil;
}

@end

// MLUpdateContext declares five readonly properties and no initialiser (MLUpdateContext.h:21-38), so
// the one way in is the seam below and it is on the class because the five values are this class's own
// state and there is no other object that could carry them.
@interface MLUpdateContext (CharonMLUpdateContext)
- (instancetype)charon_ml_initWithTask:(MLUpdateTask *)task
                                 model:(MLModel *)model
                                 event:(MLUpdateProgressEvent)event
                               metrics:(NSDictionary *)metrics
                            parameters:(NSDictionary *)parameters;
@end

@implementation MLUpdateContext {
    MLUpdateTask *_task;
    MLModel *_model;
    MLUpdateProgressEvent _event;
    NSDictionary *_metrics;
    NSDictionary *_parameters;
}

- (instancetype)charon_ml_initWithTask:(MLUpdateTask *)task
                                 model:(MLModel *)model
                                 event:(MLUpdateProgressEvent)event
                               metrics:(NSDictionary *)metrics
                            parameters:(NSDictionary *)parameters
{
    // Each of the five is a strong ivar, so storing one retains it and storing another releases the one
    // held, and a caller that hands nil is answered nil rather than a stand-in.
    if ((self = [super init])) {
        _task = task;
        _model = model;
        _event = event;
        _metrics = [metrics copy];
        _parameters = [parameters copy];
    }
    return self;
}

- (MLUpdateTask *)task { return _task; }
- (MLModel *)model { return _model; }
- (MLUpdateProgressEvent)event { return _event; }
- (NSDictionary<MLMetricKey *, id> *)metrics { return _metrics; }
- (NSDictionary<MLParameterKey *, id> *)parameters { return _parameters; }

@end

// MLUpdateProgressHandlers, MLUpdateProgressHandlers.h:17-30: "Allows applications to register for
// progress and completion handlers", with the one initializer that registers them and -init and +new
// both unavailable. The two blocks are strong ivars, which is what ARC copies a block into, so what
// the caller registers outlives this method.
@implementation MLUpdateProgressHandlers {
    MLUpdateProgressEvent _interestedEvents;
    void (^_progressHandler)(MLUpdateContext *);
    void (^_completionHandler)(MLUpdateContext *);
}

- (instancetype)initForEvents:(MLUpdateProgressEvent)interestedEvents
              progressHandler:(void (^)(MLUpdateContext *))progressHandler
            completionHandler:(void (^)(MLUpdateContext *))completionHandler
{
    if (!completionHandler) {
        CharonMLRefuse(@"CoreML: MLUpdateProgressHandlers.h:22 declares the completion handler nonnull and"
                        @" none was given, so no handlers were registered");
        return nil;
    }
    if ((self = [super init])) {
        _interestedEvents = interestedEvents;
        _progressHandler = progressHandler;
        _completionHandler = completionHandler;
    }
    return self;
}

- (instancetype)init
{
    CharonMLRefuse(@"CoreML: MLUpdateProgressHandlers.h:25 marks -init NS_UNAVAILABLE with the reason"
                    @" \"cannot construct MLUpdateTask without parameters\" - the header's own wording, and it"
                    @" names the other class; use -initForEvents:progressHandler:completionHandler:");
    return nil;
}

+ (instancetype)new
{
    CharonMLRefuse(@"CoreML: MLUpdateProgressHandlers.h:29 marks +new NS_UNAVAILABLE for the same reason -init is");
    return nil;
}

@end