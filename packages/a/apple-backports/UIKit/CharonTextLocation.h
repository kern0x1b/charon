#import <UIKit/UIKit.h>

// The port's own concrete NSTextLocation, over an offset in a document. What a location means is the
// document's business and the range layer only ever compares two of them, so an offset is all it holds; a
// content manager that has a location of its own answers with that one instead, which is the whole point of the
// protocol. facts/UIKit/NSTextRange15.md has what the host's own UIKit answers for the range layer.
@interface CharonTextLocation : NSObject <NSTextLocation>
@property (nonatomic, readonly) NSInteger offset;
- (instancetype)initWithOffset:(NSInteger)offset;
@end
