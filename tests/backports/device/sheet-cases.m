#import <UIKit/UIKit.h>
#import "sheet-cases.h"

/* A context of the test's own, with the container bounds the medium detent asks for. */
@interface SheetContext : NSObject <UISheetPresentationControllerDetentResolutionContext>
@property (nonatomic, strong) UITraitCollection *containerTraitCollection;
@property (nonatomic, assign) CGFloat maximumDetentValue;
@property (nonatomic, assign) CGRect bounds;
@end

@implementation SheetContext
- (CGRect)_containerBounds { return self.bounds; }
@end

@interface SheetDelegate : NSObject <UISheetPresentationControllerDelegate>
@property (nonatomic, strong) NSMutableArray *calls;
@end

@implementation SheetDelegate
- (instancetype)init { if ((self = [super init])) _calls = [NSMutableArray array]; return self; }
- (void)sheetPresentationControllerDidChangeSelectedDetentIdentifier:(UISheetPresentationController *)sheet { [_calls addObject:@"didChangeDetent"]; }
- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)controller { [_calls addObject:@"shouldDismiss"]; return YES; }
- (void)presentationControllerWillDismiss:(UIPresentationController *)controller { [_calls addObject:@"willDismiss"]; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller { [_calls addObject:@"didDismiss"]; }
- (void)presentationControllerDidAttemptToDismiss:(UIPresentationController *)controller { [_calls addObject:@"didAttempt"]; }
@end

static NSString *number(CGFloat value)
{
    if (value == CGFLOAT_MAX)
        return @"max";
    return [NSString stringWithFormat:@"%.2f", (double)value];
}

static NSString *flag(BOOL value)
{
    return value ? @"1" : @"0";
}

/* The description without its address. */
static NSString *detent_text(UISheetPresentationControllerDetent *detent)
{
    NSString *text = detent.description;
    NSRange range = [text rangeOfString:@"_type="];
    return range.location == NSNotFound ? text : [text substringFromIndex:range.location];
}

static NSString *identifiers(NSArray *detents)
{
    NSMutableArray *names = [NSMutableArray array];
    for (UISheetPresentationControllerDetent *detent in detents)
        [names addObject:detent.identifier];
    return [names componentsJoinedByString:@","];
}

void sheet_api_run(SheetRecorder record)
{
    record(@"const.medium", UISheetPresentationControllerDetentIdentifierMedium);
    record(@"const.large", UISheetPresentationControllerDetentIdentifierLarge);
    record(@"const.automatic", number(UISheetPresentationControllerAutomaticDimension));
    record(@"const.inactive", number(UISheetPresentationControllerDetentInactive));

    CGFloat (^constant)(id<UISheetPresentationControllerDetentResolutionContext>) = ^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) { return -5; };
    CGFloat (^fraction)(id<UISheetPresentationControllerDetentResolutionContext>) = ^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) { return context.maximumDetentValue * 0.3; };
    record(@"detent.medium", detent_text([UISheetPresentationControllerDetent mediumDetent]));
    record(@"detent.large", detent_text([UISheetPresentationControllerDetent largeDetent]));
    record(@"detent.custom", detent_text([UISheetPresentationControllerDetent customDetentWithIdentifier:@"x" resolver:constant]));
    NSString *dynamic = [UISheetPresentationControllerDetent customDetentWithIdentifier:nil resolver:constant].identifier;
    record(@"detent.dynamic", [NSString stringWithFormat:@"prefix=%@ uuid=%@", flag([dynamic hasPrefix:@"com.apple.UIKit.dynamic."]),
        flag([[NSUUID alloc] initWithUUIDString:[dynamic stringByReplacingOccurrencesOfString:@"com.apple.UIKit.dynamic." withString:@""]] != nil)]);
    UISheetPresentationControllerDetent *shared = [UISheetPresentationControllerDetent customDetentWithIdentifier:@"z" resolver:constant];
    record(@"detent.custom.equality", [NSString stringWithFormat:@"sameResolver=%@ self=%@ hashEqual=%@",
        flag([shared isEqual:[UISheetPresentationControllerDetent customDetentWithIdentifier:@"z" resolver:constant]]), flag([shared isEqual:shared]),
        flag([UISheetPresentationControllerDetent mediumDetent].hash == [UISheetPresentationControllerDetent mediumDetent].hash)]);
    record(@"detent.identity", [NSString stringWithFormat:@"sameMedium=%@ equalMedium=%@ equalLarge=%@ mediumLarge=%@ customSameId=%@",
        flag([UISheetPresentationControllerDetent mediumDetent] == [UISheetPresentationControllerDetent mediumDetent]),
        flag([[UISheetPresentationControllerDetent mediumDetent] isEqual:[UISheetPresentationControllerDetent mediumDetent]]),
        flag([[UISheetPresentationControllerDetent largeDetent] isEqual:[UISheetPresentationControllerDetent largeDetent]]),
        flag([[UISheetPresentationControllerDetent mediumDetent] isEqual:[UISheetPresentationControllerDetent largeDetent]]),
        flag([[UISheetPresentationControllerDetent customDetentWithIdentifier:@"y" resolver:constant] isEqual:[UISheetPresentationControllerDetent customDetentWithIdentifier:@"y" resolver:fraction]])]);

    NSArray *sizes = @[ [NSValue valueWithCGSize:CGSizeMake(320, 480)], [NSValue valueWithCGSize:CGSizeMake(320, 568)], [NSValue valueWithCGSize:CGSizeMake(320, 569)],
                        [NSValue valueWithCGSize:CGSizeMake(375, 667)], [NSValue valueWithCGSize:CGSizeMake(768, 1024)], [NSValue valueWithCGSize:CGSizeMake(480, 320)] ];
    for (NSValue *value in sizes) {
        CGSize size = value.CGSizeValue;
        for (NSNumber *vertical in @[ @(UIUserInterfaceSizeClassRegular), @(UIUserInterfaceSizeClassCompact), @(UIUserInterfaceSizeClassUnspecified) ]) {
            SheetContext *context = [[SheetContext alloc] init];
            context.containerTraitCollection = [UITraitCollection traitCollectionWithVerticalSizeClass:vertical.integerValue];
            context.maximumDetentValue = 440;
            context.bounds = CGRectMake(0, 0, size.width, size.height);
            record([NSString stringWithFormat:@"resolve.%.0fx%.0f.v%@", size.width, size.height, vertical],
                [NSString stringWithFormat:@"medium=%@ large=%@ constant=%@ fraction=%@", number([[UISheetPresentationControllerDetent mediumDetent] resolvedValueInContext:context]),
                    number([[UISheetPresentationControllerDetent largeDetent] resolvedValueInContext:context]),
                    number([[UISheetPresentationControllerDetent customDetentWithIdentifier:nil resolver:constant] resolvedValueInContext:context]),
                    number([[UISheetPresentationControllerDetent customDetentWithIdentifier:nil resolver:fraction] resolvedValueInContext:context])]);
        }
    }

    for (NSNumber *style in @[ @(UIModalPresentationFullScreen), @(UIModalPresentationPageSheet), @(UIModalPresentationFormSheet), @(UIModalPresentationCustom), @(UIModalPresentationOverFullScreen) ]) {
        UIViewController *controller = [[UIViewController alloc] init];
        controller.modalPresentationStyle = style.integerValue;
        UISheetPresentationController *sheet = controller.sheetPresentationController;
        record([NSString stringWithFormat:@"style.%@", style], [NSString stringWithFormat:@"sheet=%@ same=%@ again=%@",
            flag([sheet isKindOfClass:[UISheetPresentationController class]]), flag(!sheet || controller.presentationController == sheet), flag(controller.sheetPresentationController == sheet)]);
        UIViewController *asked = [[UIViewController alloc] init];
        asked.modalPresentationStyle = style.integerValue;
        UIPresentationController *first = asked.presentationController;
        record([NSString stringWithFormat:@"style.first.%@", style], [NSString stringWithFormat:@"sheet=%@ same=%@",
            flag([first isKindOfClass:[UISheetPresentationController class]]), flag(!asked.sheetPresentationController || asked.sheetPresentationController == first)]);
    }

    UIViewController *controller = [[UIViewController alloc] init];
    controller.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = controller.sheetPresentationController;
    record(@"sheet.defaults", [NSString stringWithFormat:@"detents=%@ selected=%@ undimmed=%@ grabber=%@ radius=%@ expands=%@ edge=%@ width=%@ source=%@ delegate=%@ presented=%@ presenting=%@ container=%@",
        identifiers(sheet.detents), sheet.selectedDetentIdentifier ?: @"nil", sheet.largestUndimmedDetentIdentifier ?: @"nil", flag(sheet.prefersGrabberVisible), number(sheet.preferredCornerRadius),
        flag(sheet.prefersScrollingExpandsWhenScrolledToEdge), flag(sheet.prefersEdgeAttachedInCompactHeight), flag(sheet.widthFollowsPreferredContentSizeWhenEdgeAttached),
        flag(sheet.sourceView != nil), flag(sheet.delegate != nil), flag(sheet.presentedViewController == controller), flag(sheet.presentingViewController != nil), flag(sheet.containerView != nil)]);
    record(@"sheet.base", [NSString stringWithFormat:@"style=%ld fullscreen=%@ removes=%@ frame=%@",
        (long)sheet.presentationStyle, flag(sheet.shouldPresentInFullscreen), flag(sheet.shouldRemovePresentersView), NSStringFromCGRect(sheet.frameOfPresentedViewInContainerView)]);

    UIView *source = [[UIView alloc] init];
    SheetDelegate *delegate = [[SheetDelegate alloc] init];
    sheet.detents = @[ [UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent] ];
    sheet.selectedDetentIdentifier = @"bogus";
    sheet.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    sheet.prefersGrabberVisible = YES;
    sheet.preferredCornerRadius = 12;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
    sheet.sourceView = source;
    sheet.delegate = delegate;
    [sheet invalidateDetents];
    __block BOOL ran = NO;
    [sheet animateChanges:^{
        ran = YES;
    }];
    record(@"sheet.set", [NSString stringWithFormat:@"detents=%@ selected=%@ undimmed=%@ grabber=%@ radius=%@ expands=%@ edge=%@ width=%@ source=%@ delegate=%@ animateRan=%@ calls=%@",
        identifiers(sheet.detents), sheet.selectedDetentIdentifier, sheet.largestUndimmedDetentIdentifier, flag(sheet.prefersGrabberVisible), number(sheet.preferredCornerRadius),
        flag(sheet.prefersScrollingExpandsWhenScrolledToEdge), flag(sheet.prefersEdgeAttachedInCompactHeight), flag(sheet.widthFollowsPreferredContentSizeWhenEdgeAttached),
        flag(sheet.sourceView == source), flag(sheet.delegate == delegate), flag(ran), [delegate.calls componentsJoinedByString:@","]]);
    NSArray *given = @[ [UISheetPresentationControllerDetent largeDetent] ];
    sheet.detents = given;
    sheet.selectedDetentIdentifier = nil;
    record(@"sheet.reset", [NSString stringWithFormat:@"equal=%@ selected=%@", flag([sheet.detents isEqualToArray:given]), sheet.selectedDetentIdentifier ?: @"nil"]);
}

