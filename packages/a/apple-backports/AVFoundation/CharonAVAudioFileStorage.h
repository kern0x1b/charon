// AVAudioFile's storage, declared where BOTH of the files that touch it can see it.
//
// The class object and the member category are two files on purpose - a class symbol is dropped from
// 8.0 up and a category defines no symbol and is never dropped - so the storage cannot live in a
// class extension inside one of them: the other would not see it. Declared here as a class extension
// the two both import, which is the same arrangement CharonAVFDescriptorConstruction.h uses for the
// descriptor classes' initializers.
//
// AVAudioSettings is declared here for the same reason: this SDK ships no header for it, and the two
// writing initialisers take it. The port never inspects it, because writing is refused.
#ifndef CHARON_AVAUDIOFILE_STORAGE_H
#define CHARON_AVAUDIOFILE_STORAGE_H

#import <AVFAudio/AVFAudio.h>
#import <CoreAudioTypes/CoreAudioTypes.h>
#import <Foundation/Foundation.h>

@interface AVAudioSettings : NSObject
@end

// The release's AVAudioFormat, and the members the port reads to serve an uncompressed file. This SDK
// declares none of them as properties on the class, so they are declared here to give the reads a
// compile-checked selector and return type rather than an untyped cast.
@interface AVAudioFormat (CharonAVAudioFileFormat)
@property (readonly) AudioFormatID mFormatID;
@property (readonly) UInt32 mBytesPerFrame;
// Neither initialiser is declared by this SDK's header and the port calls both, so they are declared
// here to give the calls a compile-checked selector rather than an untyped send.
- (instancetype)initWithStandardFormatWithSampleRate:(double)sampleRate channels:(AVAudioChannelCount)channels;
@end

@interface AVAudioFile ()
@property (nonatomic, strong) NSURL *charonURL;
@property (nonatomic, strong) AVAudioFormat *charonProcessingFormat;
@property (nonatomic, strong) AVAudioFormat *charonFileFormat;
@property (nonatomic, strong) NSData *charonPCM;
@property (nonatomic) BOOL charonOpen;
@property (nonatomic) int64_t charonLength;
@property (nonatomic) int64_t charonFramePosition;
@end

#endif
