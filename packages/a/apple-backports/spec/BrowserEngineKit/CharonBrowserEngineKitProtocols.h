// CharonBrowserEngineKitProtocols.h - the BrowserEngineKit protocols the generated protocol sources name, written by
// tools/transcribe-protocols.py. One the SDK this package compiles against already defines, or a
// header of this folder does, is forward-declared and its body comes from that import; any other is
// transcribed from the SDK that declares it: the base list, each member with its kind and types,
// @required and @optional as sections, and API_AVAILABLE(ios(<introduced>)). Facts only.
// Every protocol in this file is transcribed here, so it imports no framework header: their members name classes this header forward-declares. A file with a forward-declared protocol in it does import <BrowserEngineKit/BrowserEngineKit.h>, for that one body.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>
@protocol UIDragSession;
@protocol UIEditMenuInteractionAnimating;

@class BEAccessibilityTextMarker;
@class BEAccessibilityTextMarkerRange;
API_AVAILABLE(ios(18.2))
@protocol BEAccessibilityTextMarkerSupport <NSObject>
- (CGRect)accessibilityBoundsForTextMarkerRange:(BEAccessibilityTextMarkerRange * _Nonnull)range;
- (NSString * _Nullable)accessibilityContentForTextMarkerRange:(BEAccessibilityTextMarkerRange * _Nonnull)range;
- (BEAccessibilityTextMarkerRange * _Nullable)accessibilityTextMarkerRangeForCurrentSelection;
- (BEAccessibilityTextMarkerRange * _Nonnull)accessibilityTextMarkerRange;
- (BEAccessibilityTextMarker * _Nullable)accessibilityNextTextMarker:(BEAccessibilityTextMarker * _Nonnull)marker;
- (BEAccessibilityTextMarker * _Nullable)accessibilityPreviousTextMarker:(BEAccessibilityTextMarker * _Nonnull)marker;
- (BEAccessibilityTextMarker * _Nullable)accessibilityLineEndMarkerForMarker:(BEAccessibilityTextMarker * _Nonnull)marker;
- (BEAccessibilityTextMarker * _Nullable)accessibilityLineStartMarkerForMarker:(BEAccessibilityTextMarker * _Nonnull)marker;
- (BEAccessibilityTextMarker * _Nullable)accessibilityMarkerForPoint:(CGPoint)point;
- (BEAccessibilityTextMarker * _Nullable)accessibilityTextMarkerForPosition:(NSInteger)position;
- (BEAccessibilityTextMarkerRange * _Nullable)accessibilityTextMarkerRangeForRange:(NSRange)range;
- (NSRange)accessibilityRangeForTextMarkerRange:(BEAccessibilityTextMarkerRange * _Nonnull)range;
@end

@class BEDragInteraction;
@class UIDragItem;
API_AVAILABLE(ios(17.4))
@protocol BEDragInteractionDelegate <UIDragInteractionDelegate>
@optional
- (void)dragInteraction:(BEDragInteraction * _Nonnull)dragInteraction prepareDragSession:(id<UIDragSession>  _Nonnull)session completion:(BOOL (^ _Nonnull)(void))completion;
- (void)dragInteraction:(BEDragInteraction * _Nonnull)dragInteraction itemsForAddingToSession:(id<UIDragSession>  _Nonnull)session forTouchAtPoint:(CGPoint)point completion:(BOOL (^ _Nonnull)(NSArray<UIDragItem *> * _Nonnull))completion;
@end

@class UIColor;
API_AVAILABLE(ios(17.4))
@protocol BEExtendedTextInputTraits <UITextInputTraits>
@optional
@property (nonatomic, readonly, getter=isSingleLineDocument) BOOL singleLineDocument;
@property (nonatomic, readonly, getter=isTypingAdaptationEnabled) BOOL typingAdaptationEnabled;
@property (nonatomic, readonly) UIColor * _Nullable insertionPointColor;
@property (nonatomic, readonly) UIColor * _Nullable selectionHandleColor;
@property (nonatomic, readonly) UIColor * _Nullable selectionHighlightColor;
@end

@class xpc_connection_t;
API_AVAILABLE(ios(26.0))
@protocol BEExtensionProcess <NSObject>
- (void)invalidate;
- (xpc_connection_t _Nullable)makeLibXPCConnectionError:(NSError * _Nullable * _Nullable)error;
@end

