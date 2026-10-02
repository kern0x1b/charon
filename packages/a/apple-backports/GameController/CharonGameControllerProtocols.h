// CharonGameControllerProtocols.h - what the generated protocol sources of this library import.
//
// modules/apple/backports.lua writes one source per release a library's implemented protocol rows
// arrived in, and every one of them opens with `#import "CharonGameControllerProtocols.h"`. The
// framework's own header is what the generated source needs: a name it references has to have a body
// where the source is compiled, or the source does not compile at all - measured, a forward
// declaration with no umbrella import beside it gives
// `error: @protocol is using a forward protocol declaration of 'GCDevice'` on the one line
// GameControllerBackportsProtocols14.0.m spends on this protocol.
//
// GCDevice is the one protocol this library's implemented rows name. The SDK of 16.4 this package
// compiles against declares it, with a body, in GCDevice.h, which the umbrella import below brings
// in, so nothing is transcribed here and the forward declaration is the whole of what this file owes
// it: the same case CharonAccessibilityProtocols.h is in another framework, and the same shape
// tools/transcribe-protocols.py writes for a protocol the SDK the package compiles against defines.
//
// Usage: nothing imports this by hand. It is the one header the build's own generated sources name.
#import <GameController/GameController.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

// GCDevice arrived in iOS 14.0 and names four properties. The classes that conform to it - GCController,
// GCKeyboard and GCMouse, all three declared <GCDevice> by that same SDK - answer them here:
// handlerQueue and its setter, vendorName and productCategory on all three, and physicalInputProfile on
// GCController and GCKeyboard. GCMouse carries its profile through mouseInput, which is what the
// header's own note retires physicalInputProfile in favour of for a mouse.
@protocol GCDevice;