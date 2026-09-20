#import "uirest.h"

static NSString *pixels_of(UIImage *image)
{
    CGFloat scale = 2;
    CGSize size = CGSizeMake(20, 20);
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(rendered.CGImage));
    const UInt8 *bytes = CFDataGetBytePtr(data);
    NSMutableString *text = [NSMutableString string];
    unsigned long long hash = 1469598103934665603ULL;
    NSUInteger nonzero = 0;
    for (CFIndex index = 0; index < CFDataGetLength(data); index++) {
        hash = (hash ^ bytes[index]) * 1099511628211ULL;
        nonzero += bytes[index] != 0;
    }
    [text appendFormat:@"%llx %lu", hash, (unsigned long)nonzero];
    CFRelease(data);
    return text;
}

static UIImage *source_image(void)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(10, 10), NO, 2);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, 10, 5));
    [[[UIColor blackColor] colorWithAlphaComponent:0.5] setFill];
    UIRectFill(CGRectMake(0, 5, 5, 5));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static NSString *summary(id configuration)
{
    NSString *text = [NSString stringWithFormat:@"%@", configuration];
    NSRange traits = [text rangeOfString:@"traits=("];
    NSString *head = traits.location == NSNotFound ? text : [text substringToIndex:traits.location];
    NSString *scale = @"";
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"DisplayScale = [0-9.]+" options:0 error:nil];
    NSTextCheckingResult *match = traits.location == NSNotFound ? nil : [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match)
        scale = [text substringWithRange:match.range];
    return [NSString stringWithFormat:@"%@ [%@]", head, scale];
}

static NSArray *images_scenario(NSString *folder, Class symbolClass, Class configurationClass)
{
    NSMutableArray *lines = [NSMutableArray array];
    UIImage *image = source_image();
    UIColor *red = [UIColor colorWithRed:1 green:0 blue:0 alpha:1], *blue = [UIColor colorWithRed:0 green:0 blue:1 alpha:0.5];
    for (UIColor *color in @[red, blue, [UIColor clearColor], [UIColor whiteColor]]) {
        UIImage *tinted = [image imageWithTintColor:color];
        [lines addObject:ur_line(@"tinted", @[pixels_of(tinted), NSStringFromCGSize(tinted.size), @(tinted.scale), @(tinted.renderingMode)])];
        UIImage *template = [image imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysTemplate];
        [lines addObject:ur_line(@"tinted template", @[NSStringFromCGSize(template.size), @(template.scale), @(template.renderingMode)])];
    }
    [lines addObject:ur_line(@"tinted with nil", @[pixels_of([image imageWithTintColor:nil]), @([image imageWithTintColor:nil].renderingMode)])];
    UIImage *resizable = [image resizableImageWithCapInsets:UIEdgeInsetsMake(2, 2, 2, 2) resizingMode:UIImageResizingModeTile];
    UIImage *resized = [resizable imageWithTintColor:red];
    [lines addObject:ur_line(@"tinted resizable image", @[NSStringFromUIEdgeInsets(resized.capInsets), @(resized.resizingMode)])];
    UIImage *aligned = [image imageWithAlignmentRectInsets:UIEdgeInsetsMake(1, 2, 3, 4)];
    [lines addObject:ur_line(@"tinted aligned image", NSStringFromUIEdgeInsets([aligned imageWithTintColor:red].alignmentRectInsets))];
    [lines addObject:ur_line(@"tinted empty image", @[NSStringFromCGSize([[[UIImage alloc] init] imageWithTintColor:red].size)])];

    [lines addObject:ur_line(@"baseline", @[ur_yes(image.hasBaseline), @(image.baselineOffsetFromBottom)])];
    UIImage *based = [image imageWithBaselineOffsetFromBottom:3];
    [lines addObject:ur_line(@"with baseline", @[ur_yes(based.hasBaseline), @(based.baselineOffsetFromBottom), NSStringFromCGSize(based.size), @(based.scale), ur_yes(based != image), ur_yes(image.hasBaseline)])];
    UIImage *without = [based imageWithoutBaseline];
    [lines addObject:ur_line(@"without baseline", @[ur_yes(without.hasBaseline), @(without.baselineOffsetFromBottom), ur_yes(based.hasBaseline)])];
    [lines addObject:ur_line(@"baseline kept by a tint", @[ur_yes([based imageWithTintColor:red].hasBaseline), @([based imageWithTintColor:red].baselineOffsetFromBottom)])];

    UIImageConfiguration *plain = image.configuration;
    [lines addObject:ur_line(@"configuration", @[summary(plain)])];
    UIImageSymbolConfiguration *symbol = [symbolClass configurationWithPointSize:20];
    UIImage *configured = [image imageWithConfiguration:symbol];
    [lines addObject:ur_line(@"with a symbol configuration", @[summary(configured.configuration), ur_yes(configured.symbolConfiguration != nil), ur_yes(configured != image), ur_yes(configured.isSymbolImage)])];
    UIImageConfiguration *traits = [plain configurationWithTraitCollection:[UITraitCollection traitCollectionWithDisplayScale:3]];
    (void)configurationClass;
    UIImage *traited = [image imageWithConfiguration:traits];
    [lines addObject:ur_line(@"with a plain configuration", @[summary(traited.configuration), ur_yes(traited != image), NSStringFromCGSize(traited.size)])];

    NSBundle *bundle = [NSBundle bundleWithPath:folder];
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *name in @[@"logo", @"logo.png", @"missing", @"dot"]) {
        UIImage *named = [UIImage imageNamed:name inBundle:bundle withConfiguration:nil];
        [found addObject:named ? [NSString stringWithFormat:@"%@ %@ %g", name, NSStringFromCGSize(named.size), named.scale] : [name stringByAppendingString:@" nil"]];
    }
    [lines addObject:ur_line(@"images of a bundle", found)];
    UIImage *withConfiguration = [UIImage imageNamed:@"logo" inBundle:bundle withConfiguration:symbol];
    [lines addObject:ur_line(@"image of a bundle with a configuration", @[summary(withConfiguration.configuration)])];

    NSMutableArray *system = [NSMutableArray array];
    for (UIImage *glyph in @[[UIImage checkmarkImage], [UIImage strokedCheckmarkImage], [UIImage addImage], [UIImage removeImage], [UIImage actionsImage]])
        [system addObject:[NSString stringWithFormat:@"%@ %g", NSStringFromCGSize(glyph.size), glyph.scale]];
    [lines addObject:ur_line(@"system images", system)];
    NSMutableArray *flat = [NSMutableArray array];
    for (NSString *entry in lines)
        [flat addObject:[entry stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    return flat;
}

static NSString *make_bundle(void)
{
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"charon-images13.bundle"];
    [[NSFileManager defaultManager] removeItemAtPath:folder error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>local.charon.images13</string></dict></plist>" writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8, 6), NO, 1);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, 8, 6));
    [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:[folder stringByAppendingPathComponent:@"logo.png"] atomically:YES];
    UIGraphicsEndImageContext();
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(16, 12), NO, 1);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, 16, 12));
    [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:[folder stringByAppendingPathComponent:@"logo@2x.png"] atomically:YES];
    UIGraphicsEndImageContext();
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), NO, 1);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, 4, 4));
    [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:[folder stringByAppendingPathComponent:@"dot.png"] atomically:YES];
    UIGraphicsEndImageContext();
    return folder;
}
