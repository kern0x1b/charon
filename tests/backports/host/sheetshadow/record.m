#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* The magic shadow of UIKit's sheet, asked of the host's own UIKit and Core Animation under Mac Catalyst (a probe of the
   oracle: private classes are asked by name here, never in the port). It prints what the shadow is made of and checks
   the one thing the port's facts rest on: a vibrant colour matrix set with -[CALayer setFilters:] (what 16.0's
   -[_UIShadowView _updateShadowVisualStyling] sets) computes its colour from what lies behind the layer, not from the
   layer's own content, which iOS 6 has no way to do. */
typedef struct { float m11, m12, m13, m14, m15, m21, m22, m23, m24, m25, m31, m32, m33, m34, m35, m41, m42, m43, m44, m45; } Matrix;
@interface NSValue (Matrix)
+ (NSValue *)valueWithCAColorMatrix:(Matrix)matrix;
@end

static const Matrix lower = {0.796875f, -0.1875f, 0.078125f, 0, 0, -0.09375f, 0.71875f, 0.09375f, 0, 0.015625f, -0.09375f, -0.1875f, 0.96875f, 0, -0.015625f, -0.25f, -0.5f, -0.09375f, 1, 0};
static const Matrix redden = {0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0};

static id filter(NSString *type, const Matrix *matrix)
{
    id f = [NSClassFromString(@"CAFilter") performSelector:@selector(filterWithType:) withObject:type];
    if (matrix)
        [f setValue:[NSValue valueWithCAColorMatrix:*matrix] forKey:@"inputColorMatrix"];
    return f;
}

static void pixels(UIImage *image, CGSize size, void (^use)(const uint8_t *data, size_t width, size_t height))
{
    size_t w = (size_t)size.width, h = (size_t)size.height;
    uint8_t *data = calloc(w * h, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), image.CGImage);
    use(data, w, h);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(data);
}

static UIImage *solid(CGFloat alpha)
{
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40) format:format] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [[UIColor colorWithWhite:0 alpha:alpha] setFill];
        UIRectFill(CGRectMake(0, 0, 40, 40));
    }];
}

static int checks, failures;
static const float colours[4][3] = {{1, 0, 0}, {0, 0, 1}, {0.5f, 0.5f, 0.5f}, {1, 1, 1}};
static void check(BOOL ok, NSString *what)
{
    checks++;
    if (!ok)
        failures++;
    printf("%s %s\n", ok ? "ok" : "FAIL", what.UTF8String);
}

/* The destination a vibrant matrix is expected to leave, per the model the checks hold: the matrix applied to the
   destination pixel (opaque, unpremultiplied) and clamped to 0...1, laid over it with the layer's alpha times the
   matrix's own alpha. */
static void expected(const Matrix *m, float alpha, const float d[3], float out[3])
{
    const float *r = &m->m11;
    float a = fminf(fmaxf(r[15] * d[0] + r[16] * d[1] + r[17] * d[2] + r[18] + r[19], 0), 1);
    for (int c = 0; c < 3; c++) {
        float v = r[c * 5] * d[0] + r[c * 5 + 1] * d[1] + r[c * 5 + 2] * d[2] + r[c * 5 + 3] + r[c * 5 + 4];
        out[c] = d[c] + alpha * a * (fminf(fmaxf(v, 0), 1) - d[c]);
    }
}

@interface ShadowDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation ShadowDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }
@end

@interface ShadowScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation ShadowScene

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.frame = CGRectMake(0, 0, 400, 300);
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self run]; });
}

