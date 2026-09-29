// The stand-in the contract check compiles the port's own source against: an item that answers
// valueForProperty: from a table, which is the whole of what the 26.2 header says the properties are
// conveniences over. No framework, so the check measures the port's code and not this Mac's MediaPlayer -
// whose MPMediaItem declares albumTrackNumber already, so a category compiled against it would be
// measuring the host and would look like a clobber.
#import <Foundation/Foundation.h>

// The framework spells the identifier type as a typedef over NSNumber; the stand-in must too,
// or the generated getters do not compile off-target.
typedef NSNumber *MPMediaEntityPersistentID;

@interface MPMediaItem : NSObject
- (id)valueForProperty:(NSString *)property;
@end

@interface MPMediaItem (Charon70)
@property (nonatomic, readonly) NSUInteger albumTrackNumber;
@property (nonatomic, readonly) NSUInteger discNumber;
@end
