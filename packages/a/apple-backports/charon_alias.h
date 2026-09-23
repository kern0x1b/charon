#ifndef CHARON_ALIAS_H
#define CHARON_ALIAS_H

// A class the release carries without exporting it cannot be linked against: an
// application that names it does not start. CHARON_ALIAS(Name) defines CharonName,
// exports the release's name as an alias of it, and records the pair in
// __DATA,__charon_alias. Sent to, CharonName answers +class and +alloc with the
// release's class, so what is made, what the release hands out and [Name class] are
// one class; attach.c attaches a category written on Name to the release's class.
struct charon_alias {
    const void *proxy;
    const char *name;
};

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define CHARON_ALIAS(Name)                                                                                          \
    @interface Charon##Name : NSObject                                                                             \
    @end                                                                                                           \
                                                                                                                   \
    @implementation Charon##Name                                                                                   \
                                                                                                                   \
    + (Class)class                                                                                                 \
    {                                                                                                              \
        return objc_getClass(#Name);                                                                               \
    }                                                                                                              \
                                                                                                                   \
    + (id)alloc                                                                                                    \
    {                                                                                                              \
        return [objc_getClass(#Name) alloc];                                                                       \
    }                                                                                                              \
                                                                                                                   \
    + (id)allocWithZone:(NSZone *)zone                                                                             \
    {                                                                                                              \
        return [objc_getClass(#Name) allocWithZone:zone];                                                          \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)isSubclassOfClass:(Class)aClass                                                                        \
    {                                                                                                              \
        return [objc_getClass(#Name) isSubclassOfClass:aClass];                                                    \
    }                                                                                                              \
                                                                                                                   \
    + (id)forwardingTargetForSelector:(SEL)selector                                                                \
    {                                                                                                              \
        return objc_getClass(#Name);                                                                               \
    }                                                                                                              \
                                                                                                                   \
    @end                                                                                                           \
                                                                                                                   \
    __asm__(".globl _OBJC_CLASS_$_" #Name "\n"                                                                     \
            ".set _OBJC_CLASS_$_" #Name ", _OBJC_CLASS_$_Charon" #Name "\n"                                        \
            ".globl _OBJC_METACLASS_$_" #Name "\n"                                                                 \
            ".set _OBJC_METACLASS_$_" #Name ", _OBJC_METACLASS_$_Charon" #Name "\n");                              \
    extern char charon_alias_class_##Name __asm__("_OBJC_CLASS_$_Charon" #Name);                                   \
    __attribute__((used, section("__DATA,__charon_alias"))) static const struct charon_alias charon_alias_##Name = { \
        &charon_alias_class_##Name, #Name};
#endif

#endif
