#import <AVFoundation/AVFoundation.h>

// 6 constants, the iOS 15.4 metadata object types, and nothing else: a name this file does not
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

NSString *const AVMetadataObjectTypeCodabarCode = @"Codabar";
NSString *const AVMetadataObjectTypeGS1DataBarCode = @"org.gs1.GS1DataBar";
NSString *const AVMetadataObjectTypeGS1DataBarExpandedCode = @"org.gs1.GS1DataBarExpanded";
NSString *const AVMetadataObjectTypeGS1DataBarLimitedCode = @"org.gs1.GS1DataBarLimited";
NSString *const AVMetadataObjectTypeMicroPDF417Code = @"org.iso.MicroPDF417";
NSString *const AVMetadataObjectTypeMicroQRCode = @"org.iso.MicroQR";
