// CharonUIKitProtocols.h — the UIKit protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(10.0))
@protocol UITextInputTraits <NSObject>
@end

API_AVAILABLE(ios(10.0))
@protocol UIViewAnimating <NSObject>
@end

API_AVAILABLE(ios(10.0))
@protocol UIViewImplicitlyAnimating <NSObject>
@end

API_AVAILABLE(ios(11.0))
@protocol UIDragDropSession <NSObject>
@end

API_AVAILABLE(ios(11.0))
@protocol UIDropSession <UIDragDropSession, NSProgressReporting>
- (NSProgress * _Nonnull)loadObjectsOfClass:(Class<NSItemProviderReading>  _Nonnull)aClass completion:(void (^ _Nonnull)(NSArray< id<NSItemProviderReading>> * _Nonnull))completion;
- (id<UIDragSession> _Nullable)localDragSession;
- (UIDropSessionProgressIndicatorStyle)progressIndicatorStyle;
- (void)setProgressIndicatorStyle:(UIDropSessionProgressIndicatorStyle)progressIndicatorStyle;
@property (readonly, )id<UIDragSession> _Nullable localDragSession;;
@property ()UIDropSessionProgressIndicatorStyle progressIndicatorStyle;;
@end

API_AVAILABLE(ios(11.0))
@protocol UIInteraction <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol NSCollectionLayoutContainer <NSObject>
- (CGSize)contentSize;
- (CGSize)effectiveContentSize;
- (NSDirectionalEdgeInsets)contentInsets;
- (NSDirectionalEdgeInsets)effectiveContentInsets;
@property (readonly, )CGSize contentSize;;
@property (readonly, )CGSize effectiveContentSize;;
@property (readonly, )NSDirectionalEdgeInsets contentInsets;;
@property (readonly, )NSDirectionalEdgeInsets effectiveContentInsets;;
@end

API_AVAILABLE(ios(13.0))
@protocol NSCollectionLayoutEnvironment <NSObject>
- (id<NSCollectionLayoutContainer> _Nonnull)container;
- (UITraitCollection * _Nonnull)traitCollection;
@property (readonly, )id<NSCollectionLayoutContainer> _Nonnull container;;
@property (readonly, )UITraitCollection * _Nonnull traitCollection;;
@end

API_AVAILABLE(ios(13.0))
@protocol NSCollectionLayoutVisibleItem <NSObject, UIDynamicItem>
- (CGFloat)alpha;
- (void)setAlpha:(CGFloat)alpha;
- (NSInteger)zIndex;
- (void)setZIndex:(NSInteger)zIndex;
- (BOOL)isHidden;
- (void)setHidden:(BOOL)hidden;
- (CGPoint)center;
- (void)setCenter:(CGPoint)center;
- (CGAffineTransform)transform;
- (void)setTransform:(CGAffineTransform)transform;
- (CATransform3D)transform3D;
- (void)setTransform3D:(CATransform3D)transform3D;
- (NSString * _Nonnull)name;
- (NSIndexPath * _Nonnull)indexPath;
- (CGRect)frame;
- (CGRect)bounds;
- (UICollectionElementCategory)representedElementCategory;
- (NSString * _Nullable)representedElementKind;
@property ()CGFloat alpha;;
@property ()NSInteger zIndex;;
@property ()BOOL hidden;;
@property ()CGPoint center;;
@property ()CGAffineTransform transform;;
@property ()CATransform3D transform3D;;
@property (readonly, )NSString * _Nonnull name;;
@property (readonly, )NSIndexPath * _Nonnull indexPath;;
@property (readonly, )CGRect frame;;
@property (readonly, )CGRect bounds;;
@property (readonly, )UICollectionElementCategory representedElementCategory;;
@property (readonly, )NSString * _Nullable representedElementKind;;
@end

API_AVAILABLE(ios(13.0))
@protocol UIActivityItemsConfigurationReading <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UIContextMenuInteractionAnimating <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UIContextMenuInteractionCommitAnimating <UIContextMenuInteractionAnimating>
- (UIContextMenuInteractionCommitStyle)preferredCommitStyle;
- (void)setPreferredCommitStyle:(UIContextMenuInteractionCommitStyle)preferredCommitStyle;
@property ()UIContextMenuInteractionCommitStyle preferredCommitStyle;;
@end

