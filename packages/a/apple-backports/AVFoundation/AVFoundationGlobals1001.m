#import <AVFoundation/AVFoundation.h>

// The AVFoundation constants this object carries, one release's worth: an object may only hold API
// that arrived in one release, and which release that is was MEASURED off the held cache ladder with
// tools/symbol-first-release.lua - the first release whose AVFoundation EXPORTS the name - not read
// off a header's API_AVAILABLE. The two disagree for 1 of the 1 names here, which is
// why the header's own introduced version is not what this file is split by.
//
// Every value below was read, none was typed. 1 of the 1 names were read twice, from two
// independent places that agree: the shared cache of the iOS release that added the name -
// tools/corpus/cache-value.lua reads what the symbol its image exports holds - and the host's own
// AVFoundation, asked with dlopen + dlsym and decoded through CFStringGetCString as UTF-8, recorded
// in coordination/corpus/ledger/constant-values-AVFoundation.tsv with the build it was read on.
// facts/AVFoundation/Globals.md has both runs, their controls, the names they agree on, and the five
// AVCaptureWhiteBalanceTemperatureAndTintValues presets no oracle on this machine can answer.
//
// None of this is the port's minimum release own: it does not export these names, so an application
// that names one loads this string rather than a missing symbol, and where it hands the string to
// the release the release treats it as it treats any string it does not know.
NSString *const AVMediaTypeHaptic = @"hapt";
