#import <UIKit/UIKit.h>

// The objects that answer the drop protocols, shared with the file that builds the view side of a
// drop, the way CharonDragSession.h is shared. The protocols are in the header; these are the
// objects that answer them, and the release has none because it has no drop.
@interface CharonCollectionDropItem : NSObject <UICollectionViewDropItem>
@property (nonatomic, strong) UIDragItem *item;
@property (nonatomic, strong) NSIndexPath *source;
@property (nonatomic, assign) CGSize size;
@end

@interface CharonTableDropItem : NSObject <UITableViewDropItem>
@property (nonatomic, strong) UIDragItem *item;
@property (nonatomic, strong) NSIndexPath *source;
@property (nonatomic, assign) CGSize size;
@end
