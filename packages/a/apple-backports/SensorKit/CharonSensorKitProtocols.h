// CharonSensorKitProtocols.h — the SensorKit protocols the generated protocol sources name.
//
// Written in the shape tools/transcribe-protocols.py writes, and for the same reason: SensorKit's own
// reader hands its delegate messages, so an application compiled against SDK 26.2 declares
// `id<SRSensorReaderDelegate>` and conforms to a protocol that does not exist at run time on a release
// this port serves. Nothing in the port adopts it, so the port emits no __OBJC_PROTOCOL_$_ for it on
// its own — which backports.lua's protocol_sources answers by writing one object per release that
// names the protocol, and clang then emits the metadata.
//
// WHY A FORWARD DECLARATION AND NO BODY HERE. The 16.4 SDK this package compiles against already
// declares this protocol with a body, at SRSensorReader.h:21, so transcribing it here would be copying
// a header to state a fact the build's own SDK already states. The umbrella import below supplies that
// body, exactly as CharonMetalProtocols.h does for the Metal protocols the 16.4 SDK already defines.
// A forward declaration on its own emits nothing: @protocol X; is not a protocol, and
// protocol_getMethodDescriptionCount on it would answer 0 for all ten methods this protocol carries.

#import <SensorKit/SensorKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol SRSensorReaderDelegate;