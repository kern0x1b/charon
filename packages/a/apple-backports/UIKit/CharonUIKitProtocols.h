// CharonUIKitProtocols.h — the UIKit protocols the SDK this package compiles against does not declare,
// transcribed by tools/transcribe-protocols.py from the SDK that declares them: the base list, each
// member with its kind, return type and parameter types, @required and @optional as sections, and
// API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the release it arrived in.
// Facts only, and nothing written for a protocol or a member the generator refused by name below.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(13.0))
@protocol NSCollectionLayoutContainer <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol NSCollectionLayoutEnvironment <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol NSCollectionLayoutVisibleItem <NSObject, UIDynamicItem>
@end

API_AVAILABLE(ios(13.0))
@protocol UIActivityItemsConfigurationReading <NSObject>
- ()activityItemsConfigurationSupportsInteraction:(UIActivityItemsConfigurationInteraction  _Nonnull)interaction;
- ()activityItemsConfigurationMetadataForKey:(UIActivityItemsConfigurationMetadataKey  _Nonnull)key;
- ()activityItemsConfigurationMetadataForItemAtIndex:(NSInteger)index key:(UIActivityItemsConfigurationMetadataKey  _Nonnull)key;
- ()activityItemsConfigurationPreviewForItemAtIndex:(NSInteger)index intent:(UIActivityItemsConfigurationPreviewIntent  _Nonnull)intent suggestedSize:(CGSize)suggestedSize;
- ()itemProvidersForActivityItemsConfiguration;
- ()applicationActivitiesForActivityItemsConfiguration;
@end

API_AVAILABLE(ios(8.0))
@protocol UIAdaptivePresentationControllerDelegate <NSObject>
- ()adaptivePresentationStyleForPresentationController:(UIPresentationController * _Nonnull)controller;
- ()adaptivePresentationStyleForPresentationController:(UIPresentationController * _Nonnull)controller traitCollection:(UITraitCollection * _Nonnull)traitCollection;
- ()presentationController:(UIPresentationController * _Nonnull)presentationController prepareAdaptivePresentationController:(UIPresentationController * _Nonnull)adaptivePresentationController;
- ()presentationController:(UIPresentationController * _Nonnull)controller viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style;
- ()presentationController:(UIPresentationController * _Nonnull)presentationController willPresentWithAdaptiveStyle:(UIModalPresentationStyle)style transitionCoordinator:(id<UIViewControllerTransitionCoordinator>  _Nullable)transitionCoordinator;
- ()presentationControllerShouldDismiss:(UIPresentationController * _Nonnull)presentationController;
- ()presentationControllerWillDismiss:(UIPresentationController * _Nonnull)presentationController;
- ()presentationControllerDidDismiss:(UIPresentationController * _Nonnull)presentationController;
- ()presentationControllerDidAttemptToDismiss:(UIPresentationController * _Nonnull)presentationController;
@end

API_AVAILABLE(ios(14.0))
@protocol UIColorPickerViewControllerDelegate <NSObject>
- ()colorPickerViewControllerDidSelectColor:(UIColorPickerViewController * _Nonnull)viewController;
- ()colorPickerViewController:(UIColorPickerViewController * _Nonnull)viewController didSelectColor:(UIColor * _Nonnull)color continuously:(BOOL)continuously;
- ()colorPickerViewControllerDidFinish:(UIColorPickerViewController * _Nonnull)viewController;
@end

API_AVAILABLE(ios(14.0))
@protocol UIConfigurationState <NSObject>
@end

API_AVAILABLE(ios(14.0))
@protocol UIContentConfiguration <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UIContentContainer <NSObject>
@end

API_AVAILABLE(ios(14.0))
@protocol UIContentView <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UIContextMenuInteractionAnimating <NSObject>
- ()addAnimations:(void (^ _Nonnull)(void))animations;
- ()addCompletion:(void (^ _Nonnull)(void))completion;
- ()previewViewController;
@end

