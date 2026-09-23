#import <UIKit/UIKit.h>
#import <crt_externs.h>
#import <mach-o/loader.h>
#import <objc/runtime.h>

/* iOS 13 makes UIModalPresentationAutomatic the style of a new view controller when the program was
   linked with SDK 13.0 or later, and answers the style it resolves to (UIKitCore 16.0: the ivar is
   written in -initWithNibName:bundle: 0x188fd7770 and in -initWithCoder: 0x18917aba8 when the archive
   has no UIModalPresentationStyle, behind dyld_program_sdk_at_least(iOS 13.0); -modalPresentationStyle
   0x188e97f50 never answers Automatic). A release without it gets the same, decided by the same fact:
   the SDK the main image's load commands record, 0 where they record none. */
static uint32_t charon_program_sdk(void)
{
    const struct mach_header *header = (const struct mach_header *)_NSGetMachExecuteHeader();
    const char *command = (const char *)header + (header->magic == MH_MAGIC_64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
    for (uint32_t index = 0; index < header->ncmds; index++) {
        const struct load_command *load = (const struct load_command *)command;
        if (load->cmd == LC_VERSION_MIN_IPHONEOS)
            return ((const struct version_min_command *)load)->sdk;
        if (load->cmd == LC_BUILD_VERSION && ((const struct build_version_command *)load)->platform == PLATFORM_IOS)
            return ((const struct build_version_command *)load)->sdk;
        command += load->cmdsize;
    }
    return 0;
}

/* What Automatic resolves to: the controller's own preference, else the default provider's, which is
   the page sheet for every idiom UIKit registers (-[_UIPresentationControllerNullVisualStyleProvider
   defaultConcretePresentationStyleForViewController:] 0x189ab9524). The image picker prefers full
   screen for the camera (-[UIImagePickerController _preferredModalPresentationStyle] 0x1895fc4ac). */
static UIModalPresentationStyle charon_automatic_style(UIViewController *controller)
{
    if ([controller isKindOfClass:[UIImagePickerController class]] && ((UIImagePickerController *)controller).sourceType == UIImagePickerControllerSourceTypeCamera)
        return UIModalPresentationFullScreen;
    return UIModalPresentationPageSheet;
}

@interface CharonAutomaticPresentationInstaller : NSObject
@end

@implementation CharonAutomaticPresentationInstaller

+ (void)load
{
    if ([UIViewController instancesRespondToSelector:@selector(isModalInPresentation)] || charon_program_sdk() < 0x000d0000)
        return;
    Class controller = [UIViewController class];
    SEL setter = @selector(setModalPresentationStyle:);
    void (*store)(id, SEL, UIModalPresentationStyle) = (void (*)(id, SEL, UIModalPresentationStyle))class_getMethodImplementation(controller, setter);

    SEL getter = @selector(modalPresentationStyle);
    UIModalPresentationStyle (*stored)(id, SEL) = (UIModalPresentationStyle (*)(id, SEL))class_getMethodImplementation(controller, getter);
    class_replaceMethod(controller, getter, imp_implementationWithBlock(^UIModalPresentationStyle (UIViewController *self_) {
        UIModalPresentationStyle style = stored(self_, getter);
        return style == UIModalPresentationAutomatic ? charon_automatic_style(self_) : style;
    }), method_getTypeEncoding(class_getInstanceMethod(controller, getter)));

    SEL nib = @selector(initWithNibName:bundle:);
    id (*nibOriginal)(id, SEL, NSString *, NSBundle *) = (id (*)(id, SEL, NSString *, NSBundle *))class_getMethodImplementation(controller, nib);
    class_replaceMethod(controller, nib, imp_implementationWithBlock(^id (UIViewController *self_, NSString *name, NSBundle *bundle) {
        UIViewController *made = nibOriginal(self_, nib, name, bundle);
        if (made)
            store(made, setter, UIModalPresentationAutomatic);
        return made;
    }), method_getTypeEncoding(class_getInstanceMethod(controller, nib)));

    SEL coded = @selector(initWithCoder:);
    id (*codedOriginal)(id, SEL, NSCoder *) = (id (*)(id, SEL, NSCoder *))class_getMethodImplementation(controller, coded);
    class_replaceMethod(controller, coded, imp_implementationWithBlock(^id (UIViewController *self_, NSCoder *coder) {
        UIViewController *made = codedOriginal(self_, coded, coder);
        if (made && ![coder containsValueForKey:@"UIModalPresentationStyle"])
            store(made, setter, UIModalPresentationAutomatic);
        return made;
    }), method_getTypeEncoding(class_getInstanceMethod(controller, coded)));
}

@end
