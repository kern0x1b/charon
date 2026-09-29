#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>

// The names CoreServices added in iOS 8.0, with the texts CoreServices itself gives them, read out
// of the arm64e shared cache of iOS 18.0 through each symbol with tools/cfconst.py (facts/CoreServices/Names.md).
//
// One file for the one release these arrived in: an object carries the API of a single release, and the
// armv7 ladder measures this name first appearing in the cache of iOS 8.0.
//
// The text is the release's own and is not a spelling of the symbol: a uniform type identifier is what a
// file's type is compared by, and a spelling of the constant would be a different type.

CFStringRef const kUTType3DContent = CFSTR("public.3d-content");
CFStringRef const kUTTypeAVIMovie = CFSTR("public.avi");
CFStringRef const kUTTypeAppleProtectedMPEG4Video = CFSTR("com.apple.protected-mpeg-4-video");
CFStringRef const kUTTypeAppleScript = CFSTR("com.apple.applescript.text");
CFStringRef const kUTTypeAssemblyLanguageSource = CFSTR("public.assembly-source");
CFStringRef const kUTTypeBinaryPropertyList = CFSTR("com.apple.binary-property-list");
CFStringRef const kUTTypeBookmark = CFSTR("public.bookmark");
CFStringRef const kUTTypeBzip2Archive = CFSTR("public.bzip2-archive");
CFStringRef const kUTTypeCalendarEvent = CFSTR("public.calendar-event");
CFStringRef const kUTTypeCommaSeparatedText = CFSTR("public.comma-separated-values-text");
CFStringRef const kUTTypeDatabase = CFSTR("public.database");
CFStringRef const kUTTypeDelimitedText = CFSTR("public.delimited-values-text");
CFStringRef const kUTTypeElectronicPublication = CFSTR("org.idpf.epub-container");
CFStringRef const kUTTypeEmailMessage = CFSTR("public.email-message");
CFStringRef const kUTTypeExecutable = CFSTR("public.executable");
CFStringRef const kUTTypeGNUZipArchive = CFSTR("org.gnu.gnu-zip-archive");
CFStringRef const kUTTypeInternetLocation = CFSTR("com.apple.internet-location");
CFStringRef const kUTTypeJSON = CFSTR("public.json");
CFStringRef const kUTTypeJavaArchive = CFSTR("com.sun.java-archive");
CFStringRef const kUTTypeJavaClass = CFSTR("com.sun.java-class");
CFStringRef const kUTTypeJavaScript = CFSTR("com.netscape.javascript-source");
CFStringRef const kUTTypeLog = CFSTR("public.log");
CFStringRef const kUTTypeM3UPlaylist = CFSTR("public.m3u-playlist");
CFStringRef const kUTTypeMIDIAudio = CFSTR("public.midi-audio");
CFStringRef const kUTTypeMPEG2TransportStream = CFSTR("public.mpeg-2-transport-stream");
CFStringRef const kUTTypeMPEG2Video = CFSTR("public.mpeg-2-video");
CFStringRef const kUTTypeOSAScript = CFSTR("com.apple.applescript.script");
CFStringRef const kUTTypeOSAScriptBundle = CFSTR("com.apple.applescript.script-bundle");
CFStringRef const kUTTypePHPScript = CFSTR("public.php-script");
CFStringRef const kUTTypePKCS12 = CFSTR("com.rsa.pkcs-12");
CFStringRef const kUTTypePerlScript = CFSTR("public.perl-script");
CFStringRef const kUTTypePlaylist = CFSTR("public.playlist");
CFStringRef const kUTTypePluginBundle = CFSTR("com.apple.plugin");
CFStringRef const kUTTypePresentation = CFSTR("public.presentation");
CFStringRef const kUTTypePropertyList = CFSTR("com.apple.property-list");
CFStringRef const kUTTypePythonScript = CFSTR("public.python-script");
CFStringRef const kUTTypeQuickLookGenerator = CFSTR("com.apple.quicklook-generator");
CFStringRef const kUTTypeRawImage = CFSTR("public.camera-raw-image");
CFStringRef const kUTTypeRubyScript = CFSTR("public.ruby-script");
CFStringRef const kUTTypeScript = CFSTR("public.script");
CFStringRef const kUTTypeShellScript = CFSTR("public.shell-script");
CFStringRef const kUTTypeSpotlightImporter = CFSTR("com.apple.metadata-importer");
CFStringRef const kUTTypeSpreadsheet = CFSTR("public.spreadsheet");
CFStringRef const kUTTypeSystemPreferencesPane = CFSTR("com.apple.systempreference.prefpane");
CFStringRef const kUTTypeTabSeparatedText = CFSTR("public.tab-separated-values-text");
CFStringRef const kUTTypeToDoItem = CFSTR("public.to-do-item");
CFStringRef const kUTTypeURLBookmarkData = CFSTR("com.apple.bookmark");
CFStringRef const kUTTypeUnixExecutable = CFSTR("public.unix-executable");
CFStringRef const kUTTypeWindowsExecutable = CFSTR("com.microsoft.windows-executable");
CFStringRef const kUTTypeX509Certificate = CFSTR("public.x509-certificate");
CFStringRef const kUTTypeXMLPropertyList = CFSTR("com.apple.xml-property-list");
CFStringRef const kUTTypeXPCService = CFSTR("com.apple.xpc-service");
