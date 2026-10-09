// Charon's declarations of the MIDI-CI protocols of the CoreMIDI backports: the responder's delegate of MIDI-CI 1.x, which the
// protocol-sources gate reads (tests/addon/protocol-sources.sh). The initiator identifier is declared here as well, because
// the protocol names it and the classes header imports this one.
#ifndef CharonCoreMIDIProtocols_h
#define CharonCoreMIDIProtocols_h

#import <Foundation/Foundation.h>
#import <CoreMIDI/MIDIServices.h>

#import "CharonMIDIUMP18.h"

@class MIDICIDeviceInfo, MIDICIProfile;

typedef NSNumber *MIDICIInitiatiorMUID;

NS_ASSUME_NONNULL_BEGIN

@protocol MIDICIProfileResponderDelegate <NSObject>
- (BOOL)connectInitiator:(MIDICIInitiatiorMUID)initiatorMUID withDeviceInfo:(MIDICIDeviceInfo *)deviceInfo;
- (void)initiatorDisconnected:(MIDICIInitiatiorMUID)initiatorMUID;
- (BOOL)willSetProfile:(MIDICIProfile *)aProfile onChannel:(MIDIChannelNumber)channel enabled:(BOOL)shouldEnable;
- (void)handleDataForProfile:(MIDICIProfile *)aProfile onChannel:(MIDIChannelNumber)channel data:(NSData *)inData;
@end

NS_ASSUME_NONNULL_END

#endif
