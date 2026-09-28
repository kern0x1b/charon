#import <UIKit/UIKit.h>
#import <UIKit/UIDragSession.h>
#import <UIKit/UIDragInteraction.h>
#import <UIKit/UIDropInteraction.h>
#import <UIKit/UITextDragging.h>
#import <UIKit/UITextDropping.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "CharonDragSession.h"
#import "CharonTextDragDrop11.h"

// The caller: a text view that can be dragged from and dropped onto, through the port's own drag
// and drop interactions.
//
// The release has a text view and neither of these, so the port supplies the three properties
// `UITextDraggable` and `UITextDroppable` declare on a text control, and the interactions that ask
// the two text delegates' questions in the order their headers give. A drag begins by asking the
// drag delegate what the text is; a drop asks the drop delegate whether the control will take it,
// what it proposes, and then performs it.
//
// The order is Apple's, from the headers, as a fact rather than a copy:
//   * `itemsForDrag:` is what a drag is, asked first, and a delegate that answers nothing is a drag
//     that does not begin;
//   * `dragPreviewForLiftingItem:session:` is the picture the lift animates, and
//     `willAnimateLiftWithAnimator:session:` is where an application animates alongside it, so the
//     preview comes before the animator and both before the session begins;
//   * `dragSessionWillBegin:` is once the items exist and the lift is about to run;
//   * on the drop side `willBecomeEditableForDrop:` is the gate -- a delegate that says no is a drop
//     that is not allowed, and then nothing else is asked -- so it comes before `proposalForDrop:`,
//     which is what the drop would do where it is now, and both before `willPerformDrop:` and the
//     preview for dropping all the items;
//   * the four session messages then report the drag as it moves over this control: enter, update,
//     exit, end.

#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

static const char CharonTextDragDelegateKey;
static const char CharonTextDropDelegateKey;
static const char CharonTextDragOptionsKey;
static const char CharonTextDragInteractionKey;
static const char CharonTextDropInteractionKey;

@implementation UIView (CharonTextDragDropAdaptors)

