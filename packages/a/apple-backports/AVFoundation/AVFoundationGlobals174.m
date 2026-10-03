#import <AVFoundation/AVFoundation.h>

// The AVFoundation constants iOS 17.4 added, which the releases this port targets do not export.
// One object per release: an object may only carry API that arrived in one of them, which the gate
// reads off the stub.
//
// Every value below was MEASURED, not written out by hand. 1 of the 1 names in this file
// were read twice, from two independent places that agree: the shared cache of the iOS release that
// added the name - tools/corpus/cache-value.lua reads what the symbol its image exports holds - and
// the host's own AVFoundation, asked with dlopen + dlsym and decoded through CFStringGetCString as
// UTF-8, recorded in coordination/corpus/ledger/constant-values-AVFoundation.tsv with the build it
// was read on. facts/AVFoundation/Globals.md has both runs, the names they agree on and the ones
// only one of them could reach.
//
// None of this is the port's minimum release own: it does not export these names, so an application
// that names one loads this string rather than a missing symbol, and where it hands the string to
// the release the release treats it as it treats any string it does not know.
NSString *const AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification = @"AVSampleBufferDisplayLayerReadyForDisplayDidChangeNotification";