API_AVAILABLE(ios(13.0))
@protocol UIContextMenuInteractionDelegate <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UISceneDelegate <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UITextInteractionDelegate <NSObject>
- (BOOL)interactionShouldBegin:(UITextInteraction * _Nonnull)interaction atPoint:(CGPoint)point;
- (void)interactionWillBegin:(UITextInteraction * _Nonnull)interaction;
- (void)interactionDidEnd:(UITextInteraction * _Nonnull)interaction;
@end

API_AVAILABLE(ios(13.0))
@protocol UIWindowSceneDelegate <UISceneDelegate>
- (void)windowScene:(UIWindowScene * _Nonnull)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>  _Nonnull)previousCoordinateSpace interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection * _Nonnull)previousTraitCollection;
- (void)windowScene:(UIWindowScene * _Nonnull)windowScene didUpdateEffectiveGeometry:(UIWindowSceneGeometry * _Nonnull)previousEffectiveGeometry;
- (void)windowScene:(UIWindowScene * _Nonnull)windowScene performActionForShortcutItem:(UIApplicationShortcutItem * _Nonnull)shortcutItem completionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
- (void)windowScene:(UIWindowScene * _Nonnull)windowScene userDidAcceptCloudKitShareWithMetadata:(CKShareMetadata * _Nonnull)cloudKitShareMetadata;
- (UISceneWindowingControlStyle * _Nonnull)preferredWindowingControlStyleForScene:(UIWindowScene * _Nonnull)windowScene;
- (UIWindow * _Nullable)window;
- (void)setWindow:(UIWindow * _Nullable)window;
@property ()UIWindow * _Nullable window;;
@end

API_AVAILABLE(ios(14.0))
@protocol UIColorPickerViewControllerDelegate <NSObject>
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController * _Nonnull)viewController;
- (void)colorPickerViewController:(UIColorPickerViewController * _Nonnull)viewController didSelectColor:(UIColor * _Nonnull)color continuously:(BOOL)continuously;
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController * _Nonnull)viewController;
@end

API_AVAILABLE(ios(14.0))
@protocol UIConfigurationState <NSObject>
@end

API_AVAILABLE(ios(14.0))
@protocol UIContentConfiguration <NSObject, NSCopying>
@end

API_AVAILABLE(ios(14.0))
@protocol UIContentView <NSObject>
@end

API_AVAILABLE(ios(15.0))
@protocol UISheetPresentationControllerDelegate <UIAdaptivePresentationControllerDelegate>
- (void)sheetPresentationControllerDidChangeSelectedDetentIdentifier:(UISheetPresentationController * _Nonnull)sheetPresentationController;
@end

API_AVAILABLE(ios(16.0))
@protocol UIMenuLeaf <NSObject>
@end

API_AVAILABLE(ios(16.0))
@protocol UISheetPresentationControllerDetentResolutionContext <NSObject>
- (UITraitCollection * _Nonnull)containerTraitCollection;
- (CGFloat)maximumDetentValue;
@property (readonly, )UITraitCollection * _Nonnull containerTraitCollection;;
@property (readonly, )CGFloat maximumDetentValue;;
@end

