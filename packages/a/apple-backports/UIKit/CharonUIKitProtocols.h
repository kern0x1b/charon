// CharonUIKitProtocols.h — the UIKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// This file has a forward-declared protocol in it, so it imports <UIKit/UIKit.h> for that body, and
//
// Each of those four is GUARDED on __has_include, keyed on the header it is declared in -
// UITabBarControllerSidebar.h for the two sidebar protocols, UITextFormattingViewController.h for the
// formatting delegate, UICalendarSelectionWeekOfYear.h for the calendar one - for the same reason the
// other 89 entries in this file are forward declarations rather than bodies: on an SDK that ships one of
// these names, that SDK's own declaration is the one to use, and a transcription would be a second
// declaration of a name that already exists.  Three guards and not one, because a single guard keyed on
// UITab.h would let UITabBarControllerSidebar.h through on an SDK that has UITab and not the sidebar -
// this package keys a guard on the header a name actually lives in, which is what CharonUIKit26.h,
// CharonCMTag26.h and CharonUIKit18.h do for the classes they declare, each on the header 26.2 puts the
// name in.  All three are OPEN on the 16.4 SDK this package compiles against, which has
// none of the three headers, which is why the generated UIKitBackportsProtocols18.0.m still sees the four
// bodies: measured by tests/addon/protocol-sources.sh, 57 of 57 protocol sources compile.
// THE FOUR ARE BODIES, not forward declarations, and that is the difference the compiler
// makes: tests/addon/protocol-sources.sh says it plainly - "a forward declaration is correct when the
// SDK supplies the body and a compile error when it does not: error: @protocol is using a forward
// protocol declaration".  No SDK this package compiles against declares these four - they are
// 18.0 - so a forward declaration here would leave UIKitBackportsProtocols18.0.m, the source
// modules/apple/backports.lua writes for the band, naming a protocol with no metadata, and it would
// not compile.  They are transcribed from the SDK that does declare them, the host's own UIKit under
// Mac Catalyst (macOS 27.0), member for member and section for section, and the registry rows
// name the same source.  Every other protocol in this file is a forward declaration because the
// 16.4 SDK declares it.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
#import "CharonTraits17.h"
// CharonUIKit18.h for the four 18.0 protocols at the end of this file: their signatures name UITab,
// UITabGroup, UITabSidebarItem, UITabBarControllerSidebar, UITextFormattingViewController and
// UICalendarSelectionWeekOfYear, all of which that header declares.
#import "CharonUIKit18.h"

@protocol NSCollectionLayoutContainer;

@protocol NSCollectionLayoutEnvironment;

@protocol NSCollectionLayoutVisibleItem;

@protocol NSTextElementProvider;

@protocol NSTextLocation;

@protocol NSTextStorageObserving;

@protocol UIActivityItemsConfigurationReading;

@protocol UIAdaptivePresentationControllerDelegate;

// --- The last of the four.  Its one signature names UICalendarSelectionWeekOfYear, which CharonUIKit18.h
// --- above declares, like the sidebar protocols'.

#if !__has_include(<UIKit/UICalendarSelectionWeekOfYear.h>)

// What a week-of-year calendar selection tells its delegate when the user picks one.
@protocol UICalendarSelectionWeekOfYearDelegate <NSObject>
- (void)weekOfYearSelection:(UICalendarSelectionWeekOfYear *)selection didSelectWeekOfYear:(NSDateComponents *)weekOfYearComponents;
@end

#endif   // !__has_include(<UIKit/UICalendarSelectionWeekOfYear.h>)

@protocol UICGFloatTraitDefinition;

@protocol UICollectionViewDataSourcePrefetching;

@protocol UICollectionViewDragDelegate;

@protocol UICollectionViewDropCoordinator;

@protocol UICollectionViewDropDelegate;

@protocol UICollectionViewDropItem;

@protocol UICollectionViewDropPlaceholderContext;

@protocol UIColorPickerViewControllerDelegate;

