// CharonUIKitProtocols.h - the UIKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <UIKit/UIKit.h> for that body, and
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
#import "CharonTraits17.h"

@protocol NSCollectionLayoutContainer;

@protocol NSCollectionLayoutEnvironment;

@protocol NSCollectionLayoutVisibleItem;

@protocol NSLayoutManagerDelegate;

@protocol NSTextAttachmentContainer;

@protocol NSTextAttachmentLayout;

@protocol NSTextContentManagerDelegate;

@protocol NSTextContentStorageDelegate;

@protocol NSTextElementProvider;

@protocol NSTextLayoutManagerDelegate;

@protocol NSTextLayoutOrientationProvider;

@protocol NSTextLocation;

@protocol NSTextSelectionDataSource;

@protocol NSTextStorageDelegate;

@protocol NSTextStorageObserving;

@protocol NSTextViewportLayoutControllerDelegate;

@protocol UIAccessibilityContainerDataTable;

@protocol UIAccessibilityContainerDataTableCell;

@protocol UIAccessibilityContentSizeCategoryImageAdjusting;

@protocol UIAccessibilityReadingContent;

@protocol UIActivityItemSource;

@protocol UIActivityItemsConfigurationProviding;

@protocol UIActivityItemsConfigurationReading;

@protocol UIAdaptivePresentationControllerDelegate;

@protocol UIAppearance;

@protocol UIApplicationDelegate;

@protocol UICGFloatTraitDefinition;

@protocol UICalendarSelectionMultiDateDelegate;

@protocol UICalendarSelectionSingleDateDelegate;

@class UICalendarSelectionWeekOfYear;
API_AVAILABLE(ios(18.0))
@protocol UICalendarSelectionWeekOfYearDelegate <NSObject>
- (void)weekOfYearSelection:(UICalendarSelectionWeekOfYear * _Nonnull)selection didSelectWeekOfYear:(NSDateComponents * _Nullable)weekOfYearComponents;
@optional
- (BOOL)weekOfYearSelection:(UICalendarSelectionWeekOfYear * _Nonnull)selection canSelectWeekOfYear:(NSDateComponents * _Nullable)weekOfYearComponents;
@end

@protocol UICalendarViewDelegate;

@protocol UICollectionViewDataSource;

@protocol UICollectionViewDataSourcePrefetching;

@protocol UICollectionViewDelegate;

@protocol UICollectionViewDragDelegate;

@protocol UICollectionViewDropCoordinator;

@protocol UICollectionViewDropDelegate;

@protocol UICollectionViewDropItem;

@protocol UICollectionViewDropPlaceholderContext;

@protocol UIColorPickerViewControllerDelegate;

@protocol UIConfigurationState;

@protocol UIContentConfiguration;

@protocol UIContentContainer;

@protocol UIContentSizeCategoryAdjusting;

@protocol UIContentView;

@protocol UIContextMenuInteractionAnimating;

@protocol UIContextMenuInteractionCommitAnimating;

@protocol UIContextMenuInteractionDelegate;

@protocol UIDataSourceTranslating;

@protocol UIDocumentBrowserViewControllerDelegate;

@protocol UIDocumentMenuDelegate;

@protocol UIDocumentPickerDelegate;

@protocol UIDragAnimating;

@protocol UIDragDropSession;

@protocol UIDragInteractionDelegate;

@protocol UIDragSession;

@protocol UIDropInteractionDelegate;

@protocol UIDropSession;

@protocol UIDynamicItem;

@protocol UIEditMenuInteractionAnimating;

@protocol UIEditMenuInteractionDelegate;

@protocol UIFindInteractionDelegate;

@protocol UIFocusAnimationContext;

@protocol UIFocusDebuggerOutput;

@protocol UIFocusEnvironment;

@protocol UIFocusItem;

@protocol UIFocusItemContainer;

@protocol UIFocusItemScrollableContainer;

@protocol UIFontPickerViewControllerDelegate;

@protocol UIGestureRecognizerDelegate;

@protocol UIGuidedAccessRestrictionDelegate;

@protocol UIIndirectScribbleInteractionDelegate;

@protocol UIInteraction;

@protocol UIItemProviderPresentationSizeProviding;

@protocol UILargeContentViewerInteractionDelegate;

