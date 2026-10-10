// CharonGameControllerProtocols.h - the GameController protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <GameController/GameController.h> for that body, and
#import <GameController/GameController.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
@protocol GCPhysicalInputSource;

typedef struct GCPoint2 GCPoint2;
API_AVAILABLE(ios(17.4))
@protocol GCAxis2DInput <NSObject>
@property (atomic, readwrite, copy) void (^ _NullablevalueDidChangeHandler)( id<GCPhysicalInputElement>  _Nonnull, id<GCAxis2DInput>  _Nonnull, GCPoint2);
@property (atomic, readonly) GCPoint2 value;
@property (atomic, readonly, getter=isAnalog) BOOL analog;
@property (atomic, readonly) BOOL canWrap;
@property (atomic, readonly) NSTimeInterval lastValueTimestamp;
@property (atomic, readonly) NSTimeInterval lastValueLatency;
@property (atomic, readonly, copy) NSSet<id<GCPhysicalInputSource>> * _Nonnull sources;
@end

@protocol GCAxisElement;

@protocol GCAxisElementName;

@protocol GCAxisInput;

@protocol GCButtonElement;

@protocol GCButtonElementName;

@protocol GCDevice;

@protocol GCDevicePhysicalInput;

@protocol GCDevicePhysicalInputState;

@protocol GCDevicePhysicalInputStateDiff;

@protocol GCDirectionPadElement;

@protocol GCDirectionPadElementName;

@class GCGameControllerActivationContext;
API_AVAILABLE(ios(18.0))
@protocol GCGameControllerSceneDelegate <NSObject>
- (void)scene:(UIScene * _Nonnull)scene didActivateGameControllerWithContext:(GCGameControllerActivationContext * _Nonnull)context;
@end

@protocol GCLinearInput;

@protocol GCPhysicalInputElement;

@protocol GCPhysicalInputElementName;

API_AVAILABLE(ios(26.2))
@protocol GCPhysicalInputExtents <NSObject>
@property (atomic, readonly) double scaledValue;
@property (atomic, readonly) double minimumValue;
@property (atomic, readonly) double maximumValue;
@end

@protocol GCPressedStateInput;

@protocol GCRelativeInput;

@protocol GCSwitchElement;

@protocol GCSwitchElementName;

@protocol GCSwitchPositionInput;

@protocol GCTouchedStateInput;