@protocol UIConfigurationState;

@protocol UIContentConfiguration;

@protocol UIContentContainer;

@protocol UIContentView;

@protocol UIContextMenuInteractionAnimating;

@protocol UIContextMenuInteractionCommitAnimating;

@protocol UIContextMenuInteractionDelegate;

@protocol UICoordinateSpace;

@protocol UIDocumentBrowserViewControllerDelegate;

@protocol UIDocumentMenuDelegate;

@protocol UIDocumentPickerDelegate;

@protocol UIDragAnimating;

@protocol UIDragInteractionDelegate;

@protocol UIDragSession;

@protocol UIDropInteractionDelegate;

@protocol UIDropSession;

@protocol UIInteraction;

@protocol UILayoutSupport;

@protocol UIMenuLeaf;

@protocol UIMutableTraits;

@protocol UINSIntegerTraitDefinition;

@protocol UIObjectTraitDefinition;

@protocol UIPopoverPresentationControllerDelegate;

@protocol UIPreviewActionItem;

@protocol UISceneDelegate;

@protocol UISearchControllerDelegate;

@protocol UISearchResultsUpdating;

@protocol UISheetPresentationControllerDelegate;

@protocol UISheetPresentationControllerDetentResolutionContext;

// --- The two sidebar protocols of UIKit's 18.0 band, transcribed with their members because no SDK this
// --- package compiles against declares them.  Where a signature names an 18.0 class, that class is
// --- declared by CharonUIKit18.h, imported above.  Each keeps the SDK's own @optional or @required split
// --- and its own availability annotations, and nothing is added that 26.2 does not declare.

#if !__has_include(<UIKit/UITabBarControllerSidebar.h>)

// The animator a sidebar transition is handed: the panel adds its own animations and its completion.
@protocol UITabBarControllerSidebarAnimating <NSObject>
- (void)addAnimations:(void (^)(void))animations;
- (void)addCompletion:(void (^)(void))completion;
@end

// What the sidebar asks its delegate: which item a request becomes, what to show for a tab, the swipe
// and context menus of one, the drag and drop of one, and the two availability callbacks.  The 27.0
// members carry the SDK's own annotations, as the protocol spans releases.
@protocol UITabBarControllerSidebarDelegate <NSObject>
@optional
- (void)tabBarController:(UITabBarController *)tabBarController sidebarAvailabilityDidChange:(UITabBarControllerSidebar *)sidebar API_AVAILABLE(ios(27.0));
- (void)tabBarController:(UITabBarController *)tabBarController sidebarVisibilityWillChange:(UITabBarControllerSidebar *)sidebar animator:(id<UITabBarControllerSidebarAnimating>)animator;
- (UITabSidebarItem *)tabBarController:(UITabBarController *)tabBarController
                               sidebar:(UITabBarControllerSidebar *)sidebar
                        itemForRequest:(UITabSidebarItemRequest *)request;
- (void)tabBarController:(UITabBarController *)tabBarController
                 sidebar:(UITabBarControllerSidebar *)sidebar
              updateItem:(UITabSidebarItem *)item;
- (void)tabBarController:(UITabBarController *)tabBarController sidebar:(UITabBarControllerSidebar *)sidebar willBeginDisplayingTab:(__kindof UITab *)tab;
- (void)tabBarController:(UITabBarController *)tabBarController sidebar:(UITabBarControllerSidebar *)sidebar didEndDisplayingTab:(__kindof UITab *)tab;
- (UISwipeActionsConfiguration *)tabBarController:(UITabBarController *)tabBarController
                                          sidebar:(UITabBarControllerSidebar *)sidebar
                   leadingSwipeActionsConfigurationForTab:(__kindof UITab *)tab;
- (UISwipeActionsConfiguration *)tabBarController:(UITabBarController *)tabBarController
                                          sidebar:(UITabBarControllerSidebar *)sidebar
                   trailingSwipeActionsConfigurationForTab:(__kindof UITab *)tab;
