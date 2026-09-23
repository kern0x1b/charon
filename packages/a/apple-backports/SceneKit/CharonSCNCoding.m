#import "CharonSCN.h"
#import <objc/runtime.h>

@interface CharonSCNArchivedColor : NSObject <NSSecureCoding>
@property(nonatomic) CGFloat red, green, blue, alpha, white;
@property(nonatomic) BOOL isRGB;
@end

@implementation CharonSCNArchivedColor

@synthesize red = _red;
@synthesize green = _green;
@synthesize blue = _blue;
@synthesize alpha = _alpha;
@synthesize white = _white;
@synthesize isRGB = _isRGB;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init])) {
        NSDictionary *components = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], nil] forKey:@"NSComponents"];
        NSString *rgb = components[@"NSRGB"];
        NSString *white = components[@"NSWhite"];
        if (rgb.length) {
            NSArray<NSString *> *parts = [rgb componentsSeparatedByString:@" "];
            self.isRGB = YES;
            self.red = parts.count > 0 ? parts[0].doubleValue : 0;
            self.green = parts.count > 1 ? parts[1].doubleValue : 0;
            self.blue = parts.count > 2 ? parts[2].doubleValue : 0;
            self.alpha = parts.count > 3 ? parts[3].doubleValue : 1;
        } else if (white.length) {
            NSArray<NSString *> *parts = [white componentsSeparatedByString:@" "];
            self.isRGB = NO;
            self.white = parts.count > 0 ? parts[0].doubleValue : 0;
            self.alpha = parts.count > 1 ? parts[1].doubleValue : 1;
        } else {
            self.isRGB = YES;
            self.alpha = 1;
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (self.isRGB) {
        NSString *rgb = [NSString stringWithFormat:@"%g %g %g %g", self.red, self.green, self.blue, self.alpha];
        [coder encodeObject:@{@"NSRGB": rgb} forKey:@"NSComponents"];
    } else {
        NSString *white = [NSString stringWithFormat:@"%g %g", self.white, self.alpha];
        [coder encodeObject:@{@"NSWhite": white} forKey:@"NSComponents"];
    }
}

- (UIColor *)toUIColor
{
    if (self.isRGB) {
        return [UIColor colorWithRed:self.red green:self.green blue:self.blue alpha:self.alpha];
    }
    return [UIColor colorWithWhite:self.white alpha:self.alpha];
}

@end

@implementation CharonSCNCoding

+ (SCNVector3)decodeVector3:(NSCoder *)coder forKey:(NSString *)key
{
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey:key returnedLength:&length];
    if (bytes == NULL || length != sizeof(SCNVector3)) {
        return SCNVector3Make(0, 0, 0);
    }
    SCNVector3 vector;
    memcpy(&vector, bytes, sizeof(SCNVector3));
    return vector;
}

+ (void)encodeVector3:(SCNVector3)vector coder:(NSCoder *)coder forKey:(NSString *)key
{
    [coder encodeBytes:(const uint8_t *)&vector length:sizeof(SCNVector3) forKey:key];
}

+ (SCNVector4)decodeVector4:(NSCoder *)coder forKey:(NSString *)key
{
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey:key returnedLength:&length];
    if (bytes == NULL || length != sizeof(SCNVector4)) {
        return SCNVector4Make(0, 0, 0, 1);
    }
    SCNVector4 vector;
    memcpy(&vector, bytes, sizeof(SCNVector4));
    return vector;
}

+ (void)encodeVector4:(SCNVector4)vector coder:(NSCoder *)coder forKey:(NSString *)key
{
    [coder encodeBytes:(const uint8_t *)&vector length:sizeof(SCNVector4) forKey:key];
}

+ (UIColor *)decodeColor:(NSCoder *)coder forKey:(NSString *)key
{
    if (![coder containsValueForKey:key]) {
        return nil;
    }
    id decoded = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSData class], [UIColor class], nil] forKey:key];
    if ([decoded isKindOfClass:[UIColor class]]) {
        return decoded;
    }
    NSData *nested = decoded;
    if (![nested isKindOfClass:[NSData class]] || nested.length == 0) {
        return nil;
    }
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:nested];
    unarchiver.requiresSecureCoding = YES;
    [unarchiver setClass:[CharonSCNArchivedColor class] forClassName:@"NSColor"];
    CharonSCNArchivedColor *archived = nil;
    @try {
        archived = [unarchiver decodeObjectOfClass:[CharonSCNArchivedColor class] forKey:NSKeyedArchiveRootObjectKey];
    } @catch (NSException *exception) {
        return nil;
    }
    [unarchiver finishDecoding];
    return [archived toUIColor];
}

+ (NSURL *)decodePathContents:(NSCoder *)coder forKey:(NSString *)key
{
    if (![coder containsValueForKey:key]) {
        return nil;
    }
    id decoded = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], nil] forKey:key];
    NSString *path = nil;
    if ([decoded isKindOfClass:[NSDictionary class]]) {
        path = [(NSDictionary *)decoded objectForKey:@"path"];
    } else if ([decoded isKindOfClass:[NSString class]]) {
        path = decoded;
    }
    if (path.length == 0) {
        return nil;
    }
    return [NSURL URLWithString:[path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] relativeToURL:[self currentSourceURL]];
}

static NSMutableArray *CharonSCNSourceURLStack(void)
{
    static NSMutableArray<NSURL *> *stack;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stack = [NSMutableArray array];
    });
    return stack;
}

+ (void)pushSourceURL:(NSURL *)url
{
    [CharonSCNSourceURLStack() addObject:url ?: [NSNull null]];
}

+ (void)popSourceURL
{
    NSMutableArray *stack = CharonSCNSourceURLStack();
    if (stack.count) {
        [stack removeLastObject];
    }
}

+ (NSURL *)currentSourceURL
{
    id last = CharonSCNSourceURLStack().lastObject;
    return [last isKindOfClass:[NSURL class]] ? last : nil;
}

static const void *CharonSCNProvenanceKey = &CharonSCNProvenanceKey;

+ (void)markFound:(BOOL)found forKey:(NSString *)key onObject:(id)object
{
    if (object == nil) {
        return;
    }
    NSMutableDictionary<NSString *, NSNumber *> *provenance = objc_getAssociatedObject(object, CharonSCNProvenanceKey);
    if (!provenance) {
        provenance = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(object, CharonSCNProvenanceKey, provenance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    provenance[key] = @(found);
}

+ (BOOL)wasFound:(NSString *)key onObject:(id)object
{
    NSMutableDictionary<NSString *, NSNumber *> *provenance = objc_getAssociatedObject(object, CharonSCNProvenanceKey);
    return provenance[key].boolValue;
}

@end
