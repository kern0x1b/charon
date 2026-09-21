#import "pasteboard10-cases.h"

static UIImage *square(void)
{
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), YES, 1);
    [[UIColor greenColor] setFill];
    UIRectFill(CGRectMake(0, 0, 4, 4));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static NSString *flags(UIPasteboard *pasteboard)
{
    return [NSString stringWithFormat:@"%d%d%d%d", pasteboard.hasStrings ? 1 : 0, pasteboard.hasURLs ? 1 : 0,
                                      pasteboard.hasImages ? 1 : 0, pasteboard.hasColors ? 1 : 0];
}

static NSString *objects(UIPasteboard *pasteboard)
{
    return [NSString stringWithFormat:@"%d%d%d%d", pasteboard.strings.count > 0 ? 1 : 0, pasteboard.URLs.count > 0 ? 1 : 0,
                                      pasteboard.images.count > 0 ? 1 : 0, pasteboard.colors.count > 0 ? 1 : 0];
}

static void take(UIPasteboard *pasteboard, NSString *name, Pasteboard10Recorder record)
{
    record(name, [NSString stringWithFormat:@"%@ | %@", flags(pasteboard), objects(pasteboard)]);
}

void pasteboard10_run(Pasteboard10Recorder record)
{
    UIPasteboard *pasteboard = [UIPasteboard pasteboardWithUniqueName];
    take(pasteboard, @"a pasteboard with nothing on it", record);

    pasteboard.items = @[];
    pasteboard.string = @"hello";
    take(pasteboard, @"a string", record);

    pasteboard.items = @[];
    pasteboard.string = @"https://example.com/";
    take(pasteboard, @"a string that reads as a URL", record);

    pasteboard.items = @[];
    pasteboard.URL = [NSURL URLWithString:@"https://example.com/"];
    take(pasteboard, @"a URL", record);

    pasteboard.items = @[];
    pasteboard.image = square();
    take(pasteboard, @"an image", record);

    pasteboard.items = @[];
    pasteboard.color = [UIColor redColor];
    take(pasteboard, @"a colour", record);

    pasteboard.items = @[];
    pasteboard.strings = @[@"one", @"two"];
    take(pasteboard, @"two strings", record);

    pasteboard.items = @[];
    pasteboard.URLs = @[[NSURL URLWithString:@"https://one.example/"], [NSURL URLWithString:@"https://two.example/"]];
    take(pasteboard, @"two URLs", record);

    pasteboard.items = @[];
    pasteboard.string = @"beside";
    pasteboard.image = square();
    take(pasteboard, @"an image set over a string", record);

    pasteboard.items = @[@{(NSString *)@"public.utf8-plain-text": @"beside"}, @{(NSString *)@"public.png": UIImagePNGRepresentation(square())}];
    take(pasteboard, @"a string in one item and an image in another", record);

    pasteboard.items = @[];
    [pasteboard setData:UIImagePNGRepresentation(square()) forPasteboardType:@"public.png"];
    take(pasteboard, @"the bytes of a PNG under public.png", record);

    pasteboard.items = @[];
    [pasteboard setData:[@"payload" dataUsingEncoding:NSUTF8StringEncoding] forPasteboardType:@"org.charon.backports.own-type"];
    take(pasteboard, @"bytes under a type of the application's own", record);

    pasteboard.items = @[];
    take(pasteboard, @"a pasteboard emptied again", record);

    [UIPasteboard removePasteboardWithName:pasteboard.name];
}
