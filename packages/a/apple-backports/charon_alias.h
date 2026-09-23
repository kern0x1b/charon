#ifndef CHARON_ALIAS_H
#define CHARON_ALIAS_H

// A class the release carries without exporting it cannot be linked against: an
// application that names it does not start. CHARON_ALIAS(Name) defines CharonName,
// exports the release's name as an alias of it, and records the pair in
// __DATA,__charon_alias. The library's loader (attach.c) makes CharonName a subclass of
// the release's class before anything uses it, so a subclass an application writes of
// Name inherits the release's class and is laid out after it. Sent to CharonName itself,
// the class methods below answer as the release's class does, so [Name class], what
// [Name alloc] makes and what the release hands out are one class; sent to a subclass,
// they answer as NSObject's do. ld64 merges a category written on Name in the same image
// into CharonName, and attach.c gives the release's class what CharonName has and the
// release's class lacks; a category on Name in another image is attached to the
// release's class by name.
struct charon_alias {
    const void *proxy;
    const char *name;
};

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define CHARON_ALIAS_ANSWER(Name, own, released) ((__bridge const void *)self == (const void *)&charon_alias_class_##Name ? (released) : (own))

#define CHARON_ALIAS(Name)                                                                                         \
    extern char charon_alias_class_##Name __asm__("_OBJC_CLASS_$_Charon" #Name);                                   \
                                                                                                                   \
    @interface Charon##Name : NSObject                                                                             \
    @end                                                                                                           \
                                                                                                                   \
    @implementation Charon##Name                                                                                   \
                                                                                                                   \
    + (Class)class                                                                                                 \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, self, objc_getClass(#Name));                                              \
    }                                                                                                              \
                                                                                                                   \
    + (id)alloc                                                                                                    \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super alloc], [objc_getClass(#Name) alloc]);                             \
    }                                                                                                              \
                                                                                                                   \
    + (id)allocWithZone:(NSZone *)zone                                                                             \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super allocWithZone:zone], [objc_getClass(#Name) allocWithZone:zone]);   \
    }                                                                                                              \
                                                                                                                   \
    + (Class)superclass                                                                                            \
    {                                                                                                              \
        Class found = CHARON_ALIAS_ANSWER(Name, [super superclass], [objc_getClass(#Name) superclass]);            \
        return (__bridge const void *)found == (const void *)&charon_alias_class_##Name ? objc_getClass(#Name) : found; \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)isSubclassOfClass:(Class)aClass                                                                        \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super isSubclassOfClass:aClass], [objc_getClass(#Name) isSubclassOfClass:aClass]); \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)instancesRespondToSelector:(SEL)selector                                                               \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super instancesRespondToSelector:selector],                              \
                                   [objc_getClass(#Name) instancesRespondToSelector:selector]);                    \
    }                                                                                                              \
                                                                                                                   \
    + (IMP)instanceMethodForSelector:(SEL)selector                                                                 \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super instanceMethodForSelector:selector],                               \
                                   [objc_getClass(#Name) instanceMethodForSelector:selector]);                     \
    }                                                                                                              \
                                                                                                                   \
    + (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)selector                                        \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super instanceMethodSignatureForSelector:selector],                      \
                                   [objc_getClass(#Name) instanceMethodSignatureForSelector:selector]);            \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)conformsToProtocol:(Protocol *)protocol                                                                \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super conformsToProtocol:protocol], [objc_getClass(#Name) conformsToProtocol:protocol]); \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)respondsToSelector:(SEL)selector                                                                       \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super respondsToSelector:selector], [objc_getClass(#Name) respondsToSelector:selector]); \
    }                                                                                                              \
                                                                                                                   \
    + (IMP)methodForSelector:(SEL)selector                                                                         \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super methodForSelector:selector], [objc_getClass(#Name) methodForSelector:selector]); \
    }                                                                                                              \
                                                                                                                   \
    + (NSString *)description                                                                                      \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super description], [objc_getClass(#Name) description]);                 \
    }                                                                                                              \
                                                                                                                   \
    + (NSUInteger)hash                                                                                             \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super hash], [objc_getClass(#Name) hash]);                               \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)isEqual:(id)object                                                                                     \
    {                                                                                                              \
        id other = (__bridge const void *)object == (const void *)&charon_alias_class_##Name ? objc_getClass(#Name) : object; \
        return CHARON_ALIAS_ANSWER(Name, [super isEqual:other], [objc_getClass(#Name) isEqual:other]);             \
    }                                                                                                              \
                                                                                                                   \
    + (id)forwardingTargetForSelector:(SEL)selector                                                                \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, [super forwardingTargetForSelector:selector], objc_getClass(#Name));      \
    }                                                                                                              \
                                                                                                                   \
    @end                                                                                                           \
                                                                                                                   \
    __asm__(".globl _OBJC_CLASS_$_" #Name "\n"                                                                     \
            ".set _OBJC_CLASS_$_" #Name ", _OBJC_CLASS_$_Charon" #Name "\n"                                        \
            ".globl _OBJC_METACLASS_$_" #Name "\n"                                                                 \
            ".set _OBJC_METACLASS_$_" #Name ", _OBJC_METACLASS_$_Charon" #Name "\n");                              \
    __attribute__((used, section("__DATA,__charon_alias"))) static const struct charon_alias charon_alias_##Name = { \
        &charon_alias_class_##Name, #Name};
#endif

#endif
