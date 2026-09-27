//
//  CharonBraille.h
//  Accessibility
//
//  The braille half of the transcribed Accessibility declarations, in a header of its own so the
//  host differential can build the three classes without the request and the feature-override
//  session - whose names the host's own Accessibility.framework already has, and which would
//  collide with it. See CharonAccessibility.h for the transcription itself.
//

#import "CharonAccessibility.h"

// What the tables do not cover becomes a space, and this is how many characters that was, so a
// caller can tell a total translation from a partial one instead of reading the input back.
@interface AXBrailleTranslationResult (CharonUnmapped)

- (NSUInteger)charon_unmappedCount;

@end
