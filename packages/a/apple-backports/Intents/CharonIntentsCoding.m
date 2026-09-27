//
//  CharonIntentsCoding.m
//  Intents
//
//  The three functions CharonIntentsCoding.h declares, and nothing else: this file exports no
//  symbol of the framework's surface, so the package's release check has no API to place in an
//  object of its own and every band keeps it.
//

#import "CharonIntentsCoding.h"

#import <string.h>

#import <CoreLocation/CoreLocation.h>
#import <string.h>

#import <objc/message.h>
#import <objc/runtime.h>

// Whether the property an ivar belongs to is declared copy, which the copy below has to honour:
// a property declared copy owns one of its own object and a property declared strong or retain
// shares the original's, and a copy that turned the first into the second would be a different
// answer from the one the header gives.
//
// The two are matched the way the runtime pairs them and not by name: a property's attributes end
// in its backing ivar (T@"NSString",C,N,V_name), and a property whose ivar is not spelled after
// it would be missed by any name comparison - which is how a lookup by the ivar's own name, with
// its leading underscore, found nothing at all and made every object ivar a copy.
static BOOL charon_intents_ivar_is_copy(Class owner, const char *name)
{
    unsigned count = 0;
    objc_property_t *properties = class_copyPropertyList(owner, &count);
    BOOL copy = YES;
    for (unsigned index = 0; index < count; index++) {
        const char *attributes = property_getAttributes(properties[index]);
        const char *ivar = attributes ? strstr(attributes, ",V_") : NULL;
        if (!ivar) {
            continue;
        }
        if (strcmp(ivar + 3, name) != 0) {
            continue;
        }
        // C is copy; R is retain and S is strong, and both share the original's object. An
        // attribute list with neither of the three is a property of some other ownership, and
        // copying is the reading that cannot let the two objects share anything mutable.
        copy = strchr(attributes, 'C') != NULL || (strchr(attributes, 'R') == NULL &&
                                                   strchr(attributes, 'S') == NULL);
        break;
    }
    free(properties);
    return copy;
}

id charon_intents_super_init(id object, Class superclass)
{
    struct objc_super parent = { object, superclass };
    return ((id (*)(struct objc_super *, SEL, Class))objc_msgSendSuper)(&parent, @selector(init), superclass);
}

// The classes an Intents archive nests besides the Intents classes themselves: the containers
// Foundation's own archives are built from, and the value types. Every class of this process
// whose name begins with IN is in the set as well, which is what an archive of an Intents object
// may hold, and it is read from the runtime once instead of written out here so a class of a
// later group of this package is allowed without this file naming it.
NSSet *charon_intents_allowed_classes(void)
{
    static NSSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *classes = [NSMutableSet setWithObjects:
                                 [NSArray class], [NSDictionary class], [NSSet class],
                                 [NSOrderedSet class], [NSIndexSet class], [NSCharacterSet class],
                                 [NSString class], [NSAttributedString class], [NSNumber class],
                                 [NSValue class], [NSData class], [NSDate class], [NSDateComponents class],
                                 [NSDateInterval class], [NSURL class], [NSUUID class], [NSError class],
                                 [NSLocale class], [NSRegularExpression class], [CLPlacemark class], nil];
        unsigned count = objc_getClassList(NULL, 0);
        if (count > 0) {
            Class *loaded = (Class *)malloc(sizeof(Class) * count);
            count = objc_getClassList(loaded, count);
            for (unsigned index = 0; index < count; index++) {
                const char *name = class_getName(loaded[index]);
                if (name && name[0] == 'I' && name[1] == 'N' && class_getSuperclass(loaded[index])) {
                    [classes addObject:loaded[index]];
                }
            }
            free(loaded);
        }
        allowed = [classes copy];
    });
    return allowed;
}

