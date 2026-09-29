#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

// The 135 string constants of VideoToolbox, each at the value it was MEASURED to have.
//
// Where the values come from, and why not from the release: the host cache on this machine is a 753KB
// stub (magic "dyld", not 0xfeedfacf) and the release's own 6.1.3 armv7 cache refuses to be read at
// all - it was copied from a running device and 3709 of its pages hold slid pointers, which is why
// tools/cfconst.py cannot use it. The host's VideoToolbox exports all 135 symbols and implements them,
// so each value was read out of the host's own code (tests/backports/host/videotoolbox) and this file
// is written from that table. Nothing here is a rule.
//
// The thing worth writing down, because it is the reason the table was needed at all: NONE of the 135
// values is the constant's own name. 117 are the last underscore-separated part of the name, 7 are
// everything after "kVT", and 11 are neither - among them
//   kVTCompressionPropertyKey_EstimatedAverageBytesPerFrame = kVTProCodecPropertyKey_AverageBytesPerFrame
//   kVTRotation_0                                            = Rotation0
//   kVTRotation_CCW90                                        = RotationCCW90
// A string constant written as its own name - the form this package uses for MXErrorDomain and
// PKPushTypeVoIP, both MEASURED to be right - would have been wrong in all 135.

// This file holds the constants of iOS 8.0; every other release's are in VideoToolboxConstants<major>_<minor>.m, because
// an object carries the API of one release.

const CFStringRef kVTCompressionPropertyKey_GammaLevel = CFSTR("GammaLevel");
const CFStringRef kVTCompressionPropertyKey_MultiPassStorage = CFSTR("MultiPassStorage");
const CFStringRef kVTDecompressionPropertyKey_MaximizePowerEfficiency = CFSTR("MaximizePowerEfficiency");
const CFStringRef kVTDecompressionPropertyKey_OutputPoolRequestedMinimumBufferCount = CFSTR("OutputPoolRequestedMinimumBufferCount");
const CFStringRef kVTMultiPassStorageCreationOption_DoNotDelete = CFSTR("DoNotDelete");