@protocol UILargeContentViewerItem;

@protocol UILayoutSupport;

typedef enum UILetterformAwareSizingRule UILetterformAwareSizingRule;
API_AVAILABLE(ios(17.0))
@protocol UILetterformAwareAdjusting <NSObject>
@property (nonatomic, readwrite, assign, unsafe_unretained) UILetterformAwareSizingRule sizingRule;
@end

API_AVAILABLE(ios(17.0))
@protocol UILookToDictateCapable <NSObject>
@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isLookToDictateEnabled) BOOL lookToDictateEnabled;
@end

@protocol UIMenuBuilder;

@protocol UIMenuLeaf;

@protocol UIMutableTraits;

@protocol UINSIntegerTraitDefinition;

@protocol UINavigationControllerDelegate;

@protocol UINavigationItemRenameDelegate;

@protocol UIObjectTraitDefinition;

@class UIPageControlProgress;
API_AVAILABLE(ios(17.0))
@protocol UIPageControlProgressDelegate <NSObject>
@optional
- (float)pageControlProgress:(UIPageControlProgress * _Nonnull)progress initialProgressForPage:(NSInteger)page;
- (void)pageControlProgressVisibilityDidChange:(UIPageControlProgress * _Nonnull)progress;
@end

@class UIPageControlTimerProgress;
API_AVAILABLE(ios(17.0))
@protocol UIPageControlTimerProgressDelegate <UIPageControlProgressDelegate>
@optional
- (void)pageControlTimerProgressDidChange:(UIPageControlTimerProgress * _Nonnull)progress;
- (BOOL)pageControlTimerProgress:(UIPageControlTimerProgress * _Nonnull)progress shouldAdvanceToPage:(NSInteger)page;
@end

@protocol UIPageViewControllerDelegate;

@protocol UIPasteConfigurationSupporting;

@protocol UIPencilInteractionDelegate;

@protocol UIPickerViewAccessibilityDelegate;

@protocol UIPointerInteractionAnimating;

@protocol UIPointerInteractionDelegate;

@protocol UIPopoverControllerDelegate;

@protocol UIPopoverPresentationControllerDelegate;

@protocol UIPopoverPresentationControllerSourceItem;

@protocol UIPreviewActionItem;

@protocol UIPreviewInteractionDelegate;

@protocol UIPrintInteractionControllerDelegate;

@protocol UIPrinterPickerControllerDelegate;

@protocol UIResponderStandardEditActions;

@protocol UISceneDelegate;

@protocol UIScribbleInteractionDelegate;

@protocol UIScrollViewAccessibilityDelegate;

@protocol UIScrollViewDelegate;

@protocol UISearchBarDelegate;

@protocol UISearchControllerDelegate;

@protocol UISearchResultsUpdating;

@protocol UISearchSuggestion;

@protocol UISearchTextFieldDelegate;

@class UIResolvedShape;
@class UIShapeResolutionContext;
API_AVAILABLE(ios(17.0))
@protocol UIShapeProvider <NSObject>
- (UIResolvedShape * _Nonnull)resolvedShapeInContext:(UIShapeResolutionContext * _Nonnull)context;
@end

@protocol UISheetPresentationControllerDelegate;

@protocol UISheetPresentationControllerDetentResolutionContext;

@protocol UISplitViewControllerDelegate;

@protocol UISpringLoadedInteractionBehavior;

@protocol UISpringLoadedInteractionContext;

@protocol UISpringLoadedInteractionEffect;

@protocol UISpringLoadedInteractionSupporting;

@protocol UITabBarControllerDelegate;

API_AVAILABLE(ios(18.0))
@protocol UITabBarControllerSidebarAnimating <NSObject>
- (void)addAnimations:(void (^ _Nonnull)(void))animations;
- (void)addCompletion:(void (^ _Nonnull)(void))completion;
@end