// The key one ivar is carried under names the class that owns the ivar and the ivar's own name,
// so two classes of one hierarchy that both have a "date" never read each other's.
static NSString *charon_intents_key(Class owner, const char *name)
{
    return [NSString stringWithFormat:@"%s.%s", class_getName(owner), name];
}

// An ivar that holds a pointer to an object, a pointer to something that is not one (a block's
// context, a C pointer), or a value of the class's own shape.
enum { CharonIntentsObject, CharonIntentsOpaque, CharonIntentsValue };

static int charon_intents_kind(Ivar ivar, NSUInteger *size)
{
    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding) {
        return CharonIntentsOpaque;
    }
    if (encoding[0] == '@') {
        return CharonIntentsObject;
    }
    if (encoding[0] == '^' || encoding[0] == '#' || encoding[0] == ':') {
        return CharonIntentsOpaque;
    }
    NSGetSizeAndAlignment(encoding, size, NULL);
    return CharonIntentsValue;
}

void charon_intents_encode(id object, NSCoder *coder)
{
    for (Class owner = [object class]; owner && owner != [NSObject class]; owner = class_getSuperclass(owner)) {
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(owner, &count);
        for (unsigned index = 0; index < count; index++) {
            NSUInteger size = 0;
            int kind = charon_intents_kind(ivars[index], &size);
            NSString *key = charon_intents_key(owner, ivar_getName(ivars[index]));
            if (kind == CharonIntentsObject) {
                id value = object_getIvar(object, ivars[index]);
                if (value) {
                    [coder encodeObject:value forKey:key];
                }
            } else if (kind == CharonIntentsValue && size > 0) {
                const char *bytes = (const char *)(__bridge void *)object + ivar_getOffset(ivars[index]);
                [coder encodeObject:[NSData dataWithBytes:bytes length:size] forKey:key];
            }
        }
        free(ivars);
    }
}

void charon_intents_decode(id object, NSCoder *coder)
{
    for (Class owner = [object class]; owner && owner != [NSObject class]; owner = class_getSuperclass(owner)) {
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(owner, &count);
        for (unsigned index = 0; index < count; index++) {
            NSUInteger size = 0;
            int kind = charon_intents_kind(ivars[index], &size);
            NSString *key = charon_intents_key(owner, ivar_getName(ivars[index]));
            char *bytes = (char *)(__bridge void *)object + ivar_getOffset(ivars[index]);
            if (kind == CharonIntentsObject) {
                id value = [coder decodeObjectOfClasses:charon_intents_allowed_classes() forKey:key];
                if (value) {
                    object_setIvar(object, ivars[index], value);
                }
            } else if (kind == CharonIntentsValue && size > 0) {
                NSData *data = [coder decodeObjectOfClass:[NSData class] forKey:key];
                if (data.length == size) {
                    memcpy(bytes, data.bytes, size);
                }
            }
        }
        free(ivars);
    }
}

void charon_intents_copy(id copy, id object)
{
    for (Class owner = [object class]; owner && owner != [NSObject class]; owner = class_getSuperclass(owner)) {
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(owner, &count);
        for (unsigned index = 0; index < count; index++) {
            NSUInteger size = 0;
            int kind = charon_intents_kind(ivars[index], &size);
            if (kind == CharonIntentsObject) {
                // The copy owns what it is handed the way the property says: a property declared
                // copy gets one of its own, and a property declared strong or retain shares the
                // original's, so the two objects share nothing the header says they should.
                id value = object_getIvar(object, ivars[index]);
                id owned = (value && charon_intents_ivar_is_copy(owner, ivar_getName(ivars[index])) &&
                            [value respondsToSelector:@selector(copy)]) ? [value copy] : value;
                object_setIvar(copy, ivars[index], owned);
            } else if (kind == CharonIntentsValue && size > 0) {
                NSUInteger offset = ivar_getOffset(ivars[index]);
                memcpy((char *)(__bridge void *)copy + offset,
                       (const char *)(__bridge void *)object + offset, size);
            }
        }
        free(ivars);
    }
}
