//
//  params-probe.m
//  Matter
//
//  What this Mac's Matter.framework answers for the port's plain data classes, in one binary, measured.
//
//  One program, no compile-time knowledge of any class: the class names, the property names, their types and
//  the alias pairs all arrive in the driver file named as argv[1], so the same source measures the host and
//  can measure the port, and a difference between the two is a difference in behaviour and not in spelling.
//
//  Three questions, one per family of line in the driver:
//
//      <Class> TAB own                                            the class's own members, in the
//                                                                   order the header declares them
//      <Class> TAB <alias> TAB <successor> TAB alias              an alias pair, successor from the SDK's
//                                                                   own deprecation text
//  and for each class:
//
//    (i)  does the CLASS ITSELF implement -description? `class_copyMethodList` on the class, not
//        respondsToSelector:, which every class inherits; and what string does a fresh object print?
//    (ii) for an alias, which OTHER member of the class shares its storage, both ways: the alias is set to a
//        sentinel and every own member is read, and then every own member is set and the alias is read. That
//        finds the shared storage without being told the name, which is what settles the 51 deprecations
//        whose text is prose ("Please use the storage property") rather than a member name.
//    (iii) a class the host does not have is reported absent, and the port keeps its header-derived answer
//        for it; the caller says so per class.
//
//  The output is the data file tools/matter-generate.py reads, and its provenance - the host's own version
//  string and the date - is written with it.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/// The date the table was measured, written into the file beside the host's own version string, so a
/// reader can tell which binary answered without asking. It is the date this tree's run happened.
#define MEASURED "2026-10-03"

static NSString *render(id value)
{
    if (value == nil) {
        return @"(nil)";
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSString stringWithFormat:@"NSNumber(%@)", value];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"NSString(%@)", value];
    }
    if ([value isKindOfClass:[NSData class]]) {
        return [NSString stringWithFormat:@"NSData(%lu)", (unsigned long)[(NSData *)value length]];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"NSArray(%lu)", (unsigned long)[(NSArray *)value count]];
    }
    return [NSString stringWithFormat:@"%@(%@)", NSStringFromClass([value class]), value];
}

static id safeRead(id object, NSString *key)
{
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

/// A value of one member's OWN type, different for each index, so writing it twice with two indexes and
/// watching the other member move is a measurement of shared storage and not of a sentinel's identity.
///
/// The type decides the value, and that is the whole point: the first version of this probe wrote an NSValue
/// through KVC whatever the member's type was, and a BOOL or a uint64_t member answers that with
/// NSInvalidArgumentException - which is how 6 rows came to read `raised` and looked like host behaviour.
/// They were the probe's own artifact, and the six members that raised are the six whose type differs from
/// their successor's, which is exactly the case a single sentinel cannot serve.
static id typedValue(NSString *type, NSInteger index, NSString *tag)
{
    NSString *spelling = type;
    for (NSString *word in @[ @"_Nonnull", @"_Nullable" ]) {
        spelling = [spelling stringByReplacingOccurrencesOfString:word withString:@""];
    }
    spelling = [[spelling componentsSeparatedByString:@"<"] firstObject];
    spelling = [spelling stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    static NSMutableDictionary *marks = nil;
    if (marks == nil) {
        marks = [NSMutableDictionary dictionary];
    }
    if ([spelling hasSuffix:@"*"]) {
        NSString *key = [NSString stringWithFormat:@"%@/%ld", tag, (long)index];
        if (marks[key] == nil) {
            marks[key] = [NSValue valueWithRange:NSMakeRange(0x5AFE0000 + (index * 4096), 1)];
        }
        return marks[key];
    }
    return @((long)(index == 0 ? 0 : (index == 1 ? 1 : 42)));
}

/// Write through the SETTER by name, falling back to KVC. The setter is the member's own API and a scalar
/// member has no KVC path that takes a value of its own type without boxing it first.
static BOOL writeValue(id object, NSString *key, id value)
{
    SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%c:", [[key substringToIndex:1]
                                                                                 uppercaseString],
                                      [[key substringFromIndex:1] characterAtIndex:0]]);
    if ([object respondsToSelector:setter]) {
        ((void (*)(id, SEL, id))objc_msgSend)(object, setter, value);
        return YES;
    }
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

/// The property names the CLASS ITSELF declares, in the runtime's own order, inherited ones excluded.
static NSArray<NSString *> *ownProperties(Class cls)
{
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    unsigned int count = 0;
    objc_property_t *list = class_copyPropertyList(cls, &count);
    for (unsigned int index = 0; index < count; index++) {
        [found addObject:[NSString stringWithUTF8String:property_getName(list[index])]];
    }
    free(list);
    return found;
}