API_AVAILABLE(ios(13.0))
@protocol UIContextMenuInteractionCommitAnimating <UIContextMenuInteractionAnimating>
- ()preferredCommitStyle;
- ()setPreferredCommitStyle:(UIContextMenuInteractionCommitStyle)preferredCommitStyle;
@end

API_AVAILABLE(ios(13.0))
@protocol UIContextMenuInteractionDelegate <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UICoordinateSpace <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UIDocumentMenuDelegate <NSObject>
- ()documentMenu:(UIDocumentMenuViewController * _Nonnull)documentMenu didPickDocumentPicker:(UIDocumentPickerViewController * _Nonnull)documentPicker;
- ()documentMenuWasCancelled:(UIDocumentMenuViewController * _Nonnull)documentMenu;
@end

API_AVAILABLE(ios(8.0))
@protocol UIDocumentPickerDelegate <NSObject>
- ()documentPicker:(UIDocumentPickerViewController * _Nonnull)controller didPickDocumentsAtURLs:(NSArray<NSURL *> * _Nonnull)urls;
- ()documentPickerWasCancelled:(UIDocumentPickerViewController * _Nonnull)controller;
- ()documentPicker:(UIDocumentPickerViewController * _Nonnull)controller didPickDocumentAtURL:(NSURL * _Nonnull)url;
@end

API_AVAILABLE(ios(11.0))
@protocol UIDragDropSession <NSObject>
@end

API_AVAILABLE(ios(11.0))
@protocol UIDropSession <UIDragDropSession, NSProgressReporting>
@end

API_AVAILABLE(ios(11.0))
@protocol UIInteraction <NSObject>
- ()willMoveToView:(UIView * _Nullable)view;
- ()didMoveToView:(UIView * _Nullable)view;
- ()view;
@end

API_AVAILABLE(ios(7.0))
@protocol UILayoutSupport <NSObject>
- ()length;
- ()topAnchor;
- ()bottomAnchor;
- ()heightAnchor;
@end

API_AVAILABLE(ios(8.0))
@protocol UIPopoverPresentationControllerDelegate <UIAdaptivePresentationControllerDelegate>
- ()prepareForPopoverPresentation:(UIPopoverPresentationController * _Nonnull)popoverPresentationController;
- ()popoverPresentationControllerShouldDismissPopover:(UIPopoverPresentationController * _Nonnull)popoverPresentationController;
- ()popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController * _Nonnull)popoverPresentationController;
- ()popoverPresentationController:(UIPopoverPresentationController * _Nonnull)popoverPresentationController willRepositionPopoverToRect:(CGRect * _Nonnull)rect inView:(UIView * _Nonnull * _Nonnull)view;
@end

API_AVAILABLE(ios(9.0))
@protocol UIPreviewActionItem <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UISceneDelegate <NSObject>
@end

API_AVAILABLE(ios(8.0))
@protocol UISearchControllerDelegate <NSObject>
- ()willPresentSearchController:(UISearchController * _Nonnull)searchController;
- ()didPresentSearchController:(UISearchController * _Nonnull)searchController;
- ()willDismissSearchController:(UISearchController * _Nonnull)searchController;
- ()didDismissSearchController:(UISearchController * _Nonnull)searchController;
- ()presentSearchController:(UISearchController * _Nonnull)searchController;
- ()searchController:(UISearchController * _Nonnull)searchController willChangeToSearchBarPlacement:(UINavigationItemSearchBarPlacement)newPlacement;
- ()searchController:(UISearchController * _Nonnull)searchController didChangeFromSearchBarPlacement:(UINavigationItemSearchBarPlacement)previousPlacement;
@end

API_AVAILABLE(ios(8.0))
@protocol UISearchResultsUpdating <NSObject>
- ()updateSearchResultsForSearchController:(UISearchController * _Nonnull)searchController;
- ()updateSearchResultsForSearchController:(UISearchController * _Nonnull)searchController selectingSearchSuggestion:(id<UISearchSuggestion>  _Nonnull)searchSuggestion;
@end

