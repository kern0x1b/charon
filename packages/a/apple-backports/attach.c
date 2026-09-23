#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include "charon_alias.h"

#ifdef __LP64__
typedef struct mach_header_64 charon_header;
#else
typedef struct mach_header charon_header;
#endif

extern const charon_header __dso_handle;

static intptr_t charon_slide(void)
{
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        if ((const void *)_dyld_get_image_header(index) == (const void *)&__dso_handle)
            return _dyld_get_image_vmaddr_slide(index);
    }
    return 0;
}

static const void *charon_section(const charon_header *header, intptr_t slide, const char *segment, const char *section, unsigned long *size)
{
#ifdef __LP64__
    const struct section_64 *found = getsectbynamefromheader_64(header, segment, section);
#else
    const struct section *found = getsectbynamefromheader(header, segment, section);
#endif
    if (!found || found->size == 0)
        return NULL;
    *size = (unsigned long)found->size;
    return (const void *)((uintptr_t)found->addr + slide);
}

// Every alias of charon_alias.h in the images loaded so far: a library's categories on
// a class another library aliases are attached after that library is loaded.
static const struct charon_alias *charon_image_aliases(uint32_t image, size_t *count)
{
    unsigned long size = 0;
    const struct charon_alias *aliases = charon_section((const charon_header *)_dyld_get_image_header(image), _dyld_get_image_vmaddr_slide(image), "__DATA", "__charon_alias", &size);
    *count = aliases ? size / sizeof *aliases : 0;
    return aliases;
}

static struct charon_alias *charon_aliases(size_t *count)
{
    size_t total = 0, held;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        charon_image_aliases(index, &held);
        total += held;
    }
    struct charon_alias *found = calloc(total ? total : 1, sizeof *found);
    *count = 0;
    for (uint32_t index = 0; index < _dyld_image_count() && *count < total; index++) {
        const struct charon_alias *aliases = charon_image_aliases(index, &held);
        held = held < total - *count ? held : total - *count;
        if (held)
            memcpy(found + *count, aliases, held * sizeof *found);
        *count += held;
    }
    return found;
}

// A category written on a name charon_alias.h aliases belongs to the release's class.
static Class charon_release_class(Class cls, const struct charon_alias *aliases, size_t count)
{
    for (size_t index = 0; index < count; index++) {
        if (aliases[index].proxy == (const void *)cls)
            return objc_getClass(aliases[index].name);
    }
    return cls;
}

struct charon_list {
    uint32_t flags;
    uint32_t count;
};

struct charon_category {
    const char *name;
    Class cls;
    struct charon_list *instance_methods;
    struct charon_list *class_methods;
    struct charon_protocols *protocols;
    struct charon_list *instance_properties;
};

struct charon_protocols {
    uintptr_t count;
    const struct charon_protocol *list[];
};

struct charon_protocol {
    Class isa;
    const char *name;
};

struct charon_pending {
    Class cls;
    SEL name;
    IMP implementation;
    const char *types;
};

static const uint32_t charon_relative_methods = 0x80000000;

static int32_t charon_offset(const struct charon_list *list, uint32_t index, uint32_t field)
{
    uint32_t size = list->flags & 0xFFFC;
    const int32_t *at = (const int32_t *)((const char *)(list + 1) + index * size + field * sizeof(int32_t));
    return *at;
}

static const char *charon_relative(const struct charon_list *list, uint32_t index, uint32_t field)
{
    uint32_t size = list->flags & 0xFFFC;
    const char *at = (const char *)(list + 1) + index * size + field * sizeof(int32_t);
    return at + charon_offset(list, index, field);
}

static void charon_method(const struct charon_list *list, uint32_t index, const char **name, const char **types, IMP *implementation)
{
    if (list->flags & charon_relative_methods) {
        *name = *(const char *const *)charon_relative(list, index, 0);
        *types = charon_relative(list, index, 1);
        *implementation = (IMP)charon_relative(list, index, 2);
        return;
    }
    uint32_t size = list->flags & 0xFFFC;
    const void *const *entry = (const void *const *)((const char *)(list + 1) + index * size);
    *name = (const char *)entry[0];
    *types = (const char *)entry[1];
    *implementation = (IMP)entry[2];
}

static int charon_implements(Class cls, SEL selector)
{
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        unsigned count;
        Method *methods = class_copyMethodList(current, &count);
        int found = 0;
        for (unsigned index = 0; index < count && !found; index++)
            found = method_getName(methods[index]) == selector;
        free(methods);
        if (found)
            return 1;
    }
    return 0;
}

static size_t charon_collect(Class cls, const struct charon_list *list, struct charon_pending *pending, size_t used)
{
    if (!list)
        return used;
    for (uint32_t index = 0; index < list->count; index++) {
        const char *name, *types;
        IMP implementation;
        charon_method(list, index, &name, &types, &implementation);
        SEL selector = sel_registerName(name);
        if (!charon_implements(cls, selector))
            pending[used++] = (struct charon_pending){cls, selector, implementation, types};
    }
    return used;
}

static void charon_add_properties(Class cls, const struct charon_list *list)
{
    if (!list || !class_addProperty)
        return;
    uint32_t size = list->flags & 0xFFFC;
    for (uint32_t index = 0; index < list->count; index++) {
        const char *const *entry = (const char *const *)((const char *)(list + 1) + index * size);
        if (class_getProperty(cls, entry[0]))
            continue;
        char *attributes = strdup(entry[1]);
        unsigned count = 1;
        for (char *cursor = attributes; *cursor; cursor++)
            count += *cursor == ',';
        objc_property_attribute_t parsed[count];
        char names[count][2];
        unsigned used = 0;
        char *state;
        for (char *item = strtok_r(attributes, ",", &state); item; item = strtok_r(NULL, ",", &state)) {
            names[used][0] = item[0];
            names[used][1] = 0;
            parsed[used] = (objc_property_attribute_t){names[used], item + 1};
            used++;
        }
        class_addProperty(cls, entry[0], parsed, used);
        free(attributes);
    }
}

