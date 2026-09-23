#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include "charon_alias.h"

#ifdef __LP64__
typedef struct mach_header_64 charon_header;
typedef struct segment_command_64 charon_segment;
#define CHARON_SEGMENT LC_SEGMENT_64
#else
typedef struct mach_header charon_header;
typedef struct segment_command charon_segment;
#define CHARON_SEGMENT LC_SEGMENT
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

static uintptr_t charon_uleb(const uint8_t **at, const uint8_t *end)
{
    uintptr_t value = 0;
    unsigned shift = 0;
    while (*at < end) {
        uint8_t byte = *(*at)++;
        if (shift < sizeof value * 8)
            value |= (uintptr_t)(byte & 0x7F) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    return value;
}

static const struct load_command *charon_command(uint32_t cmd, uint32_t skipped)
{
    const struct load_command *command = (const struct load_command *)((const charon_header *)&__dso_handle + 1);
    for (uint32_t index = 0; index < __dso_handle.ncmds; index++) {
        if (command->cmd == cmd && skipped-- == 0)
            return command;
        command = (const struct load_command *)((const char *)command + command->cmdsize);
    }
    return NULL;
}

// A category's class reference is NULL when the release has the class without
// exporting it: the reference is a weak import dyld could not bind. The symbol
// the reference was bound to still names the class, and the runtime has it by
// that name. The binding is read from this image's own bind opcodes.
static Class charon_bound_class(const void *slot)
{
    const charon_segment *linkedit = NULL;
    for (uint32_t index = 0; !linkedit && charon_command(CHARON_SEGMENT, index); index++) {
        const charon_segment *segment = (const charon_segment *)charon_command(CHARON_SEGMENT, index);
        if (strcmp(segment->segname, SEG_LINKEDIT) == 0)
            linkedit = segment;
    }
    const struct dyld_info_command *info = (const struct dyld_info_command *)charon_command(LC_DYLD_INFO_ONLY, 0);
    if (!info)
        info = (const struct dyld_info_command *)charon_command(LC_DYLD_INFO, 0);
    if (!linkedit || !info || info->bind_size == 0)
        return Nil;
    intptr_t slide = charon_slide();
    const uint8_t *at = (const uint8_t *)(uintptr_t)(linkedit->vmaddr + slide + info->bind_off - linkedit->fileoff);
    const uint8_t *end = at + info->bind_size;
    const char *symbol = NULL;
    uintptr_t address = 0;
    int placed = 0;
    while (at < end) {
        uint8_t opcode = *at & BIND_OPCODE_MASK, immediate = *at & BIND_IMMEDIATE_MASK;
        at++;
        uintptr_t count = 1, skip = 0;
        switch (opcode) {
        case BIND_OPCODE_DONE:
            placed = 0;
            continue;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
        case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
        case BIND_OPCODE_SET_TYPE_IMM:
            continue;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
        case BIND_OPCODE_SET_ADDEND_SLEB:
            charon_uleb(&at, end);
            continue;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
            symbol = (const char *)at;
            at += strnlen(symbol, (size_t)(end - at)) + 1;
            continue;
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: {
            const charon_segment *segment = (const charon_segment *)charon_command(CHARON_SEGMENT, immediate);
            placed = segment != NULL;
            address = (placed ? (uintptr_t)(segment->vmaddr + slide) : 0) + charon_uleb(&at, end);
            continue;
        }
        case BIND_OPCODE_ADD_ADDR_ULEB:
            address += charon_uleb(&at, end);
            continue;
        case BIND_OPCODE_DO_BIND:
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
            skip = charon_uleb(&at, end);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
            skip = immediate * sizeof(void *);
            break;
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB:
            count = charon_uleb(&at, end);
            skip = charon_uleb(&at, end);
            break;
        default:
            return Nil;
        }
        for (uintptr_t index = 0; index < count; index++) {
            if (placed && symbol && address == (uintptr_t)slot) {
                static const char prefix[] = "_OBJC_CLASS_$_";
                return strncmp(symbol, prefix, sizeof prefix - 1) == 0 ? objc_getClass(symbol + sizeof prefix - 1) : Nil;
            }
            address += sizeof(void *) + skip;
        }
    }
    return Nil;
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
    size_t alias_count;
    struct charon_alias *aliases = charon_aliases(&alias_count);
    Class *classes = calloc(count ? count : 1, sizeof *classes);
    for (size_t index = 0; index < count; index++) {
        Class cls = categories[index]->cls ? categories[index]->cls : charon_bound_class(&categories[index]->cls);
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
    for (size_t index = 0; index < used; index++)
        class_addMethod(pending[index].cls, pending[index].name, pending[index].implementation, pending[index].types);
    free(pending);
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
