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
//
// The release may carry that class in SOME of the releases a band is built for and in none
// of the others -- NSURLSessionStreamTask is such a name: CFNetwork carries it from 8.0 on,
// carrying no method of its own, and nothing below 8.0 carries it at all. Where the release
// has no class of the name, the loader has nothing to re-parent the proxy onto and nothing
// to adopt its members into, so the proxy IS the class and every class method below answers
// as CharonName itself: what it makes is an instance of self, what it answers about members
// is what its own chain answers, and what its superclass is is the superclass it was declared
// with. CHARON_ALIAS_OF(Name, Super) declares it; CHARON_ALIAS(Name) is that with NSObject,
// which is right for a name whose release class is NSObject's own descendant. One thing does
// not answer there and is written down in facts/: an application that asks the runtime for the
// name with NSClassFromString gets nil, where the port's own class used to answer, because the
// class it would have to replace is a class of Charon's own and the release's own name belongs
// to no class on such a release.
struct charon_alias {
    const void *proxy;
    const char *name;
};

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// The released answer is the release's own, and only where the release has the class: the test is
// the class itself, so a release that carries none of the name takes the own answer instead of
// messaging nil.
#define CHARON_ALIAS_ANSWER(Name, own, released) \
    ((__bridge const void *)self == (const void *)&charon_alias_class_##Name && objc_getClass(#Name) ? (released) : (own))

// What a class answers about a member, walking its own chain: the question is about the class,
// and [super ...] answers it about the class above it, which is not the class asked about.
static BOOL charon_alias_answers(Class cls, SEL selector, BOOL class_methods)
{
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        if ((class_methods ? class_getClassMethod(current, selector) : class_getInstanceMethod(current, selector))) {
            return YES;
        }
    }
    return NO;
}

static Method charon_alias_method(Class cls, SEL selector, BOOL class_methods)
{
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        Method found = class_methods ? class_getClassMethod(current, selector) : class_getInstanceMethod(current, selector);
        if (found) {
            return found;
        }
    }
    return NULL;
}

#define CHARON_ALIAS_OF(Name, Super)                                                                               \
    extern char charon_alias_class_##Name __asm__("_OBJC_CLASS_$_Charon" #Name);                                   \
                                                                                                                   \
    @interface Charon##Name : Super                                                                                \
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
        return CHARON_ALIAS_ANSWER(Name, class_createInstance(self, 0), [objc_getClass(#Name) alloc]);             \
    }                                                                                                              \
                                                                                                                   \
    + (id)allocWithZone:(NSZone *)zone                                                                             \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, class_createInstance(self, 0), [objc_getClass(#Name) allocWithZone:zone]); \
    }                                                                                                              \
                                                                                                                   \
    + (Class)superclass                                                                                            \
    {                                                                                                              \
        Class found = CHARON_ALIAS_ANSWER(Name, class_getSuperclass(self), [objc_getClass(#Name) superclass]);     \
        return (__bridge const void *)found == (const void *)&charon_alias_class_##Name ? objc_getClass(#Name) : found; \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)isSubclassOfClass:(Class)aClass                                                                        \
    {                                                                                                              \
        if ((__bridge const void *)self == (const void *)&charon_alias_class_##Name && objc_getClass(#Name)) {      \
            return [objc_getClass(#Name) isSubclassOfClass:aClass];                                                 \
        }                                                                                                          \
        for (Class current = self; current; current = class_getSuperclass(current)) {                             \
            if (current == aClass) {                                                                               \
                return YES;                                                                                        \
            }                                                                                                      \
        }                                                                                                          \
        return NO;                                                                                                 \
    }                                                                                                              \
                                                                                                                   \
    + (BOOL)instancesRespondToSelector:(SEL)selector                                                               \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, charon_alias_answers(self, selector, false),                              \
                                   [objc_getClass(#Name) instancesRespondToSelector:selector]);                    \
    }                                                                                                              \
                                                                                                                   \
    + (IMP)instanceMethodForSelector:(SEL)selector                                                                 \
    {                                                                                                              \
        return CHARON_ALIAS_ANSWER(Name, method_getImplementation(charon_alias_method(self, selector, false)),      \
                                   [objc_getClass(#Name) instanceMethodForSelector:selector]);                     \
    }                                                                                                              \
                                                                                                                   \
    + (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)selector                                        \
    {                                                                                                              \
        Class asked = CHARON_ALIAS_ANSWER(Name, self, objc_getClass(#Name));                                       \
        const char *types = method_getTypeEncoding(charon_alias_method(asked, selector, false));                   \
        return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;                                     \
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
        return CHARON_ALIAS_ANSWER(Name, method_getImplementation(charon_alias_method(self, selector, true)),       \
                                   [objc_getClass(#Name) methodForSelector:selector]);                            \
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

#define CHARON_ALIAS(Name) CHARON_ALIAS_OF(Name, NSObject)
#endif

#endif
