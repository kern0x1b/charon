// CharonFileProviderProtocols.h - the FileProvider protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <FileProvider/FileProvider.h> for that body, and
#import <FileProvider/FileProvider.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol NSFileProviderChangeObserver;

@protocol NSFileProviderCustomAction;

@protocol NSFileProviderDomainState;

@protocol NSFileProviderEnumerating;

@protocol NSFileProviderEnumerationObserver;

@protocol NSFileProviderEnumerator;

@protocol NSFileProviderIncrementalContentFetching;

@protocol NSFileProviderItem;

@protocol NSFileProviderItemDecorating;

@protocol NSFileProviderPendingSetEnumerator;

@protocol NSFileProviderReplicatedExtension;

@protocol NSFileProviderServiceSource;

@protocol NSFileProviderServicing;

@protocol NSFileProviderTestingChildrenEnumeration;

@protocol NSFileProviderTestingCollisionResolution;

@protocol NSFileProviderTestingContentFetch;

@protocol NSFileProviderTestingCreation;

@protocol NSFileProviderTestingDeletion;

@protocol NSFileProviderTestingIngestion;

@protocol NSFileProviderTestingLookup;

@protocol NSFileProviderTestingModification;

@protocol NSFileProviderTestingOperation;

@protocol NSFileProviderThumbnailing;
