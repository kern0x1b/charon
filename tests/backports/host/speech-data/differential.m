// The iOS 10 Speech data classes, asked one question per process: the host's own Speech (a bare macOS tool, no bundle, no
// usage description) when built without -DPORT, and the port's sources in packages/a/apple-backports/Speech when built with
// it. The two sides are separate processes because both define the same classes.
//
// Each case is one argv[1] value and prints a fixed set of lines, so run.sh can compare the two sides case by case, and a
// crash of one side is attributed to that case alone. No recognizer is created or started: nothing here captures audio,
// opens the microphone, or sends anything to a server.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <objc/runtime.h>

static NSString *show(id value)
{
    return value ? [NSString stringWithFormat:@"%@", value] : @"nil";
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    int which = argc > 1 ? atoi(argv[1]) : -1;

    switch (which) {
    case 1: {
        SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:[NSURL fileURLWithPath:@"/nonexistent/recording.wav"]];
        printf("class=%s\n", class_getName([request class]));
        printf("URL=%s\n", show([request.URL absoluteString]).UTF8String);
        printf("taskHint=%ld\n", (long)request.taskHint);
        printf("shouldReportPartialResults=%d\n", request.shouldReportPartialResults);
        printf("contextualStrings=%s\n", show(request.contextualStrings).UTF8String);
        printf("interactionIdentifier=%s\n", show(request.interactionIdentifier).UTF8String);
        break;
    }
    case 2: {
        SFSpeechAudioBufferRecognitionRequest *request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
        printf("class=%s\n", class_getName([request class]));
        printf("taskHint=%ld\n", (long)request.taskHint);
        printf("shouldReportPartialResults=%d\n", request.shouldReportPartialResults);
        printf("contextualStrings=%s\n", show(request.contextualStrings).UTF8String);
        AVAudioFormat *format = request.nativeAudioFormat;
        printf("nativeAudioFormat sampleRate=%.0f channels=%u commonFormat=%ld interleaved=%d\n", format.sampleRate,
               (unsigned)format.channelCount, (long)format.commonFormat, format.isInterleaved);
        break;
    }
    case 3: {
        SFTranscription *transcription = [[SFTranscription alloc] init];
        printf("class=%s\n", class_getName([transcription class]));
        printf("formattedString=%s\n", show(transcription.formattedString).UTF8String);
        printf("segments=%s\n", show(transcription.segments).UTF8String);
        break;
    }
    case 4: {
        SFTranscriptionSegment *segment = [[SFTranscriptionSegment alloc] init];
        printf("class=%s\n", class_getName([segment class]));
        printf("substring=%s\n", show(segment.substring).UTF8String);
        printf("substringRange=%s\n", NSStringFromRange(segment.substringRange).UTF8String);
        printf("timestamp=%.1f duration=%.1f confidence=%.1f\n", segment.timestamp, segment.duration, segment.confidence);
        printf("alternativeSubstrings=%s\n", show(segment.alternativeSubstrings).UTF8String);
        break;
    }
    case 5: {
        SFTranscription *transcription = [[SFTranscription alloc] init];
        NSError *error = nil;
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:transcription requiringSecureCoding:YES error:&error];
        printf("archive error=%s\n", error ? "yes" : "none");
        printf("archive length>0=%d\n", archive.length > 0);
        SFTranscription *back = archive ? [NSKeyedUnarchiver unarchivedObjectOfClass:[SFTranscription class] fromData:archive error:&error] : nil;
        printf("unarchive error=%s\n", error ? "yes" : "none");
        printf("unarchived class=%s\n", back ? class_getName([back class]) : "nil");
        printf("unarchived formattedString=%s\n", show(back.formattedString).UTF8String);
        break;
    }
    case 6: {
        SFTranscriptionSegment *segment = [[SFTranscriptionSegment alloc] init];
        SFTranscriptionSegment *copy = [segment copy];
        printf("copy class=%s\n", class_getName([copy class]));
        printf("copy substringRange=%s\n", NSStringFromRange(copy.substringRange).UTF8String);
        printf("copy confidence=%.1f\n", copy.confidence);
        break;
    }
    case 7: {
        // The host raises when a fresh result's transcriptions are read: the case is named as a host crash by run.sh.
        SFSpeechRecognitionResult *result = [[SFSpeechRecognitionResult alloc] init];
        printf("final=%d\n", result.isFinal);
        printf("transcriptions=%s\n", show(result.transcriptions).UTF8String);
        printf("bestTranscription=%s\n", show(result.bestTranscription).UTF8String);
        break;
    }
    }
    return 0;
}
