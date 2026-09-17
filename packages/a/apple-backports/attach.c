#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

#ifdef __LP64__
typedef struct mach_header_64 charon_header;
#else
typedef struct mach_header charon_header;
#endif

extern const charon_header __dso_handle;

static const void *charon_section(const char *segment, const char *section, unsigned long *size)
{
#ifdef __LP64__
    const struct section_64 *found = getsectbynamefromheader_64(&__dso_handle, segment, section);
#else
    const struct section *found = getsectbynamefromheader(&__dso_handle, segment, section);
#endif
    if (!found || found->size == 0)
        return NULL;
    intptr_t slide = 0;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        if ((const void *)_dyld_get_image_header(index) == (const void *)&__dso_handle) {
            slide = _dyld_get_image_vmaddr_slide(index);
            break;
        }
    }
    *size = (unsigned long)found->size;
    return (const void *)((uintptr_t)found->addr + slide);
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

__attribute__((constructor)) static void charon_backports_attach(void)
{
    unsigned long size;
    const struct charon_category *const *categories = (const struct charon_category *const *)charon_section("__DATA", "__charon_catlist", &size);
    size_t count = categories ? size / sizeof(void *) : 0;
    size_t capacity = 0;
    for (size_t index = 0; index < count; index++) {
        const struct charon_category *category = categories[index];
        capacity += (category->instance_methods ? category->instance_methods->count : 0) + (category->class_methods ? category->class_methods->count : 0);
    }
    struct charon_pending *pending = calloc(capacity ? capacity : 1, sizeof *pending);
    size_t used = 0;
    for (size_t index = 0; index < count; index++) {
        const struct charon_category *category = categories[index];
        if (!category->cls)
            continue;
        objc_lookUpClass(class_getName(category->cls));
        used = charon_collect(category->cls, category->instance_methods, pending, used);
        used = charon_collect(object_getClass((id)category->cls), category->class_methods, pending, used);
    }
    for (size_t index = 0; index < used; index++)
        class_addMethod(pending[index].cls, pending[index].name, pending[index].implementation, pending[index].types);
    free(pending);
    for (size_t index = 0; index < count; index++) {
        const struct charon_category *category = categories[index];
        if (!category->cls)
            continue;
        for (uintptr_t protocol = 0; category->protocols && protocol < category->protocols->count; protocol++) {
            Protocol *found = objc_getProtocol(category->protocols->list[protocol]->name);
            if (found && !class_conformsToProtocol(category->cls, found))
                class_addProtocol(category->cls, found);
        }
        charon_add_properties(category->cls, category->instance_properties);
    }
}
