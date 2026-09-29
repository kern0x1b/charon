#import <AVFoundation/AVFoundation.h>

// 9 constants, the iOS 14.0 metadata key-space names, and nothing else: a name this file does not
// define is a name the corpus's gate asks for and the link cannot find, so the list
// below is the whole of this file's claim and the registry names each one of them.
//
// Every value was read out of the host's own AVFoundation at runtime, one dlsym of
// the exported symbol per name, and the differential in tests/backports/host/avf-metadata
// reads the same table out of two builds - Apple's framework on its own, and this file
// beside it in one binary with the names renamed - and diffs them. A value is not copied
// out of a header; it is what the framework answered, which is why one of them is the
// eleven ASCII characters "udta/%A9ade" and not a copyright sign.
//
// See facts/AVFoundation/MetadataKeySpaces.md.

NSString *const AVMetadataCommonIdentifierAccessibilityDescription = @"common/accessibilityDescription";
NSString *const AVMetadataCommonKeyAccessibilityDescription = @"accessibilityDescription";
NSString *const AVMetadataISOUserDataKeyAccessibilityDescription = @"ades";
NSString *const AVMetadataIdentifierISOUserDataAccessibilityDescription = @"uiso/ades";
NSString *const AVMetadataIdentifierQuickTimeMetadataAccessibilityDescription = @"mdta/com.apple.quicktime.accessibility.description";
NSString *const AVMetadataIdentifierQuickTimeMetadataLocationHorizontalAccuracyInMeters = @"mdta/com.apple.quicktime.location.accuracy.horizontal";
NSString *const AVMetadataIdentifierQuickTimeUserDataAccessibilityDescription = @"udta/%A9ade";
NSString *const AVMetadataQuickTimeMetadataKeyAccessibilityDescription = @"com.apple.quicktime.accessibility.description";
NSString *const AVMetadataQuickTimeUserDataKeyAccessibilityDescription = @"@ade";