// ld64 merges a category written on an alias into the class the alias names, CharonName,
// since both are in one image, so the release's class takes from CharonName whatever it and
// its superclasses lack. CharonName's own +class, +alloc and forwarding are NSObject's
// selectors, which the release's class answers already.
static unsigned charon_method_count(Class cls)
{
    unsigned count = 0;
    free(class_copyMethodList(cls, &count));
    return count;
}

static size_t charon_adopt_methods(Class release, Class proxy, struct charon_pending *pending, size_t used)
{
    unsigned count = 0;
    Method *methods = class_copyMethodList(proxy, &count);
    for (unsigned index = 0; index < count; index++) {
        SEL selector = method_getName(methods[index]);
        if (!charon_implements(release, selector))
            pending[used++] = (struct charon_pending){release, selector, method_getImplementation(methods[index]), method_getTypeEncoding(methods[index])};
    }
    free(methods);
    return used;
}

static void charon_adopt_declarations(Class release, Class proxy)
{
    unsigned count = 0;
    Protocol **protocols = class_copyProtocolList(proxy, &count);
    for (unsigned index = 0; index < count; index++) {
        if (!class_conformsToProtocol(release, protocols[index]))
            class_addProtocol(release, protocols[index]);
    }
    free(protocols);
    if (!class_addProperty)
        return;
    objc_property_t *properties = class_copyPropertyList(proxy, &count);
    for (unsigned index = 0; index < count; index++) {
        const char *name = property_getName(properties[index]);
        if (class_getProperty(release, name))
            continue;
        unsigned held = 0;
        objc_property_attribute_t *attributes = property_copyAttributeList(properties[index], &held);
        class_addProperty(release, name, attributes, held);
        free(attributes);
    }
    free(properties);
}

__attribute__((constructor)) static void charon_backports_attach(void)
{
    unsigned long size;
    const struct charon_category *const *categories = (const struct charon_category *const *)charon_section(&__dso_handle, charon_slide(), "__DATA", "__charon_catlist", &size);
    size_t count = categories ? size / sizeof(void *) : 0;
    size_t capacity = 0;
    for (size_t index = 0; index < count; index++) {
        const struct charon_category *category = categories[index];
        capacity += (category->instance_methods ? category->instance_methods->count : 0) + (category->class_methods ? category->class_methods->count : 0);
    }
    unsigned long own_size = 0;
    const struct charon_alias *own = charon_section(&__dso_handle, charon_slide(), "__DATA", "__charon_alias", &own_size);
    size_t own_count = own ? own_size / sizeof *own : 0;
    Class *releases = calloc(own_count ? own_count : 1, sizeof *releases);
    for (size_t index = 0; index < own_count; index++) {
        releases[index] = objc_getClass(own[index].name);
        if (!releases[index])
            continue;
        // class_copyMethodList reads a class as realized without checking; looking it up realizes it.
        objc_lookUpClass(class_getName((Class)own[index].proxy));
        capacity += charon_method_count((Class)own[index].proxy) + charon_method_count(object_getClass((id)own[index].proxy));
    }
    size_t alias_count;
    struct charon_alias *aliases = charon_aliases(&alias_count);
    Class *classes = calloc(count ? count : 1, sizeof *classes);
    for (size_t index = 0; index < count; index++) {
        Class cls = categories[index]->cls;
        classes[index] = cls ? charon_release_class(cls, aliases, alias_count) : Nil;
    }
    free(aliases);
    struct charon_pending *pending = calloc(capacity ? capacity : 1, sizeof *pending);
    size_t used = 0;
    for (size_t index = 0; index < count; index++) {
        const struct charon_category *category = categories[index];
        Class cls = classes[index];
        if (!cls)
            continue;
        objc_lookUpClass(class_getName(cls));
        used = charon_collect(cls, category->instance_methods, pending, used);
        used = charon_collect(object_getClass((id)cls), category->class_methods, pending, used);
    }
    for (size_t index = 0; index < own_count; index++) {
        if (!releases[index])
            continue;
        Class proxy = (Class)own[index].proxy;
        used = charon_adopt_methods(releases[index], proxy, pending, used);
        used = charon_adopt_methods(object_getClass((id)releases[index]), object_getClass((id)proxy), pending, used);
    }
    for (size_t index = 0; index < used; index++)
        class_addMethod(pending[index].cls, pending[index].name, pending[index].implementation, pending[index].types);
    free(pending);
    for (size_t index = 0; index < own_count; index++) {
        if (releases[index])
            charon_adopt_declarations(releases[index], (Class)own[index].proxy);
    }
    free(releases);
    for (size_t index = 0; index < count; index++) {
        const struct charon_category *category = categories[index];
        Class cls = classes[index];
        if (!cls)
            continue;
        for (uintptr_t protocol = 0; category->protocols && protocol < category->protocols->count; protocol++) {
            Protocol *found = objc_getProtocol(category->protocols->list[protocol]->name);
            if (found && !class_conformsToProtocol(cls, found))
                class_addProtocol(cls, found);
        }
        charon_add_properties(cls, category->instance_properties);
    }
    free(classes);
}
