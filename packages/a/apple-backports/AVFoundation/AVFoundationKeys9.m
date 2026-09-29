#import <AVFoundation/AVFoundation.h>

// 1 of the 33 notification names, user-info keys and option keys this slice carries: the one name the 9.3.6 rung is the first to export.
//
// Every value was read out of the host's own AVFoundation at runtime, one dlsym of the exported
// symbol per name, and the differential in tests/backports/host/avf-notifications reads the same table
// out of two builds - Apple's framework on its own, and this file beside it in one binary with the
// names renamed - and diffs it, the text and the bytes both.
//
// 23 of the 33 answer their own symbol's name and 10 do not, and which 10 is a measurement rather
// than a rule: AVMediaCharacteristicContainsAlphaChannel is "public.contains-alpha-channel" and
// ContainsHDRVideo is "public.contains-hdr-video", while the four
// AVPlayerInterstitialEventMonitor...Key/Notification names drop the monitor's own prefix and the
// AVVideoAppleProRAWBitDepthKey answers "AppleProRAWBitDepthKey". An earlier note in this file said all
// 33 were their own name; the host says otherwise for those ten and the port follows the host.
//
// The objects are split by MEASUREMENT, not by the corpus's introduced: an object may not mix a name a
// band already exports with one it does not, or backports.lua's band() raises "an object carries API
// that arrived in one release". Searching the held caches - 4.3, 6.1.3, 7.0, 7.1, 7.1.1, 7.1.2 and 8.0 (armv7), 8.1.3, 8.2 and 8.4.1 (armv7s), 9.3.6 (armv7), 10.0.1, 11.0 and 12.0 (arm64) and 16.0 (arm64e) - for each name's own exported
// symbol gives the FIRST HELD RUNG that exports it, and this file is the one holding the the one name the 9.3.6 rung is the first to export. "First
// held rung" is the honest phrase: a release between two held ones may export a name and this
// measurement cannot see it. _NSFileSize is planted as a control wherever a rung is claimed.
//
// See facts/AVFoundation/AVFoundationNotificationKeys.md.
NSString *const AVPlayerItemMediaSelectionDidChangeNotification = @"AVPlayerItemMediaSelectionDidChangeNotification";
