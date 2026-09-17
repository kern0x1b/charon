#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

extern const struct mach_header_64 __dso_handle;

struct host_list {
    uint32_t flags;
    uint32_t count;
};

struct host_category {
    const char *name;
    Class cls;
    struct host_list *instance_methods;
    struct host_list *class_methods;
};

static void host_method(const struct host_list *list, uint32_t index, const char **name, const char **types, IMP *implementation)
{
    uint32_t size = list->flags & 0xFFFC;
    const char *entry = (const char *)(list + 1) + index * size;
    if (list->flags & 0x80000000) {
        const int32_t *offsets = (const int32_t *)entry;
        *name = *(const char *const *)(entry + offsets[0]);
        *types = entry + sizeof(int32_t) + offsets[1];
        *implementation = (IMP)(entry + 2 * sizeof(int32_t) + offsets[2]);
        return;
    }
    const void *const *pointers = (const void *const *)entry;
    *name = pointers[0];
    *types = pointers[1];
    *implementation = (IMP)pointers[2];
}

static void host_add(Class cls, const struct host_list *list, const char *prefix)
{
    for (uint32_t index = 0; list && index < list->count; index++) {
        const char *name, *types;
        IMP implementation;
        host_method(list, index, &name, &types, &implementation);
        size_t length = strlen(prefix) + strlen(name) + 1;
        char *prefixed = malloc(length);
        strcpy(prefixed, prefix);
        strcat(prefixed, name);
        if (!class_addMethod(cls, sel_registerName(prefixed), implementation, types))
            abort();
        free(prefixed);
    }
}

void host_attach_prefixed(const char *prefix)
{
    unsigned long size;
    const struct host_category *const *categories = (const struct host_category *const *)getsectiondata(&__dso_handle, "__DATA", "__charon_catlist", &size);
    if (!categories)
        categories = (const struct host_category *const *)getsectiondata(&__dso_handle, "__DATA_CONST", "__charon_catlist", &size);
    for (size_t index = 0; categories && index < size / sizeof(void *); index++) {
        const struct host_category *category = categories[index];
        host_add(category->cls, category->instance_methods, prefix);
        host_add(object_getClass((id)category->cls), category->class_methods, prefix);
    }
}