API_AVAILABLE(ios(17.4))
@protocol BEProcessCapabilityGrant <NSObject>
- (BOOL)invalidate;
@property (atomic, readonly, getter=isValid) BOOL valid;
@end

API_AVAILABLE(ios(17.4))
@protocol BEResponderEditActions <UIResponderStandardEditActions>
@optional
- (void)share:(id  _Nullable)sender;
- (void)addShortcut:(id  _Nullable)sender;
- (void)lookup:(id  _Nullable)sender;
- (void)findSelected:(id  _Nullable)sender;
- (void)promptForReplace:(id  _Nullable)sender;
- (void)replace:(id  _Nullable)sender;
- (void)translate:(id  _Nullable)sender;
- (void)transliterateChinese:(id  _Nullable)sender;
@end

@class BEScrollView;
@class BEScrollViewScrollUpdate;
API_AVAILABLE(ios(17.4))
@protocol BEScrollViewDelegate <UIScrollViewDelegate>
@optional
- (void)scrollView:(BEScrollView * _Nonnull)scrollView handleScrollUpdate:(BEScrollViewScrollUpdate * _Nonnull)scrollUpdate completion:(void (^ _Nonnull)(BOOL))completion;
- (BEScrollView * _Nullable)parentScrollViewForScrollView:(BEScrollView * _Nonnull)scrollView;
@end

