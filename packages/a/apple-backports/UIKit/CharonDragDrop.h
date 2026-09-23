#import <UIKit/UIKit.h>

// What UITableView and UICollectionView keep for their drag and drop properties. Each class's category
// is a file of its own, since UICollectionView arrives in 6.0 and UITableView is there from 2.0.
@interface CharonDragDropBox : NSObject {
@public
    __weak id dragDelegate;
    __weak id dropDelegate;
    BOOL didSetDragInteractionEnabled;
    BOOL dragInteractionEnabled;
}
@end

CharonDragDropBox *charon_drag_drop_box(id object);
BOOL charon_drag_interaction_enabled(id object);
void charon_set_drag_interaction_enabled(id object, BOOL enabled);
