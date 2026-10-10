// CharonCarPlayProtocols.h - the CarPlay protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <CarPlay/CarPlay.h> for that body, and
#import <CarPlay/CarPlay.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol CPApplicationDelegate;

@protocol CPBarButtonProviding;

@protocol CPInstrumentClusterControllerDelegate;

@protocol CPInterfaceControllerDelegate;

@protocol CPListTemplateDelegate;

@protocol CPListTemplateItem;

@protocol CPMapTemplateDelegate;

@protocol CPNowPlayingTemplateObserver;

@protocol CPPointOfInterestTemplateDelegate;

@protocol CPSearchTemplateDelegate;

@protocol CPSelectableListItem;

@protocol CPSessionConfigurationDelegate;

@protocol CPTabBarTemplateDelegate;

@protocol CPTemplateApplicationDashboardSceneDelegate;

@protocol CPTemplateApplicationInstrumentClusterSceneDelegate;

@protocol CPTemplateApplicationSceneDelegate;