@class BEDirectionalTextRange;
typedef enum BEGestureType BEGestureType;
@class BEKeyEntry;
typedef enum BEKeyModifierFlags BEKeyModifierFlags;
typedef enum BESelectionFlags BESelectionFlags;
typedef enum BESelectionTouchPhase BESelectionTouchPhase;
@class BETextAlternatives;
@class BETextDocumentContext;
@class BETextDocumentRequest;
typedef enum BETextReplacementOptions BETextReplacementOptions;
@class BETextSuggestion;
@class NSAttributedString;
@class NSAttributedStringKey;
typedef enum NSWritingDirection NSWritingDirection;
typedef enum UIEditMenuArrowDirection UIEditMenuArrowDirection;
typedef enum UIGestureRecognizerState UIGestureRecognizerState;
typedef enum UITextGranularity UITextGranularity;
@class UITextPlaceholder;
@class UITextPosition;
@class UITextRange;
@class UITextSelectionRect;
typedef enum UITextStorageDirection UITextStorageDirection;
@class UIView;
API_AVAILABLE(ios(17.4))
@protocol BETextInput <UIKeyInput, BETextSelectionDirectionNavigation, BEResponderEditActions>
@property (nonatomic, readwrite, weak) id<BETextInputDelegate> _Nullable asyncInputDelegate;
- (BOOL)canPerformAction:(SEL _Nonnull)action withSender:(id  _Nullable)sender;
@property (nonatomic, readonly, getter=isEditable) BOOL editable;
- (void)handleKeyEntry:(BEKeyEntry * _Nonnull)entry withCompletionHandler:(void (^ _Nonnull)(BEKeyEntry * _Nonnull, BOOL))completionHandler;
- (void)shiftKeyStateChangedFromState:(BEKeyModifierFlags)oldState toState:(BEKeyModifierFlags)newState;
- (NSString * _Nullable)textInRange:(UITextRange * _Nonnull)range;
- (NSInteger)offsetFromPosition:(UITextPosition * _Nonnull)from toPosition:(UITextPosition * _Nonnull)toPosition;
- (void)setBaseWritingDirection:(NSWritingDirection)writingDirection forRange:(UITextRange * _Nonnull)range;
- (void)deleteInDirection:(UITextStorageDirection)direction toGranularity:(UITextGranularity)granularity;
- (void)transposeCharactersAroundSelection;
- (void)replaceText:(NSString * _Nonnull)originalText withText:(NSString * _Nonnull)replacementText options:(BETextReplacementOptions)options completionHandler:(void (^ _Nonnull)(NSArray<UITextSelectionRect *> * _Nonnull))completionHandler;
- (void)requestTextContextForAutocorrectionWithCompletionHandler:(void (^ _Nonnull)(BETextDocumentContext * _Nonnull))completionHandler;
- (void)requestTextRectsForString:(NSString * _Nonnull)input withCompletionHandler:(void (^ _Nonnull)(NSArray<UITextSelectionRect *> * _Nonnull))completionHandler;
@property (nonatomic, readonly) BOOL automaticallyPresentEditMenu;
- (void)requestPreferredArrowDirectionForEditMenuWithCompletionHandler:(void (^ _Nonnull)(UIEditMenuArrowDirection))completionHandler;
- (void)systemWillPresentEditMenuWithAnimator:(id<UIEditMenuInteractionAnimating>  _Nonnull)animator;
- (void)systemWillDismissEditMenuWithAnimator:(id<UIEditMenuInteractionAnimating>  _Nonnull)animator;
@property (nonatomic, readonly) id<BEExtendedTextInputTraits> _Nullable extendedTextInputTraits;
- (NSDictionary<NSAttributedStringKey,id> * _Nullable)textStylingAtPosition:(UITextPosition * _Nonnull)position inDirection:(UITextStorageDirection)direction;
@property (nonatomic, readonly, getter=isReplaceAllowed) BOOL replaceAllowed;
- (void)replaceSelectedText:(NSString * _Nonnull)text withText:(NSString * _Nonnull)replacementText;
- (void)updateCurrentSelectionTo:(CGPoint)point fromGesture:(BEGestureType)gestureType inState:(UIGestureRecognizerState)state;
- (void)setSelectionFromPoint:(CGPoint)from toPoint:(CGPoint)to gesture:(BEGestureType)gesture state:(UIGestureRecognizerState)state;
- (void)adjustSelectionBoundaryToPoint:(CGPoint)point touchPhase:(BESelectionTouchPhase)touch baseIsStart:(BOOL)boundaryIsStart flags:(BESelectionFlags)flags;
- (BOOL)textInteractionGesture:(BEGestureType)gestureType shouldBeginAtPoint:(CGPoint)point;
@optional
@property (nonatomic, readonly) API_AVAILABLE UIView *selectionContainerViewBelowText;
@property (nonatomic, readonly) API_AVAILABLE UIView *selectionContainerViewAboveText;
@required
@property (atomic, readonly) NSString * _Nullable selectedText;
@property (atomic, readwrite, copy) UITextRange * _Nullable selectedTextRange;
@property (nonatomic, readonly, getter=isSelectionAtDocumentStart) BOOL selectionAtDocumentStart;
- (CGRect)caretRectForPosition:(UITextPosition * _Nonnull)position;
- (NSArray<UITextSelectionRect *> * _Nonnull)selectionRectsForRange:(UITextRange * _Nonnull)range;
- (void)selectWordForReplacement;
- (void)updateSelectionWithExtentPoint:(CGPoint)point boundary:(UITextGranularity)granularity completionHandler:(void (^ _Nonnull)(BOOL))completionHandler;
- (void)selectTextInGranularity:(UITextGranularity)granularity atPoint:(CGPoint)point completionHandler:(void (^ _Nonnull)(void))completionHandler;
- (void)selectPositionAtPoint:(CGPoint)point completionHandler:(void (^ _Nonnull)(void))completionHandler;
- (void)selectPositionAtPoint:(CGPoint)point withContextRequest:(BETextDocumentRequest * _Nonnull)request completionHandler:(void (^ _Nonnull)(BETextDocumentContext * _Nonnull))completionHandler;
- (void)adjustSelectionByRange:(BEDirectionalTextRange)range completionHandler:(void (^ _Nonnull)(void))completionHandler;
- (void)moveByOffset:(NSInteger)offset;
- (void)moveSelectionAtBoundary:(UITextGranularity)granularity inStorageDirection:(UITextStorageDirection)direction completionHandler:(void (^ _Nonnull)(void))completionHandler;
- (void)selectTextForEditMenuWithLocationInView:(CGPoint)locationInView completionHandler:(void (^ _Nonnull)(BOOL, NSString * _Nullable, NSRange))completionHandler;
@property (nonatomic, readonly) NSString * _Nullable markedText;
@property (nonatomic, readonly) NSAttributedString * _Nullable attributedMarkedText;
@property (nonatomic, readonly) UITextRange * _Nullable markedTextRange;
@property (nonatomic, readonly) BOOL hasMarkedText;
- (void)setMarkedText:(NSString * _Nullable)markedText selectedRange:(NSRange)selectedRange;
- (void)setAttributedMarkedText:(NSAttributedString * _Nullable)markedText selectedRange:(NSRange)selectedRange;
- (void)unmarkText;
- (BOOL)isPointNearMarkedText:(CGPoint)point;
- (void)requestDocumentContext:(BETextDocumentRequest * _Nonnull)request completionHandler:(void (^ _Nonnull)(BETextDocumentContext * _Nonnull))completionHandler;
- (void)willInsertFinalDictationResult;
- (void)replaceDictatedText:(NSString * _Nonnull)oldText withText:(NSString * _Nonnull)newText;
- (void)didInsertFinalDictationResult;
- (NSArray<BETextAlternatives *> * _Nullable)alternativesForSelectedText;
- (void)addTextAlternatives:(BETextAlternatives * _Nonnull)alternatives;
- (void)insertTextAlternatives:(BETextAlternatives * _Nonnull)alternatives;
@optional
- (void)removeTextAlternatives;
@required
- (void)insertTextPlaceholderWithSize:(CGSize)size completionHandler:(void (^ _Nonnull)(UITextPlaceholder * _Nonnull))completionHandler;
- (void)removeTextPlaceholder:(UITextPlaceholder * _Nonnull)placeholder willInsertText:(BOOL)willInsertText completionHandler:(void (^ _Nonnull)(void))completionHandler;
- (void)insertTextSuggestion:(BETextSuggestion * _Nonnull)textSuggestion;
@property (nonatomic, readonly)  UIView * _Nonnull textInputView;
@property (nonatomic, readonly) CGRect textFirstRect;
@property (nonatomic, readonly) CGRect textLastRect;
@property (nonatomic, readonly) CGRect unobscuredContentRect;
@property (nonatomic, readonly) UIView * _Nonnull unscaledView;
@property (nonatomic, readonly) CGRect selectionClipRect;
- (void)autoscrollToPoint:(CGPoint)point;
- (void)cancelAutoscroll;
@optional
- (void)keyboardWillDismiss;
@end