@class UITab;
@class UITabBarControllerSidebar;
@class UITabGroup;
@class UITabSidebarItem;
@class UITabSidebarItemRequest;
API_AVAILABLE(ios(18.0))
@protocol UITabBarControllerSidebarDelegate <NSObject>
@optional
- (void)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebarVisibilityWillChange:(UITabBarControllerSidebar * _Nonnull)sidebar animator:(id<UITabBarControllerSidebarAnimating>  _Nonnull)animator;
- (UITabSidebarItem * _Nonnull)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar itemForRequest:(UITabSidebarItemRequest * _Nonnull)request;
- (void)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar updateItem:(UITabSidebarItem * _Nonnull)item;
- (void)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar willBeginDisplayingTab:( UITab * _Nonnull)tab;
- (void)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar didEndDisplayingTab:( UITab * _Nonnull)tab;
- (UISwipeActionsConfiguration * _Nullable)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar leadingSwipeActionsConfigurationForTab:( UITab * _Nonnull)tab;
- (UISwipeActionsConfiguration * _Nullable)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar trailingSwipeActionsConfigurationForTab:( UITab * _Nonnull)tab;
- (UIContextMenuConfiguration * _Nullable)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar contextMenuConfigurationForTab:( UITab * _Nonnull)tab;
- (NSArray<UIDragItem *> * _Nonnull)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar itemsForBeginningDragSession:(id<UIDragSession>  _Nonnull)dragSession tab:(UITab * _Nonnull)tab;
- (NSArray<UIDragItem *> * _Nonnull)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar itemsForAddingToDragSession:(id<UIDragSession>  _Nonnull)dragSession tab:(UITab * _Nonnull)tab;
- (UIDropOperation)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar sidebarAction:(UIAction * _Nonnull)sidebarAction group:(UITabGroup * _Nonnull)group operationForAcceptingItemsFromDropSession:(id<UIDropSession>  _Nonnull)session;
- (void)tabBarController:(UITabBarController * _Nonnull)tabBarController sidebar:(UITabBarControllerSidebar * _Nonnull)sidebar sidebarAction:(UIAction * _Nonnull)sidebarAction group:(UITabGroup * _Nonnull)group acceptItemsFromDropSession:(id<UIDropSession>  _Nonnull)session;
@end

@protocol UITableViewDelegate;

@protocol UITableViewDragDelegate;

@protocol UITableViewDropCoordinator;

@protocol UITableViewDropDelegate;

@protocol UITableViewDropItem;

@protocol UITableViewDropPlaceholderContext;

API_AVAILABLE(ios(17.0))
@protocol UITextCursorView <UICoordinateSpace>
@property (nonatomic, readwrite, assign, unsafe_unretained, getter=isBlinking) BOOL blinking;
- (void)resetBlinkAnimation;
@end

@protocol UITextDocumentProxy;

@protocol UITextDragDelegate;

@protocol UITextDragRequest;

@protocol UITextDraggable;

@protocol UITextDropDelegate;

@protocol UITextDropRequest;

@protocol UITextDroppable;

@protocol UITextFieldDelegate;

@protocol UITextFormattingCoordinatorDelegate;

@class UITextFormattingViewController;
@class UITextFormattingViewControllerChangeValue;
API_AVAILABLE(ios(18.0))
@protocol UITextFormattingViewControllerDelegate <NSObject>
- (void)textFormattingViewController:(UITextFormattingViewController * _Nonnull)viewController didChangeValue:(UITextFormattingViewControllerChangeValue * _Nonnull)changeValue;
@optional
- (BOOL)textFormattingViewController:(UITextFormattingViewController * _Nonnull)viewController shouldPresentFontPicker:(UIFontPickerViewController * _Nonnull)fontPicker;
- (BOOL)textFormattingViewController:(UITextFormattingViewController * _Nonnull)viewController shouldPresentColorPicker:(UIColorPickerViewController * _Nonnull)colorPicker;
- (void)textFormattingDidFinish:(UITextFormattingViewController * _Nonnull)viewController;
@end

@protocol UITextInput;

@protocol UITextInputDelegate;

@protocol UITextInputTraits;

@protocol UITextInteractionDelegate;

@protocol UITextPasteConfigurationSupporting;

@protocol UITextPasteDelegate;

@protocol UITextPasteItem;

@protocol UITextSearchAggregator;

@protocol UITextSearching;

@class UITextSelectionDisplayInteraction;
API_AVAILABLE(ios(17.0))
@protocol UITextSelectionDisplayInteractionDelegate <NSObject>
@optional
- (UIView * _Nullable)selectionContainerViewBelowTextForSelectionDisplayInteraction:(UITextSelectionDisplayInteraction * _Nonnull)interaction;
@end