/// Whether the class's OWN method list carries -description. respondsToSelector: cannot answer it: every
/// class inherits NSObject's, so a class that does not override it answers YES either way.
static BOOL ownDescription(Class cls)
{
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count && !found; index++) {
        found = sel_isEqual(method_getName(list[index]), @selector(description));
    }
    free(list);
    return found;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSString *path = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"/dev/stdin";
        NSString *input = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        NSArray<NSString *> *lines = [input componentsSeparatedByString:@"\n"];
        NSString *version = [NSBundle bundleWithPath:@"/System/Library/Frameworks/Matter.framework"]
                                .infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";

        printf("# host\tMatter.framework\t%s\t%s\targv1=%s\n", version.UTF8String,
               MEASURED, path.UTF8String);
        printf("# question\tclass\tmember\tanswer\n");
        for (NSString *line in lines) {
            NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
            if (fields.count < 2 || [fields[0] length] == 0 || [fields[1] hasPrefix:@"#"]) {
                continue;
            }
            NSString *name = fields[0];
            Class cls = NSClassFromString(name);
            if (cls == nil) {
                // (iii): the host has no such class. The port keeps what the header says, and this line is
                // what says so per class rather than the tool assuming it for all of them.
                printf("present\t%s\t-\tabsent\n", name.UTF8String);
                continue;
            }
            // One class that raises must not end the run before the other 922 are read, so each class's
            // whole reading is inside one @try and a failure is reported as one.
            @try {
            if (fields.count >= 2 && [fields[1] isEqualToString:@"own"]) {
                // (i) once per class, whichever member line reaches it first.
                printf("present\t%s\t-\tpresent\n", name.UTF8String);
                printf("ownDescription\t%s\t-\t%s\n", name.UTF8String,
                       (ownDescription(cls) ? @"yes" : @"no").UTF8String);
                printf("description\t%s\t-\t%s\n", name.UTF8String,
                       [[[cls alloc] init] description].UTF8String);
                for (NSString *property in ownProperties(cls)) {
                    id value = safeRead([[cls alloc] init], property);
                    printf("fresh\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                           render(value).UTF8String);
                    // The same value as the -description PRINTS it, which is %@ and not render()'s
                    // spelling: `(null)` for nil, `0` for the NSNumber zero, nothing for an empty NSString.
                    // The predictor lays these out in the HOST SDK's declaration order and compares the
                    // string that comes out with the host's own, so this is the row it needs.
                    printf("described\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                           (value == nil ? @"(null)" : [value description]).UTF8String);
                }
                continue;
            }
            if (fields.count < 3) {
                continue;
            }
            // (ii) an alias: the declared successor, and which member MEASURES as sharing its storage. The
            // test is behavioural - write the alias twice, with two values of ITS OWN type, and see whether
            // another member's reading moves - so it works for a BOOL and for an NSNumber alike.
            NSString *alias = fields[1];
            NSString *declared = fields[2];
            NSString *aliasType = fields.count > 3 ? fields[3] : @"id";
            id object = [[cls alloc] init];
            NSMutableArray<NSString *> *sharing = [NSMutableArray array];
            for (NSString *property in ownProperties(cls)) {
                if ([property isEqualToString:alias]) {
                    continue;
                }
                writeValue(object, alias, typedValue(aliasType, 0, alias));
                NSString *before = render(safeRead(object, property));
                writeValue(object, alias, typedValue(aliasType, 1, alias));
                NSString *after = render(safeRead(object, property));
                if (![before isEqualToString:after]) {
                    [sharing addObject:property];
                }
            }
            printf("alias\t%s\t%s\tdeclared=%s\tmeasured=%s\n", name.UTF8String, alias.UTF8String,
                   declared.UTF8String,
                   ([sharing count] == 0 ? @"own" : [sharing componentsJoinedByString:@","]).UTF8String);
            // And the other way round: write the member that moved, read the alias - which is what a
            // conversion between two different types has to reproduce.
            for (NSString *property in sharing) {
                id other = [[cls alloc] init];
                writeValue(other, property, typedValue(aliasType, 2, property));
                printf("aliasBack\t%s\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                       alias.UTF8String, render(safeRead(other, alias)).UTF8String);
            }
            }
            @catch (NSException *exception) {
                printf("raised\t%s\t%s\t%s\n", name.UTF8String, fields[1].UTF8String,
                       exception.name.UTF8String);
            }
        }
    }
    return 0;
}
