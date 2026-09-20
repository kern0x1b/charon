#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static Class native_class(void)
{
    static Class native;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        native = objc_getClass("NSTextTab");
    });
    return native;
}

@interface CharonNSTextTab : NSObject
+ (NSCharacterSet *)columnTerminatorsForLocale:(NSLocale *)locale;
@end

@implementation CharonNSTextTab

+ (void)load
{
    Class native = native_class();
    Method terminators = class_getClassMethod(self, @selector(columnTerminatorsForLocale:));
    if (native && !class_getClassMethod(native, @selector(columnTerminatorsForLocale:)))
        class_addMethod(object_getClass(native), @selector(columnTerminatorsForLocale:), method_getImplementation(terminators), method_getTypeEncoding(terminators));
}

+ (NSCharacterSet *)columnTerminatorsForLocale:(NSLocale *)locale
{
    NSString *separator = locale ? [locale objectForKey:NSLocaleDecimalSeparator] : @".";
    return [NSCharacterSet characterSetWithCharactersInString:separator.length ? separator : @"."];
}

+ (Class)class
{
    return native_class();
}

+ (id)alloc
{
    return [native_class() alloc];
}

+ (id)allocWithZone:(NSZone *)zone
{
    return [native_class() allocWithZone:zone];
}

+ (BOOL)isSubclassOfClass:(Class)aClass
{
    return [native_class() isSubclassOfClass:aClass];
}

+ (id)forwardingTargetForSelector:(SEL)selector
{
    return native_class();
}

@end

__asm__(".globl _OBJC_CLASS_$_NSTextTab\n"
        ".set _OBJC_CLASS_$_NSTextTab, _OBJC_CLASS_$_CharonNSTextTab\n"
        ".globl _OBJC_METACLASS_$_NSTextTab\n"
        ".set _OBJC_METACLASS_$_NSTextTab, _OBJC_METACLASS_$_CharonNSTextTab\n");