@class BEKeyEntryContext;
@class BETextSuggestion;
API_AVAILABLE(ios(17.4))
@protocol BETextInputDelegate <NSObject>
- (BOOL)shouldDeferEventHandlingToSystemForTextInput:(id<BETextInput>  _Nonnull)textInput context:(BEKeyEntryContext * _Nonnull)keyEventContext;
- (void)textInput:(id<BETextInput>  _Nonnull)textInput setCandidateSuggestions:(NSArray<BETextSuggestion *> * _Nullable)suggestions;
- (void)selectionWillChangeForTextInput:(id<BETextInput>  _Nonnull)textInput;
- (void)selectionDidChangeForTextInput:(id<BETextInput>  _Nonnull)textInput;
- (void)textInput:(id<BETextInput>  _Nonnull)textInput deferReplaceTextActionToSystem:(id  _Nonnull)sender;
- (void)invalidateTextEntryContextForTextInput:(id<BETextInput>  _Nonnull)textInput;
@end

@class BETextInteraction;
API_AVAILABLE(ios(17.4))
@protocol BETextInteractionDelegate <NSObject>
- (void)systemWillChangeSelectionForInteraction:(BETextInteraction * _Nonnull)textInteraction;
- (void)systemDidChangeSelectionForInteraction:(BETextInteraction * _Nonnull)textInteraction;
@end

typedef enum UITextGranularity UITextGranularity;
typedef enum UITextLayoutDirection UITextLayoutDirection;
typedef enum UITextStorageDirection UITextStorageDirection;
API_AVAILABLE(ios(17.4))
@protocol BETextSelectionDirectionNavigation <NSObject>
- (void)moveInLayoutDirection:(UITextLayoutDirection)direction;
- (void)extendInLayoutDirection:(UITextLayoutDirection)direction;
- (void)moveInStorageDirection:(UITextStorageDirection)direction byGranularity:(UITextGranularity)granularity;
- (void)extendInStorageDirection:(UITextStorageDirection)direction byGranularity:(UITextGranularity)granularity;
@end
