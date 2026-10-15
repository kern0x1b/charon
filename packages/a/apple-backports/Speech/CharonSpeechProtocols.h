// CharonSpeechProtocols.h: the Speech protocols of iOS 10 that the release lacks, with their bodies as the SDK declares them.
//
// The protocols are declared with their optional methods rather than forward-declared: a forward declaration makes the
// protocol exist with no method descriptions, so an application that asks the runtime whether a recognizer delegate answers
// speechRecognizer:availabilityDidChange: gets NO. The classes the methods name are forward-declared, and the umbrella header
// is not imported here, because with both it would define each protocol twice.
#import <Foundation/Foundation.h>

@class SFSpeechRecognizer;
@class SFSpeechRecognitionTask;
@class SFSpeechRecognitionResult;
@class SFTranscription;

@protocol SFSpeechRecognizerDelegate <NSObject>

@optional
- (void)speechRecognizer:(SFSpeechRecognizer *)speechRecognizer availabilityDidChange:(BOOL)available;

@end

@protocol SFSpeechRecognitionTaskDelegate <NSObject>

@optional
- (void)speechRecognitionDidDetectSpeech:(SFSpeechRecognitionTask *)task;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didHypothesizeTranscription:(SFTranscription *)transcription;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishRecognition:(SFSpeechRecognitionResult *)recognitionResult;
- (void)speechRecognitionTaskFinishedReadingAudio:(SFSpeechRecognitionTask *)task;
- (void)speechRecognitionTaskWasCancelled:(SFSpeechRecognitionTask *)task;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didFinishSuccessfully:(BOOL)successfully;
- (void)speechRecognitionTask:(SFSpeechRecognitionTask *)task didProcessAudioDuration:(NSTimeInterval)duration;

@end
