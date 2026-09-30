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

// The artwork class, as the release declares it, so the port's subclass has something to override and
// the check can see the override happen. The release's own imageWithSize: answers nil here, which is
// what makes the override observable rather than accidental.
@class UIImage;

@interface MPMediaItemArtwork : NSObject
- (instancetype)initWithImage:(id)image;
- (UIImage *)imageWithSize:(CGSize)size;
- (CGRect)bounds;
@end

@interface MPMediaItemArtwork (Charon100)
- (instancetype)initWithBoundsSize:(CGSize)boundsSize requestHandler:(UIImage *(^)(CGSize size))requestHandler;
@end

// The 9.0 command event's two types, and the base the port carries it over, so the check can compile
// the port's own source for a class the release does not have.
typedef NSUInteger MPChangeLanguageOptionSetting;
// The 8.0 repeat and shuffle events' types, spelled with the cases MPRemoteControlTypes.h gives them:
// MPRepeatTypeOff/One/All and MPShuffleTypeOff/Items/Collections, neither of which has an "unknown"
// case, so a stand-in that added one would let the port's own source compile against a type the SDK does
// not declare and the check would measure that instead of the port.
typedef NSInteger MPRepeatType;
enum { MPRepeatTypeOff = 0, MPRepeatTypeOne = 1, MPRepeatTypeAll = 2 };
typedef NSInteger MPShuffleType;
enum { MPShuffleTypeOff = 0, MPShuffleTypeItems = 1, MPShuffleTypeCollections = 2 };
@interface MPNowPlayingInfoLanguageOption : NSObject
@property (nonatomic, readonly) BOOL isAutomaticLegibleLanguageOption;
@end
@interface MPRemoteCommand : NSObject
@end
@interface MPRemoteCommandEvent : NSObject
- (instancetype)initWithCommand:(MPRemoteCommand *)command;
@property (nonatomic, strong, readonly) MPRemoteCommand *command;
@property (nonatomic, assign, readonly) NSTimeInterval timestamp;
@end
