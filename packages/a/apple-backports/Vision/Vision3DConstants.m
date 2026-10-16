#import <Vision/Vision.h>

/* The group key of the 3D body pose points. Its own object: the SDK marks it 14.0, but no held release cache before
 * 18.0 exports it, and the gate places an object by the earliest release that exports what it defines, so it cannot
 * share an object with the iOS 14 constants of Vision14_0Constants.m. The value is the host's (facts/Vision/Constants14.md). */

VNRecognizedPointGroupKey const VNRecognizedPoint3DGroupKeyAll = @"VNIPOAll";
