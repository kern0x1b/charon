// CharonCoreNFCProtocols.h - the CoreNFC protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <CoreNFC/CoreNFC.h> for that body, and
#import <CoreNFC/CoreNFC.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

@protocol NFCFeliCaTag;

@protocol NFCISO15693Tag;

@protocol NFCISO7816Tag;

@protocol NFCMiFareTag;

@protocol NFCNDEFReaderSessionDelegate;

@protocol NFCNDEFTag;

@protocol NFCReaderSession;

@protocol NFCReaderSessionDelegate;

@protocol NFCTag;

@protocol NFCTagReaderSessionDelegate;

@protocol NFCVASReaderSessionDelegate;
