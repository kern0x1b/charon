#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "check.h"

static NSString *image_of_method(Class class, SEL selector)
{
    Method method = class_getInstanceMethod(class, selector);
    Dl_info info;
    if (!method || !dladdr((void *)method_getImplementation(method), &info) || !info.dli_fname)
        return @"<missing>";
    return @(info.dli_fname).lastPathComponent;
}

static void thermal_state(void)
{
    NSProcessInfo *info = NSProcessInfo.processInfo;
    CHECK_EQUAL(image_of_method([NSProcessInfo class], @selector(thermalState)), @"libFoundationBackports.dylib", "-[NSProcessInfo thermalState] comes from the backports");
    CHECK(info.thermalState == NSProcessInfoThermalStateNominal, "the thermal state is nominal");
    CHECK(info.thermalState == info.thermalState, "the thermal state is the same when read again");
    CHECK_EQUAL(NSProcessInfoThermalStateDidChangeNotification, @"NSProcessInfoThermalStateDidChangeNotification", "the notification is the release's string");
    __block int heard = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) { heard++; }];
    (void)info.thermalState;
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    CHECK(heard == 0, "the notification is not posted, since the state never changes");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

static void picker_presets(void)
{
    Class picker = NSClassFromString(@"UIImagePickerController");
    CHECK(picker != Nil, "UIImagePickerController is there");
    CHECK_EQUAL(image_of_method(picker, @selector(imageExportPreset)), @"libUIKitBackports.dylib", "-imageExportPreset comes from the backports");
    CHECK_EQUAL(image_of_method(picker, @selector(setVideoExportPreset:)), @"libUIKitBackports.dylib", "-setVideoExportPreset: comes from the backports");
    UIImagePickerController *controller = [[UIImagePickerController alloc] init];
    CHECK(controller != nil, "a picker can be made");
    CHECK(controller.imageExportPreset == UIImagePickerControllerImageURLExportPresetCompatible, "a fresh picker exports the compatible format");
    CHECK(controller.videoExportPreset == nil, "a fresh picker has no video preset");
    controller.imageExportPreset = UIImagePickerControllerImageURLExportPresetCurrent;
    CHECK(controller.imageExportPreset == UIImagePickerControllerImageURLExportPresetCurrent, "the image preset is handed back as it was set");
    NSMutableString *preset = [NSMutableString stringWithString:@"AVAssetExportPresetPassthrough"];
    controller.videoExportPreset = preset;
    [preset appendString:@"X"];
    CHECK_EQUAL(controller.videoExportPreset, @"AVAssetExportPresetPassthrough", "the video preset is copied");
    controller.videoExportPreset = nil;
    CHECK(controller.videoExportPreset == nil, "the video preset can be taken away");
    UIImagePickerController *other = [[UIImagePickerController alloc] init];
    CHECK(other.imageExportPreset == UIImagePickerControllerImageURLExportPresetCompatible, "the preset belongs to the picker it was set on");
    CHECK_EQUAL(UIImagePickerControllerPHAsset, @"UIImagePickerControllerPHAsset", "UIImagePickerControllerPHAsset carries its own name");
}

static void absences(void)
{
    CHECK(![UIScrollView instancesRespondToSelector:@selector(horizontalScrollIndicatorInsets)], "horizontalScrollIndicatorInsets is absent");
    CHECK(![UIScrollView instancesRespondToSelector:@selector(verticalScrollIndicatorInsets)], "verticalScrollIndicatorInsets is absent");
    CHECK([UIScrollView instancesRespondToSelector:@selector(scrollIndicatorInsets)], "the release's own scrollIndicatorInsets stays");
    CHECK(NSClassFromString(@"UIPencilInteraction") == Nil, "UIPencilInteraction is absent");
    CHECK(dlsym(RTLD_DEFAULT, "UIGuidedAccessConfigureAccessibilityFeatures") == NULL, "UIGuidedAccessConfigureAccessibilityFeatures is absent");
    CHECK(dlsym(RTLD_DEFAULT, "UIDocumentBrowserErrorDomain") == NULL, "UIDocumentBrowserErrorDomain is absent");
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        if (argc > 1)
            charon_log_to(@(argv[1]));
        thermal_state();
        picker_presets();
        absences();
        printf("%d of %d checks failed\n", charon_failures, charon_checks);
        return charon_failures;
    }
}
