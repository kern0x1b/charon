// The port's CIFilter convenience constructors beside the host's own, in one process.
//
// Every zero-argument class method the port's objects added to CIFilter is called under both names:
// the host's, and the port's prefixed one.  What the two answer is compared field by field - the
// class, the name, the input keys, the output keys and the whole attribute dictionary - and where the
// filter's only declared input is an image, the two are rendered over a fixed window and the bytes
// compared too.  The list of methods is read from the runtime, so nothing here names one by hand.
#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const PREFIX = @"charonHost_";
#define WINDOW_W 32
#define WINDOW_H 32

typedef id (*CharonMsgSend0)(id, SEL);

// prefix_selectors.py keeps the spelling of a keyword whose first half is one of the five families
// an Objective-C method is copied under, gluing the prefix to the second half instead
// (copyMachineTransitionFilter -> copyCharonHostMachineTransitionFilter), so a prefixed selector is
// put back to the port's own name by both spellings.
static NSString *unprefixed(const char *keyword)
{
    if (strncmp(keyword, "charonHost_", 11) == 0) return [NSString stringWithUTF8String:keyword + 11];
    for (NSString *family in @[@"mutableCopy", @"copy", @"init", @"new", @"alloc"]) {
        if (!strncmp(keyword, family.UTF8String, family.length)) {
            const char *rest = keyword + family.length;
            if (strncmp(rest, "CharonHost", 10) == 0 && rest[10] >= 'A' && rest[10] <= 'Z')
                return [NSString stringWithFormat:@"%@%s", family, rest + 10];
        }
    }
    return nil;
}

// The other direction: the name the port's method is under, by the tool's own rule.
static NSString *prefixed(NSString *keyword)
{
    for (NSString *family in @[@"mutableCopy", @"copy", @"init", @"new", @"alloc"]) {
        if ([keyword hasPrefix:family]) {
            NSString *rest = [keyword substringFromIndex:family.length];
            if (!rest.length || (rest.length && [rest characterAtIndex:0] >= 'A' && [rest characterAtIndex:0] <= 'Z'))
                return [NSString stringWithFormat:@"%@CharonHost%@", family, rest];
        }
    }
    return [PREFIX stringByAppendingString:keyword];
}

static CIContext *context;
static long compared, rendered, different, missing;

static NSData *bytes_of(CIImage *image)
{
    if (!image) return nil;
    size_t width = WINDOW_W, height = WINDOW_H;
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    [context render:image toBitmap:data.mutableBytes rowBytes:width * 4 bounds:CGRectMake(0, 0, width, height)
             format:kCIFormatRGBA8 colorSpace:space];
    CGColorSpaceRelease(space);
    return data;
}

static void tell(NSString *what)
{
    if (different++ < 40) printf("different: %s\n", what.UTF8String);
}

static void same_dictionary(NSDictionary *a, NSDictionary *b, NSString *what)
{
    compared++;
    if (a.count != b.count) {
        tell([NSString stringWithFormat:@"%@ count %lu vs %lu", what, (unsigned long)a.count, (unsigned long)b.count]);
        return;
    }
    for (id key in a) {
        id x = a[key], y = b[key];
        BOOL equal;
        if ([x isKindOfClass:[NSArray class]] && [y isKindOfClass:[NSArray class]]) {
            equal = [(NSArray *)x isEqualToArray:y];
        } else if ([x isKindOfClass:[NSData class]] && [y isKindOfClass:[NSData class]]) {
            equal = [(NSData *)x isEqualToData:y];
        } else {
            equal = [x isEqual:y];
        }
        if (!equal) {
            tell([NSString stringWithFormat:@"%@[%@] %@ vs %@", what, [key description],
                  [x description], [y description]]);
            return;
        }
    }
}

int main(void)
{
    context = [CIContext contextWithOptions:nil];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CIColor *colour = [[CIColor alloc] initWithRed:0.25 green:0.5 blue:0.75 alpha:1];
    CIImage *input = [[CIImage imageWithColor:colour] imageByCroppingToRect:CGRectMake(0, 0, 16, 12)];
    CGColorSpaceRelease(space);

    Class metaclass = object_getClass([CIFilter class]);
    unsigned count = 0;
    Method *methods = class_copyMethodList(metaclass, &count);
    NSMutableArray *ported = [NSMutableArray array];
    for (unsigned i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);
        const char *keyword = sel_getName(sel);
        if (!types || types[0] != '@') continue;
        if (strchr(keyword, ':')) continue;
        NSString *own = unprefixed(keyword);
        if (!own) continue;
        [ported addObject:own];
    }
    free(methods);

    for (NSString *selector in ported) {
        SEL host = NSSelectorFromString(selector);
        SEL own = NSSelectorFromString(prefixed(selector));
        if (![CIFilter respondsToSelector:host]) {
            tell([NSString stringWithFormat:@"the host has no +%@, so there is nothing to compare against", selector]);
            continue;
        }
        CIFilter *theirs = ((CharonMsgSend0)objc_msgSend)((id)[CIFilter class], host);
        CIFilter *ours = ((CharonMsgSend0)objc_msgSend)((id)[CIFilter class], own);
        compared++;
        if (ours != theirs && ![ours.name isEqualToString:theirs.name]) {
            tell([NSString stringWithFormat:@"+%@ answers %@ where the host answers %@", selector,
                  ours ? ours.name : @"nil", theirs ? theirs.name : @"nil"]);
            continue;
        }
        if (object_getClass(ours) != object_getClass(theirs)) {
            tell([NSString stringWithFormat:@"+%@ class %s vs %s", selector,
                  class_getName(object_getClass(ours)), class_getName(object_getClass(theirs))]);
        }
        if (![ours.name isEqualToString:theirs.name]) {
            tell([NSString stringWithFormat:@"+%@ name %@ vs %@", selector, ours.name, theirs.name]);
        }
        if (![ours.inputKeys isEqualToArray:theirs.inputKeys]) tell([NSString stringWithFormat:@"+%@ inputKeys", selector]);
        if (![ours.outputKeys isEqualToArray:theirs.outputKeys]) tell([NSString stringWithFormat:@"+%@ outputKeys", selector]);
        same_dictionary(ours.attributes, theirs.attributes, [NSString stringWithFormat:@"+%@ attributes", selector]);

        CIFilter *pair[2] = {ours, theirs};
        NSData *bytes[2] = {nil, nil};
        for (int i = 0; i < 2; i++) {
            if ([pair[i].inputKeys isEqualToArray:@[@"inputImage"]]) [pair[i] setValue:input forKey:@"inputImage"];
            @try {
                bytes[i] = bytes_of(pair[i].outputImage);
            } @catch (NSException *e) {
                bytes[i] = nil;
            }
        }
        if (bytes[0] && bytes[1]) {
            rendered++;
            if (![bytes[0] isEqualToData:bytes[1]]) tell([NSString stringWithFormat:@"+%@ output bytes", selector]);
        }
    }
    if (ported.count != 239) {
        tell([NSString stringWithFormat:@"the port's objects carry %lu prefixed constructors, not 239", (unsigned long)ported.count]);
    }
    printf("compared %ld of %lu port constructors against the host's own, %ld rendered and compared, %ld different\n",
           compared, (unsigned long)ported.count, rendered, different);
    return different ? 1 : 0;
}