static NSString *window_rect(UIView *view)
{
    CGRect rect = [view convertRect:view.bounds toView:nil];
    return [NSString stringWithFormat:@"%.1f %.1f %.1f %.1f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

@interface SheetLayoutSteps : NSObject
@property (nonatomic, strong) NSMutableArray *steps;
@end

@implementation SheetLayoutSteps
- (void)next
{
    if (!_steps.count)
        return;
    void (^step)(void) = _steps.firstObject;
    [_steps removeObjectAtIndex:0];
    step();
    [self performSelector:@selector(next) withObject:nil afterDelay:1.2];
}
@end

void sheet_layout_run(UIWindow *window, SheetRecorder record, void (^done)(void))
{
    UIViewController *root = window.rootViewController;
    UIViewController *first = [[UIViewController alloc] init];
    first.view.backgroundColor = [UIColor whiteColor];
    first.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = first.sheetPresentationController;
    SheetDelegate *delegate = [[SheetDelegate alloc] init];
    sheet.delegate = delegate;
    sheet.detents = @[ [UISheetPresentationControllerDetent mediumDetent], [UISheetPresentationControllerDetent largeDetent] ];
    sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
    UIViewController *second = [[UIViewController alloc] init];
    second.view.backgroundColor = [UIColor lightGrayColor];
    second.modalPresentationStyle = UIModalPresentationFormSheet;
    void (^state)(NSString *) = ^(NSString *name) {
        record([@"layout." stringByAppendingString:name], [NSString stringWithFormat:@"root=%@ first=%@ second=%@ selected=%@ container=%@ calls=%@",
            window_rect(root.view), first.view.window ? window_rect(first.view) : @"-", second.view.window ? window_rect(second.view) : @"-",
            sheet.selectedDetentIdentifier ?: @"nil", flag(sheet.containerView != nil), [delegate.calls componentsJoinedByString:@","]]);
    };
    SheetLayoutSteps *steps = [[SheetLayoutSteps alloc] init];
    steps.steps = [NSMutableArray arrayWithObjects:
        ^{ [root presentViewController:first animated:YES completion:nil]; },
        ^{ state(@"large");
           record(@"layout.controller", [NSString stringWithFormat:@"same=%@ presenting=%@", flag(first.presentationController == sheet), flag(sheet.presentingViewController == root)]);
           [sheet animateChanges:^{ sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium; }]; },
        ^{ state(@"medium");
           sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge; },
        ^{ state(@"largeAgain");
           [first presentViewController:second animated:YES completion:nil]; },
        ^{ state(@"stacked");
           [second dismissViewControllerAnimated:YES completion:nil]; },
        ^{ state(@"unstacked");
           [first dismissViewControllerAnimated:YES completion:nil]; },
        ^{ state(@"dismissed");
           record(@"layout.after", [NSString stringWithFormat:@"transform=%@ radius=%.1f masks=%@", NSStringFromCGAffineTransform(root.view.transform), root.view.layer.cornerRadius, flag(root.view.layer.masksToBounds)]);
           done(); },
        nil];
    /* The delayed perform keeps the steps alive until the last one has run. */
    [steps next];
}
