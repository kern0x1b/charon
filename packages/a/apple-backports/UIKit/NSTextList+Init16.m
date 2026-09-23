#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation NSTextList (CharonInit16)

// The release's own list, through its own initializer and starting number.
- (instancetype)initWithMarkerFormat:(NSTextListMarkerFormat)markerFormat options:(NSTextListOptions)options startingItemNumber:(NSInteger)startingItemNumber
{
    if ((self = [self initWithMarkerFormat:markerFormat options:options]))
        self.startingItemNumber = startingItemNumber;
    return self;
}

@end

// iOS 6 carries NSTextList in UIFoundation without exporting the class, so the
// category above reaches it through a weak reference that is NULL there, and the
// library's loader skips a category with no class. The method is added by name.
@interface CharonTextListInit16 : NSObject
@end

@implementation CharonTextListInit16

+ (void)load
{
    Class list = objc_getClass("NSTextList");
    SEL selector = @selector(initWithMarkerFormat:options:startingItemNumber:);
    Method method = class_getInstanceMethod(self, selector);
    if (list && !class_getInstanceMethod(list, selector))
        class_addMethod(list, selector, method_getImplementation(method), method_getTypeEncoding(method));
}

- (instancetype)initWithMarkerFormat:(NSTextListMarkerFormat)markerFormat options:(NSTextListOptions)options startingItemNumber:(NSInteger)startingItemNumber
{
    NSTextList *list = [(NSTextList *)self initWithMarkerFormat:markerFormat options:options];
    list.startingItemNumber = startingItemNumber;
    return (id)list;
}

@end
