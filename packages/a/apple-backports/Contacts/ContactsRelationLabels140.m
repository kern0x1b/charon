#import <Contacts/Contacts.h>

// The CNLabel names of iOS 14.0, with the texts Contacts itself gives them, read out of the arm64e
// shared cache of iOS 18.0 through each symbol with tools/cfconst.py (facts/Contacts/Values.md).
//
// One file for the one release these arrived in: an object carries the API of a single release. The armv7
// ladder measures CNLabelContactRelationGranddaughterOrNiece of them first appearing in the cache of iOS 16.0, which is the release the object is
// carried from.
//
// The text is the release's own and is not a spelling of the symbol: a label the release never made and this
// port never stores is still the name a dictionary of the release's own book is keyed by when a caller writes
// one, and it is what facts/Contacts/Values.md records.

NSString * const CNLabelContactRelationGranddaughterOrNiece = @"_$!<GranddaughterOrNiece>!$_";
NSString * const CNLabelContactRelationGrandsonOrNephew = @"_$!<GrandsonOrNephew>!$_";