// One adaptor per control, made once, so a control that is asked twice has one delegate and the
// interaction's is not replaced under itself.
- (CharonTextDragAdaptor *)charon_textDragDelegateAdaptor
{
    static const char key;
    CharonTextDragAdaptor *adaptor = objc_getAssociatedObject(self, &key);
    if (adaptor)
        return adaptor;
    adaptor = [[CharonTextDragAdaptor alloc] initWithControl:self];
    objc_setAssociatedObject(self, &key, adaptor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return adaptor;
}

- (CharonTextDropAdaptor *)charon_textDropDelegateAdaptor
{
    static const char key;
    CharonTextDropAdaptor *adaptor = objc_getAssociatedObject(self, &key);
    if (adaptor)
        return adaptor;
    adaptor = [[CharonTextDropAdaptor alloc] initWithControl:self];
    objc_setAssociatedObject(self, &key, adaptor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return adaptor;
}

@end

@implementation UIView (CharonTextDragDrop11)

// -------------------------------------------------------------------------------------------
// UITextDraggable: what a text control says about dragging out of it.
- (id<UITextDragDelegate>)textDragDelegate
{
    return objc_getAssociatedObject(self, &CharonTextDragDelegateKey);
}

- (void)setTextDragDelegate:(id<UITextDragDelegate>)textDragDelegate
{
    objc_setAssociatedObject(self, &CharonTextDragDelegateKey, textDragDelegate, OBJC_ASSOCIATION_ASSIGN);
}

// The interaction the port installs, made once per control and asked for by a caller that wants to
// drive a drag itself.
- (UIDragInteraction *)textDragInteraction
{
    UIDragInteraction *interaction = objc_getAssociatedObject(self, &CharonTextDragInteractionKey);
    if (interaction)
        return interaction;
    interaction = [[UIDragInteraction alloc] initWithDelegate:(id<UIDragInteractionDelegate>)[self charon_textDragDelegateAdaptor]];
    objc_setAssociatedObject(self, &CharonTextDragInteractionKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return interaction;
}

- (BOOL)isTextDragActive
{
    UIDragInteraction *interaction = objc_getAssociatedObject(self, &CharonTextDragInteractionKey);
    return interaction ? interaction.session != nil : NO;
}

- (UITextDragOptions)textDragOptions
{
    NSNumber *options = objc_getAssociatedObject(self, &CharonTextDragOptionsKey);
    return (UITextDragOptions)(options ? options.unsignedIntegerValue : UITextDragOptionsNone);
}

- (void)setTextDragOptions:(UITextDragOptions)textDragOptions
{
    objc_setAssociatedObject(self, &CharonTextDragOptionsKey, @(textDragOptions), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// -------------------------------------------------------------------------------------------
// UITextDroppable: what a text control says about dropping into it.
- (id<UITextDropDelegate>)textDropDelegate
{
    return objc_getAssociatedObject(self, &CharonTextDropDelegateKey);
}

- (void)setTextDropDelegate:(id<UITextDropDelegate>)textDropDelegate
{
    objc_setAssociatedObject(self, &CharonTextDropDelegateKey, textDropDelegate, OBJC_ASSOCIATION_ASSIGN);
}

- (UIDropInteraction *)textDropInteraction
{
    UIDropInteraction *interaction = objc_getAssociatedObject(self, &CharonTextDropInteractionKey);
    if (interaction)
        return interaction;
    interaction = [[UIDropInteraction alloc] initWithDelegate:(id<UIDropInteractionDelegate>)[self charon_textDropDelegateAdaptor]];
    objc_setAssociatedObject(self, &CharonTextDropInteractionKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return interaction;
}

- (BOOL)isTextDropActive
{
    UIDropInteraction *interaction = objc_getAssociatedObject(self, &CharonTextDropInteractionKey);
    return interaction ? interaction.currentDrop != nil : NO;
}

@end

// The two adaptors, and the questions they ask in the order the two headers give.
@implementation CharonTextDragAdaptor
@synthesize control = _control;

- (instancetype)initWithControl:(UIView *)control
{
    if ((self = [super init]))
        _control = control;
    return self;
}

// What the text is: the drag delegate's own answer, and nothing is dragged when it gives none.
- (NSArray<UIDragItem *> *)charon_itemsForDragSession:(id<UIDragSession>)session
{
    id<UITextDragDelegate> delegate = self.control.textDragDelegate;
    SEL ask = @selector(textDraggableView:itemsForDrag:);
    if (![delegate respondsToSelector:ask])
        return nil;
    CharonTextDragRequest *request = [[CharonTextDragRequest alloc] initWithSession:session];
    if ([self.control isKindOfClass:[UITextView class]]) {
        // The text range the selection covers, which is what the protocol calls the drag range: a
        // range in the text, not an NSRange into a string.
        UITextView *text = (UITextView *)self.control;
        UITextPosition *start = [text positionFromPosition:text.beginningOfDocument offset:0];
        request.range = [text textRangeFromPosition:start toPosition:[text positionFromPosition:start offset:text.selectedRange.length]];
    }
    request.selected = request.range != nil;
    NSArray<UIDragItem *> *items = ((NSArray<UIDragItem *> * (*)(id, SEL, id, id))objc_msgSend)(delegate, ask, self.control, request);
    request.suggested = items;
    return items.count ? items : nil;
}

// The picture the lift animates, from the drag delegate, and from the text itself when it has none:
// the release's own text is drawn into an image of the range, which is what a text drag shows.
- (UITargetedDragPreview *)charon_previewForLiftingItem:(UIDragItem *)item session:(id<UIDragSession>)session
{
    id<UITextDragDelegate> delegate = self.control.textDragDelegate;
    SEL ask = @selector(textDraggableView:dragPreviewForLiftingItem:session:);
    if ([delegate respondsToSelector:ask])
        return ((UITargetedDragPreview * (*)(id, SEL, id, id, id))objc_msgSend)(delegate, ask, self.control, item, session);
    UIView *control = self.control;
    if (![control isKindOfClass:[UITextView class]])
        return nil;
    UITextView *text = (UITextView *)control;
    NSRange range = text.selectedRange;
    if (!range.length)
        return nil;
    NSLayoutManager *layout = text.layoutManager;
    if (!layout)
        return nil;
    UITextDragPreviewRenderer *renderer = [[UITextDragPreviewRenderer alloc] initWithLayoutManager:layout range:range];
    UIImage *image = renderer.image;
    if (!image)
        return nil;
    // A view is the preview and the control is the target, so the picture is the text and it is
    // aimed at the control it came from: the preview's view and its target are the same control, and
    // the lift animates from the range's own place because the parameters carry the visible path.
    UIDragPreviewParameters *parameters = [[UIDragPreviewParameters alloc] init];
    parameters.visiblePath = [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImageView *picture = [[UIImageView alloc] initWithImage:image];
    // A picture of the text, aimed at the control it came from: the picture is what travels and the
    // control is where it goes back to, and the parameters carry the visible path so the lift
    // animates from the range's own place.
    return [[UITargetedDragPreview alloc] initWithView:picture
                                       parameters:parameters
                                            target:[[UIDragPreviewTarget alloc] initWithContainer:text
                                                                                        center:CGPointMake(CGRectGetMidX([text bounds]),
                                                                                                          CGRectGetMidY([text bounds]))]];
}

// The lift, in the header's order: the preview, then the animator, then the session beginning.
- (void)charon_willAnimateLiftWithSession:(id<UIDragSession>)session
{
    id<UITextDragDelegate> delegate = self.control.textDragDelegate;
    SEL preview = @selector(textDraggableView:dragPreviewForLiftingItem:session:);
    SEL animate = @selector(textDraggableView:willAnimateLiftWithAnimator:session:);
    SEL willBegin = @selector(textDraggableView:dragSessionWillBegin:);
    UIDragItem *item = session.items.firstObject;
    if ([delegate respondsToSelector:preview] && item)
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(delegate, preview, self.control, item, session);
    if ([delegate respondsToSelector:animate])
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(delegate, animate, self.control, (id)self, session);
    if ([delegate respondsToSelector:willBegin])
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, willBegin, self.control, session);
}

- (void)charon_dragSessionDidEnd:(id<UIDragSession>)session withOperation:(UIDropOperation)operation
{
    id<UITextDragDelegate> delegate = self.control.textDragDelegate;
    SEL ask = @selector(textDraggableView:dragSessionDidEnd:withOperation:);
    if ([delegate respondsToSelector:ask])
        ((void (*)(id, SEL, id, id, NSInteger))objc_msgSend)(delegate, ask, self.control, session, (NSInteger)operation);
}

@end

@implementation CharonTextDropAdaptor
@synthesize control = _control;

- (instancetype)initWithControl:(UIView *)control
{
    if ((self = [super init]))
        _control = control;
    return self;
}

// Whether this control will take the drop at all. A delegate that says no ends the sequence here,
// which is the header's own rule and why the gate comes first.
- (BOOL)charon_canHandleSession:(id<UIDropSession>)session
{
    id<UITextDropDelegate> delegate = self.control.textDropDelegate;
    SEL ask = @selector(textDroppableView:willBecomeEditableForDrop:);
    if (![delegate respondsToSelector:ask])
        return NO;
    CharonTextDropRequest *request = [[CharonTextDropRequest alloc] initWithSession:session];
    UITextDropEditability editability = ((UITextDropEditability (*)(id, SEL, id, id))objc_msgSend)(delegate, ask, self.control, request);
    return editability == UITextDropEditabilityYes;
}

// What the drop would do where it is now, asked on every move, and then the drop itself.
- (void)charon_updateForSession:(id<UIDropSession>)session
{
    id<UITextDropDelegate> delegate = self.control.textDropDelegate;
    SEL proposal = @selector(textDroppableView:proposalForDrop:);
    SEL perform = @selector(textDroppableView:willPerformDrop:);
    SEL preview = @selector(textDroppableView:previewForDroppingAllItemsWithDefault:);
    CharonTextDropRequest *request = [[CharonTextDropRequest alloc] initWithSession:session];
    if ([delegate respondsToSelector:proposal]) {
        UITextDropProposal *answer = ((UITextDropProposal * (*)(id, SEL, id, id))objc_msgSend)(delegate, proposal, self.control, request);
        request.proposal = answer;
    }
    if ([delegate respondsToSelector:perform])
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, perform, self.control, request);
    if ([delegate respondsToSelector:preview])
        ((UITargetedDragPreview * (*)(id, SEL, id, id))objc_msgSend)(delegate, preview, self.control, (id)[UITargetedDragPreview class]);
}

- (void)charon_sessionDidEnter:(id<UIDropSession>)session
{
    id<UITextDropDelegate> delegate = self.control.textDropDelegate;
    SEL ask = @selector(textDroppableView:dropSessionDidEnter:);
    if ([delegate respondsToSelector:ask])
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, ask, self.control, session);
}

- (void)charon_sessionDidExit:(id<UIDropSession>)session
{
    id<UITextDropDelegate> delegate = self.control.textDropDelegate;
    SEL ask = @selector(textDroppableView:dropSessionDidExit:);
    if ([delegate respondsToSelector:ask])
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, ask, self.control, session);
}

- (void)charon_sessionDidEnd:(id<UIDropSession>)session
{
    id<UITextDropDelegate> delegate = self.control.textDropDelegate;
    SEL ask = @selector(textDroppableView:dropSessionDidEnd:);
    if ([delegate respondsToSelector:ask])
        ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, ask, self.control, session);
}

@end

// The two request objects.
@implementation CharonTextDragRequest
@synthesize session = _session;
@synthesize range = _range;
@synthesize suggested = _suggested;
@synthesize existing = _existing;
@synthesize selected = _selected;

- (instancetype)initWithSession:(id<UIDragSession>)session
{
    if ((self = [super init])) {
        _session = session;
    }
    return self;
}

- (id<UIDragSession>)dragSession
{
    return _session;
}

- (UITextRange *)dragRange
{
    return _range;
}

- (NSArray<UIDragItem *> *)suggestedItems
{
    return _suggested ?: @[];
}

- (NSArray<UIDragItem *> *)existingItems
{
    return _existing ?: @[];
}

- (BOOL)isSelected
{
    return _selected;
}

@end

@implementation CharonTextDropRequest
@synthesize session = _session;
@synthesize position = _position;
@synthesize proposal = _proposal;
@synthesize sameView = _sameView;

- (instancetype)initWithSession:(id<UIDropSession>)session
{
    if ((self = [super init]))
        _session = session;
    return self;
}

- (id<UIDropSession>)dropSession
{
    return _session;
}

- (UITextPosition *)dropPosition
{
    return _position;
}

- (UITextDropProposal *)suggestedProposal
{
    return _proposal;
}

- (BOOL)isSameView
{
    return _sameView;
}

@end