API_AVAILABLE(ios(17.0))
@protocol UITextSelectionHandleView <UICoordinateSpace>
@property (nonatomic, readwrite, assign, unsafe_unretained) NSDirectionalRectEdge direction;
@property (nonatomic, readonly, getter=isVertical) BOOL vertical;
@property (nonatomic, readwrite, strong) UIBezierPath * _Nullable customShape;
- (CGRect)preferredFrameForRect:(CGRect)rect;
@end

API_AVAILABLE(ios(17.0))
@protocol UITextSelectionHighlightView <UICoordinateSpace>
@property (nonatomic, readwrite, strong) NSArray<UITextSelectionRect *> * _Nonnull selectionRects;
@end

@protocol UITextViewDelegate;

@protocol UIToolTipInteractionDelegate;

@protocol UITraitChangeObservable;

@protocol UITraitChangeRegistration;

@protocol UITraitEnvironment;

@protocol UITraitOverrides;

@protocol UIUserActivityRestoring;

@protocol UIViewControllerAnimatedTransitioning;

@protocol UIViewControllerContextTransitioning;

@protocol UIViewControllerInteractiveTransitioning;

@protocol UIViewControllerPreviewing;

@protocol UIViewControllerPreviewingDelegate;

@protocol UIViewControllerTransitionCoordinator;

@protocol UIViewControllerTransitionCoordinatorContext;

@protocol UIViewControllerTransitioningDelegate;

@protocol UIWindowSceneDelegate;

@class UIWritingToolsCoordinator;
@class UIWritingToolsCoordinatorAnimationParameters;
@class UIWritingToolsCoordinatorContext;
typedef enum UIWritingToolsCoordinatorContextScope UIWritingToolsCoordinatorContextScope;
typedef enum UIWritingToolsCoordinatorState UIWritingToolsCoordinatorState;
typedef enum UIWritingToolsCoordinatorTextAnimation UIWritingToolsCoordinatorTextAnimation;
typedef enum UIWritingToolsCoordinatorTextReplacementReason UIWritingToolsCoordinatorTextReplacementReason;
API_AVAILABLE(ios(18.2))
@protocol UIWritingToolsCoordinatorDelegate <NSObject>
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsContextsForScope:(UIWritingToolsCoordinatorContextScope)scope completion:(void (^ _Nonnull)(NSArray<UIWritingToolsCoordinatorContext *> * _Nonnull))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator replaceRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context proposedText:(NSAttributedString * _Nonnull)replacementText reason:(UIWritingToolsCoordinatorTextReplacementReason)reason animationParameters:(UIWritingToolsCoordinatorAnimationParameters * _Nullable)animationParameters completion:(void (^ _Nonnull)(NSAttributedString * _Nullable))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator selectRanges:(NSArray<NSValue *> * _Nonnull)ranges inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(void))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsBoundingBezierPathsForRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(NSArray<UIBezierPath *> * _Nonnull))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsUnderlinePathsForRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(NSArray<UIBezierPath *> * _Nonnull))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator prepareForTextAnimation:(UIWritingToolsCoordinatorTextAnimation)textAnimation forRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(void))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsPreviewForTextAnimation:(UIWritingToolsCoordinatorTextAnimation)textAnimation ofRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(UITargetedPreview * _Nullable))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator finishTextAnimation:(UIWritingToolsCoordinatorTextAnimation)textAnimation forRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(void))completion;
@optional
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsSingleContainerSubrangesOfRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(NSArray<NSValue *> * _Nonnull))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsDecorationContainerViewForRange:(NSRange)range inContext:(UIWritingToolsCoordinatorContext * _Nonnull)context completion:(void (^ _Nonnull)(UIView * _Nonnull))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator willChangeToState:(UIWritingToolsCoordinatorState)newState completion:(void (^ _Nonnull)(void))completion;
- (void)writingToolsCoordinator:(UIWritingToolsCoordinator * _Nonnull)writingToolsCoordinator requestsRangeInContextWithIdentifierForPoint:(CGPoint)point completion:(void (^ _Nonnull)(NSRange, NSUUID * _Nonnull))completion;
@end