- (void)run
{
    UIImage *kit = [UIImage performSelector:@selector(kitImageNamed:) withObject:@"_UIPopoverShadow"];
    printf("note the kit image _UIPopoverShadow: %s at scale %g\n", NSStringFromCGSize(kit.size).UTF8String, kit.scale);
    Class shadowClass = NSClassFromString(@"_UIRoundedRectShadowView");
    if (shadowClass) {
        UIImageView *shadow = ((id (*)(id, SEL, CGFloat))objc_msgSend)([shadowClass alloc], NSSelectorFromString(@"initWithCornerRadius:"), 10);
        CGRect frame = ((CGRect (*)(id, SEL, CGRect))objc_msgSend)(shadow, NSSelectorFromString(@"frameWithContentWithFrame:"), CGRectMake(0, 0, 200, 200));
        shadow.frame = frame;
        [self.window addSubview:shadow];
        [shadow layoutIfNeeded];
        printf("note the shadow view around a 200 x 200 card: frame %s, image %s, cap insets %s\n", NSStringFromCGRect(frame).UTF8String,
               NSStringFromCGSize(shadow.image.size).UTF8String, NSStringFromUIEdgeInsets(shadow.image.capInsets).UTF8String);
        [shadow removeFromSuperview];
    }

    NSArray *backgrounds = @[[UIColor redColor], [UIColor blueColor], [UIColor colorWithWhite:0.5 alpha:1], [UIColor whiteColor]];
    UIView *root = self.window.rootViewController.view;
    for (NSUInteger b = 0; b < backgrounds.count; b++)
        for (NSUInteger k = 0; k < 3; k++) {
            UIView *back = [[UIView alloc] initWithFrame:CGRectMake(10 + k * 60, 10 + b * 60, 50, 50)];
            back.backgroundColor = backgrounds[b];
            UIView *layerView = [[UIView alloc] initWithFrame:CGRectMake(5, 5, 40, 40)];
            layerView.layer.contents = (id)solid(0.5).CGImage;
            if (k == 1) layerView.layer.filters = @[filter(@"colorMatrix", &redden)];
            if (k == 2) layerView.layer.filters = @[filter(@"vibrantColorMatrix", &lower)];
            [back addSubview:layerView];
            [root addSubview:back];
        }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = 1;
        CGSize size = self.window.bounds.size;
        UIImage *shot = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
        }];
        pixels(shot, size, ^(const uint8_t *d, size_t w, size_t h) {
            for (NSUInteger b = 0; b < backgrounds.count; b++) {
                /* The capture's full value: the background alone (the capture reads 249 for 1.0). */
                const uint8_t *alone = d + ((10 + b * 60 + 2) * w + 10 + 25) * 4;
                float full = MAX(MAX(alone[0], alone[1]), alone[2]) / (b == 0 ? colours[0][0] : b == 1 ? colours[1][2] : colours[b][0]);
                const uint8_t *plain = d + ((10 + b * 60 + 25) * w + 10 + 25) * 4;
                const uint8_t *red = d + ((10 + b * 60 + 25) * w + 70 + 25) * 4;
                const uint8_t *vibrant = d + ((10 + b * 60 + 25) * w + 130 + 25) * 4;
                NSString *name = @[@"red", @"blue", @"grey", @"white"][b];
                float red_expected[3] = {0.5f + 0.5f * colours[b][0], 0.5f * colours[b][1], 0.5f * colours[b][2]};
                BOOL control = YES;
                for (int c = 0; c < 3; c++)
                    control = control && fabsf(red[c] - red_expected[c] * full) <= 3;
                check(control, [NSString stringWithFormat:@"the capture shows a layer's filters: a colour matrix that makes the layer red, over %@: %u %u %u", name, red[0], red[1], red[2]]);
                float model[3];
                expected(&lower, 0.5f, colours[b], model);
                BOOL matches = YES, differs = NO;
                for (int c = 0; c < 3; c++) {
                    matches = matches && fabsf(vibrant[c] - model[c] * full) <= 3;
                    differs = differs || abs((int)vibrant[c] - (int)plain[c]) > 6;
                }
                check(matches && differs, [NSString stringWithFormat:@"the vibrant matrix over %@ leaves %u %u %u: the matrix of what is behind (%.0f %.0f %.0f), not the black layer laid over it (%u %u %u)",
                      name, vibrant[0], vibrant[1], vibrant[2], model[0] * full, model[1] * full, model[2] * full, plain[0], plain[1], plain[2]]);
            }
        });
        printf("checks=%d failures=%d\n", checks, failures);
        fflush(stdout);
        exit(failures ? 1 : 0);
    });
}

@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, @"ShadowDelegate");
    }
}