API_AVAILABLE(ios(7.0))
@protocol UILayoutSupport <NSObject>
- (CGFloat)length;
- (API_AVAILABLE NSLayoutYAxisAnchor *)topAnchor;
- (API_AVAILABLE NSLayoutYAxisAnchor *)bottomAnchor;
- (API_AVAILABLE NSLayoutDimension *)heightAnchor;
@property (readonly, )CGFloat length;;
@property (readonly, )API_AVAILABLE NSLayoutYAxisAnchor * topAnchor;;
@property (readonly, )API_AVAILABLE NSLayoutYAxisAnchor * bottomAnchor;;
@property (readonly, )API_AVAILABLE NSLayoutDimension * heightAnchor;;
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerAnimatedTransitioning <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerContextTransitioning <NSObject>
- (void)updateInteractiveTransition:(CGFloat)percentComplete;
- (void)finishInteractiveTransition;
- (void)cancelInteractiveTransition;
- (void)pauseInteractiveTransition;
- (void)completeTransition:(BOOL)didComplete;
- ( UIViewController * _Nullable)viewControllerForKey:(UITransitionContextViewControllerKey  _Nonnull)key;
- ( UIView * _Nullable)viewForKey:(UITransitionContextViewKey  _Nonnull)key;
- (CGRect)initialFrameForViewController:(UIViewController * _Nonnull)vc;
- (CGRect)finalFrameForViewController:(UIViewController * _Nonnull)vc;
- (API_UNAVAILABLE UIView *)containerView;
- (BOOL)isAnimated;
- (BOOL)isInteractive;
- (BOOL)transitionWasCancelled;
- (UIModalPresentationStyle)presentationStyle;
- (CGAffineTransform)targetTransform;
@property (readonly, )API_UNAVAILABLE UIView * containerView;;
@property (readonly, )BOOL animated;;
@property (readonly, )BOOL interactive;;
@property (readonly, )BOOL transitionWasCancelled;;
@property (readonly, )UIModalPresentationStyle presentationStyle;;
@property (readonly, )CGAffineTransform targetTransform;;
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerInteractiveTransitioning <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerTransitionCoordinator <UIViewControllerTransitionCoordinatorContext>
- (BOOL)animateAlongsideTransition:(void (^ _Nullable)(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull))animation completion:(void (^ _Nullable)(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull))completion;
- (BOOL)animateAlongsideTransitionInView:(UIView * _Nullable)view animation:(void (^ _Nullable)(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull))animation completion:(void (^ _Nullable)(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull))completion;
- (void)notifyWhenInteractionEndsUsingBlock:(void (^ _Nonnull)(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull))handler;
- (void)notifyWhenInteractionChangesUsingBlock:(void (^ _Nonnull)(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull))handler;
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerTransitionCoordinatorContext <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerTransitioningDelegate <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UIAdaptivePresentationControllerDelegate <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UIContentContainer <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UICoordinateSpace <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UIDocumentMenuDelegate <NSObject>
- (void)documentMenu:(UIDocumentMenuViewController * _Nonnull)documentMenu didPickDocumentPicker:(UIDocumentPickerViewController * _Nonnull)documentPicker;
- (void)documentMenuWasCancelled:(UIDocumentMenuViewController * _Nonnull)documentMenu;
@end

API_AVAILABLE(ios(8.0))
@protocol UIDocumentPickerDelegate <NSObject>
- (void)documentPicker:(UIDocumentPickerViewController * _Nonnull)controller didPickDocumentsAtURLs:(NSArray<NSURL *> * _Nonnull)urls;
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController * _Nonnull)controller;
- (void)documentPicker:(UIDocumentPickerViewController * _Nonnull)controller didPickDocumentAtURL:(NSURL * _Nonnull)url;
@end

API_AVAILABLE(ios(8.0))
@protocol UIPopoverPresentationControllerDelegate <UIAdaptivePresentationControllerDelegate>
- (void)prepareForPopoverPresentation:(UIPopoverPresentationController * _Nonnull)popoverPresentationController;
- (BOOL)popoverPresentationControllerShouldDismissPopover:(UIPopoverPresentationController * _Nonnull)popoverPresentationController;
- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController * _Nonnull)popoverPresentationController;
- (void)popoverPresentationController:(UIPopoverPresentationController * _Nonnull)popoverPresentationController willRepositionPopoverToRect:(CGRect * _Nonnull)rect inView:(UIView * _Nonnull * _Nonnull)view;
@end

API_AVAILABLE(ios(8.0))
@protocol UISearchControllerDelegate <NSObject>
- (void)willPresentSearchController:(UISearchController * _Nonnull)searchController;
- (void)didPresentSearchController:(UISearchController * _Nonnull)searchController;
- (void)willDismissSearchController:(UISearchController * _Nonnull)searchController;
- (void)didDismissSearchController:(UISearchController * _Nonnull)searchController;
- (void)presentSearchController:(UISearchController * _Nonnull)searchController;
- (void)searchController:(UISearchController * _Nonnull)searchController willChangeToSearchBarPlacement:(UINavigationItemSearchBarPlacement)newPlacement;
- (void)searchController:(UISearchController * _Nonnull)searchController didChangeFromSearchBarPlacement:(UINavigationItemSearchBarPlacement)previousPlacement;
@end

API_AVAILABLE(ios(8.0))
@protocol UISearchResultsUpdating <NSObject>
- (void)updateSearchResultsForSearchController:(UISearchController * _Nonnull)searchController;
- (void)updateSearchResultsForSearchController:(UISearchController * _Nonnull)searchController selectingSearchSuggestion:(id<UISearchSuggestion>  _Nonnull)searchSuggestion;
@end

API_AVAILABLE(ios(9.0))
@protocol UIPreviewActionItem <NSObject>
@end