API_AVAILABLE(ios(15.0))
@protocol UISheetPresentationControllerDelegate <UIAdaptivePresentationControllerDelegate>
- ()sheetPresentationControllerDidChangeSelectedDetentIdentifier:(UISheetPresentationController * _Nonnull)sheetPresentationController;
@end

API_AVAILABLE(ios(16.0))
@protocol UISheetPresentationControllerDetentResolutionContext <NSObject>
- ()containerTraitCollection;
- ()maximumDetentValue;
@end

API_AVAILABLE(ios(10.0))
@protocol UITextInputTraits <NSObject>
@end

API_AVAILABLE(ios(13.0))
@protocol UITextInteractionDelegate <NSObject>
- ()interactionShouldBegin:(UITextInteraction * _Nonnull)interaction atPoint:(CGPoint)point;
- ()interactionWillBegin:(UITextInteraction * _Nonnull)interaction;
- ()interactionDidEnd:(UITextInteraction * _Nonnull)interaction;
@end

API_AVAILABLE(ios(10.0))
@protocol UIViewAnimating <NSObject>
- ()startAnimation;
- ()startAnimationAfterDelay:(NSTimeInterval)delay;
- ()pauseAnimation;
- ()stopAnimation:(BOOL)withoutFinishing;
- ()finishAnimationAtPosition:(UIViewAnimatingPosition)finalPosition;
- ()state;
- ()isRunning;
- ()isReversed;
- ()setReversed:(BOOL)reversed;
- ()fractionComplete;
- ()setFractionComplete:(CGFloat)fractionComplete;
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerAnimatedTransitioning <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerContextTransitioning <NSObject>
- ()updateInteractiveTransition:(CGFloat)percentComplete;
- ()finishInteractiveTransition;
- ()cancelInteractiveTransition;
- ()pauseInteractiveTransition;
- ()completeTransition:(BOOL)didComplete;
- ()viewControllerForKey:(UITransitionContextViewControllerKey  _Nonnull)key;
- ()viewForKey:(UITransitionContextViewKey  _Nonnull)key;
- ()initialFrameForViewController:(UIViewController * _Nonnull)vc;
- ()finalFrameForViewController:(UIViewController * _Nonnull)vc;
- ()containerView;
- ()isAnimated;
- ()isInteractive;
- ()transitionWasCancelled;
- ()presentationStyle;
- ()targetTransform;
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerInteractiveTransitioning <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerTransitionCoordinator <UIViewControllerTransitionCoordinatorContext>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerTransitionCoordinatorContext <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol UIViewControllerTransitioningDelegate <NSObject>
@end

API_AVAILABLE(ios(10.0))
@protocol UIViewImplicitlyAnimating <UIViewAnimating>
- ()addAnimations:(void (^ _Nonnull)(void))animation delayFactor:(CGFloat)delayFactor;
- ()addAnimations:(void (^ _Nonnull)(void))animation;
- ()addCompletion:(void (^ _Nonnull)(UIViewAnimatingPosition))completion;
- ()continueAnimationWithTimingParameters:(id<UITimingCurveProvider>  _Nullable)parameters durationFactor:(CGFloat)durationFactor;
@end

API_AVAILABLE(ios(13.0))
@protocol UIWindowSceneDelegate <UISceneDelegate>
- ()windowScene:(UIWindowScene * _Nonnull)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>  _Nonnull)previousCoordinateSpace interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection * _Nonnull)previousTraitCollection;
- ()windowScene:(UIWindowScene * _Nonnull)windowScene didUpdateEffectiveGeometry:(UIWindowSceneGeometry * _Nonnull)previousEffectiveGeometry;
- ()windowScene:(UIWindowScene * _Nonnull)windowScene performActionForShortcutItem:(UIApplicationShortcutItem * _Nonnull)shortcutItem completionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
- ()windowScene:(UIWindowScene * _Nonnull)windowScene userDidAcceptCloudKitShareWithMetadata:(CKShareMetadata * _Nonnull)cloudKitShareMetadata;
- ()preferredWindowingControlStyleForScene:(UIWindowScene * _Nonnull)windowScene;
- ()window;
- ()setWindow:(UIWindow * _Nullable)window;
@end