- (UIContextMenuConfiguration *)tabBarController:(UITabBarController *)tabBarController
                                         sidebar:(UITabBarControllerSidebar *)sidebar
                          contextMenuConfigurationForTab:(__kindof UITab *)tab;
- (NSArray<UIDragItem *> *)tabBarController:(UITabBarController *)tabBarController
                                    sidebar:(UITabBarControllerSidebar *)sidebar
               itemsForBeginningDragSession:(id<UIDragSession>)dragSession
                                        tab:(UITab *)tab API_AVAILABLE(ios(18.4));
- (NSArray<UIDragItem *> *)tabBarController:(UITabBarController *)tabBarController
                                    sidebar:(UITabBarControllerSidebar *)sidebar
                itemsForAddingToDragSession:(id<UIDragSession>)dragSession tab:(UITab *)tab API_AVAILABLE(ios(18.4));
- (UIDropOperation)tabBarController:(UITabBarController *)tabBarController
                            sidebar:(UITabBarControllerSidebar *)sidebar
                             sidebarAction:(UIAction *)sidebarAction
                                    group:(UITabGroup *)group
            operationForAcceptingItemsFromDropSession:(id<UIDropSession>)session API_AVAILABLE(ios(18.4));
- (void)tabBarController:(UITabBarController *)tabBarController
                 sidebar:(UITabBarControllerSidebar *)sidebar
           sidebarAction:(UIAction *)sidebarAction
                   group:(UITabGroup *)group
acceptItemsFromDropSession:(id<UIDropSession>)session API_AVAILABLE(ios(18.4));
@end

#endif   // !__has_include(<UIKit/UITabBarControllerSidebar.h>)

@protocol UITableViewDataSourcePrefetching;

@protocol UITableViewDragDelegate;

@protocol UITableViewDropCoordinator;

@protocol UITableViewDropDelegate;

@protocol UITableViewDropItem;

@protocol UITableViewDropPlaceholderContext;

@protocol UITextDragDelegate;

@protocol UITextDragRequest;

@protocol UITextDraggable;

@protocol UITextDropDelegate;

@protocol UITextDropRequest;

@protocol UITextDroppable;

// --- The formatting panel's delegate, likewise transcribed.  Its signatures name two 18.0 classes of
// --- CharonUIKit18.h, which is why that header is imported above.

#if !__has_include(<UIKit/UITextFormattingViewController.h>)

// What the formatting panel tells its delegate, and the three questions it may ask first.
@protocol UITextFormattingViewControllerDelegate <NSObject>
- (void)textFormattingViewController:(UITextFormattingViewController *)viewController didChangeValue:(UITextFormattingViewControllerChangeValue *)changeValue;
@optional
- (BOOL)textFormattingViewController:(UITextFormattingViewController *)viewController shouldPresentFontPicker:(UIFontPickerViewController *)fontPicker;
- (BOOL)textFormattingViewController:(UITextFormattingViewController *)viewController shouldPresentColorPicker:(UIColorPickerViewController *)colorPicker;
- (void)textFormattingDidFinish:(UITextFormattingViewController *)viewController;
@end

#endif   // !__has_include(<UIKit/UITextFormattingViewController.h>)

@protocol UITextInputTraits;

@protocol UITextInteractionDelegate;

@protocol UITraitChangeObservable;

@protocol UITraitChangeRegistration;

@protocol UITraitDefinition;

@protocol UITraitOverrides;

@protocol UIViewAnimating;

@protocol UIViewControllerAnimatedTransitioning;

@protocol UIViewControllerContextTransitioning;

@protocol UIViewControllerInteractiveTransitioning;

@protocol UIViewControllerTransitionCoordinator;

@protocol UIViewControllerTransitionCoordinatorContext;

@protocol UIViewControllerTransitioningDelegate;

@protocol UIViewImplicitlyAnimating;

@protocol UIWindowSceneDelegate;
