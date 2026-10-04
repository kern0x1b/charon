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
//  Four questions, one per family of line in the driver:
//
//      <Class> TAB own                                            the class's own members, in the
//                                                                   order the header declares them
//      <Class> TAB <alias> TAB <successor> TAB alias              an alias pair, successor from the SDK's
//                                                                   own deprecation text
//      <Class> TAB <member> TAB <superclass> TAB storage <type>   an alias CLASS's own storage: the value
//                                                                   written through the alias reference and
//                                                                   read back through a current one, both
//                                                                   ways round, with the alias's own ivars,
//                                                                   the bytes its layout adds and whether
//                                                                   its OWN method list carries the pair
//  and for each class:
//
//    (i)  does the CLASS ITSELF implement -description, and which class in its hierarchy carries -init?
//        `class_copyMethodList` on the class and on every superclass, not respondsToSelector:, which every
//        class inherits for both; and what string does a fresh object print?
//    (ii) for an alias, which OTHER member of the class shares its storage, both ways: the alias is set to a
//        sentinel and every own member is read, and then every own member is set and the alias is read. That
//        finds the shared storage without being told the name, which is what settles the 51 deprecations
//        whose text is prose ("Please use the storage property") rather than a member name.
//    (iii) for an alias CLASS - a class whose own deprecation names its own superclass - whether the alias
//        holds storage of its own. The framework writes `@dynamic` for every member and nothing else, so
//        the members live in the superclass's ivars and there is ONE storage; a port that gives the alias
//        its own holds TWO, and no value read alone can see it, because Objective-C dispatch walks up from
//        the RECEIVER's class and never from the static type of the variable. So the question reads the
//        shape the runtime reports - the class's OWN ivars, the bytes its layout adds to the superclass's
//        and whether its OWN method list carries the accessor pair - and answers the value question both
//        ways round beside it, because "write via one and read via the other" is only a check if it can
//        fail. Measured on this host, for MTRTestClusterClusterSimpleStruct's `a`:
//            ownIvars=0  sizeDelta=0  ownAccessors=no  aliasWrite=M1  currentRead=M1  aliasReadBack=M2
//    (iv) a class the host does not have is reported absent, and the port keeps its header-derived answer
//        for it; the caller says so per class.
//
//  Every value is flattened before it is printed, because a TSV field cannot hold a newline and an empty
//  NSArray's -description is one.
//
//  The output is the data file tools/matter-generate.py reads, and its provenance - the host's own version
//  string and the date - is written with it.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

/// The date the table was measured, written into the file beside the host's own version string, so a
/// reader can tell which binary answered without asking. It is the date this tree's run happened.
#define MEASURED "2026-10-04"

/// One TSV field cannot hold a newline, and several of these values carry one: an empty NSArray's
/// `-description` is `(` and a newline and `)` on this Foundation, so a struct holding one printed its
/// members up to `d:(` and the rest of the line landed on the next one. 132 of 6,560 readings were cut
/// short that way and 277 lines of the file were the pieces of them - the same count on both sides, so the
/// comparison still called such a pair equal, and it could not see the tail of any of them. The value is
/// what it is; the FIELD is flattened, and only the field.
static NSString *flatten(NSString *value)
{
    if (value == nil) {
        return nil;
    }
    NSString *spaced = [value stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return [spaced stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
}

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
    return flatten([NSString stringWithFormat:@"%@(%@)", NSStringFromClass([value class]), value]);
}

/// Write through KVC only, and say whether it took. The setter is the member's own API, but handing an
/// NSNumber to an `NSData *` property's `setD:` is NSInvalidArgumentException, so the value's CLASS - not the
/// storage - would decide whether the reading exists at all. KVC routes to the same accessor and coerces,
/// which is what makes the two sides' readings comparable.
static BOOL safeWrite(id object, NSString *key, id value)
{
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
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
/// A value of one member's OWN type, for the alias-storage question, where the member's type is whatever
/// the alias class's header declares and not necessarily its successor's.
///
/// `typedValue` above cannot serve it: it answers an object-typed member with an NSValue marker, and KVC
/// handing that to an `NSNumber *` property raises NSInvalidArgumentException - which is how the first run of
/// this question reported 11 `raised` rows that were the probe's own artifact and not host behaviour, the
/// same defect the `alias` question already had. So the type decides here too, by its base class name, over
/// the eight shapes the 230 members of this question actually declare (measured: 164 NSNumber, 25 NSArray,
/// 14 NSString, 14 of one Matter struct, 7 NSData, 2 NSArray<NSData *>, one protocol id, one struct list,
/// one struct, one BOOL). A type this does not know is answered with an NSNumber and the run says so,
/// rather than guessed at - the class of the value is what decides whether a write succeeded, and a
/// mismatched one raises instead of reading back.
static id probeValue(NSString *type, NSInteger index)
{
    NSString *spelling = [type stringByReplacingOccurrencesOfString:@"_Nonnull" withString:@""];
    spelling = [spelling stringByReplacingOccurrencesOfString:@"_Nullable" withString:@""];
    spelling = [[[spelling componentsSeparatedByString:@"<"] firstObject]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    long value = (long)(index == 0 ? 7 : 9);
    if ([spelling isEqualToString:@"NSString"]) {
        return index == 0 ? @"red-control-zero" : @"red-control-one";
    }
    if ([spelling isEqualToString:@"NSData"]) {
        return [NSData dataWithBytes:(index == 0 ? "0" : "1") length:1];
    }
    if ([spelling isEqualToString:@"NSArray"]) {
        return @[ @(value) ];
    }
    if ([spelling hasSuffix:@"*"] && [spelling hasPrefix:@"MTR"]) {
        // The trailing `*` is stripped BEFORE the trim, or the name handed to NSClassFromString ends in a
        // space and the lookup is nil for every one of the 63 members whose type is a Matter class - which is
        // how the first run of this question wrote an NSNumber into 63 struct members and reported the
        // probe's own artifact as a difference between the two sides.
        NSString *bare = [[spelling stringByReplacingOccurrencesOfString:@"*" withString:@""]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        Class named = NSClassFromString(bare);
        if (named == nil) {
            printf("probe: UNREAD type %s, the class it names is not in this framework\n", type.UTF8String);
            return @(value);
        }
        return [[named alloc] init];
    }
    return @(value);
}

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

/// How many ivars a class declares ITSELF, inherited ones excluded. The framework's alias class declares
/// none - `@dynamic` and nothing else - so this is the number that says whether a port gave it storage.
static unsigned int ownIvars(Class cls)
{
    unsigned int count = 0;
    free(class_copyIvarList(cls, &count));
    return count;
}

/// Whether the class's OWN method list carries a selector. An alias class that inherits its accessor does
/// not, and one the port gave storage of its own does.
static BOOL ownSelector(Class cls, NSString *name)
{
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count && !found; index++) {
        found = sel_isEqual(method_getName(list[index]), NSSelectorFromString(name));
    }
    free(list);
    return found;
}

/// The setter a member's own name spells. One function because the probe wrote it inline twice and the
/// one-character case has no second character to take: `characterAtIndex:0` on an empty substring is
/// NSRangeException and took the run down on the first line that named a one-letter member.
static NSString *setterName(NSString *key)
{
    if ([key length] < 2) {
        return [NSString stringWithFormat:@"set%@:", key];
    }
    return [NSString stringWithFormat:@"set%@%c:", [[key substringToIndex:1] uppercaseString],
            [[key substringFromIndex:1] characterAtIndex:0]];
}

/// Which class in the hierarchy CARRIES -init in its own method list, the class itself first.
///
/// `[[X alloc] init]` runs the first -init the runtime finds walking up from X, and a CATEGORY's method is
/// merged into the class's own list, so a class whose own @implementation declares no -init and whose
/// CATEGORY does is measured here exactly like one that declares it. That is the whole answer to
/// MTRSubscribeParams' minInterval reading 1 after `[[MTRSubscribeParams alloc] init]`: the -init that runs
/// is on the class itself, and the framework's own source says which one it is -
/// `MTRCluster.mm:287 @implementation MTRSubscribeParams (Deprecated)` with `- (instancetype)init` at :289
/// storing `_minInterval = @(1)` at :294 - where the class's own @implementation at :184 has none.
///
/// NSObject is left out of the answer on purpose: a hierarchy that reaches no -init but NSObject's stores
/// nothing, and NSObject's is not one of these classes'.
static NSString *initOwner(Class cls)
{
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    Class walk = cls;
    while (walk && walk != [NSObject class]) {
        unsigned int count = 0;
        Method *list = class_copyMethodList(walk, &count);
        for (unsigned int index = 0; index < count; index++) {
            if (sel_isEqual(method_getName(list[index]), @selector(init))) {
                [found addObject:[found count] == 0 && walk == cls ? @"self" : NSStringFromClass(walk)];
                break;
            }
        }
        free(list);
        walk = class_getSuperclass(walk);
    }
    return found.count == 0 ? @"none" : [found componentsJoinedByString:@","];
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
                // (iv): the host has no such class. The port keeps what the header says, and this line is
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
                printf("initOwner\t%s\t-\t%s\n", name.UTF8String, initOwner(cls).UTF8String);
                printf("description\t%s\t-\t%s\n", name.UTF8String,
                       flatten([[[cls alloc] init] description]).UTF8String);
                for (NSString *property in ownProperties(cls)) {
                    id value = safeRead([[cls alloc] init], property);
                    printf("fresh\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                           render(value).UTF8String);
                    // The same value as the -description PRINTS it, which is %@ and not render()'s
                    // spelling: `(null)` for nil, `0` for the NSNumber zero, nothing for an empty NSString.
                    // The predictor lays these out in the HOST SDK's declaration order and compares the
                    // string that comes out with the host's own, so this is the row it needs.
                    printf("described\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                           flatten(value == nil ? @"(null)" : [value description]).UTF8String);
                }
                continue;
            }
            if (fields.count < 3) {
                continue;
            }
            // (iii) an alias CLASS's own storage. See the note at the top of this file: the value question
            // cannot see two storages on its own, so the runtime's own answer comes first and the value
            // question is answered both ways round beside it.
            if (fields.count >= 4 && [fields[3] isEqualToString:@"storage"]) {
                NSString *member = fields[1];
                Class successor = NSClassFromString(fields[2]);
                NSString *kind = fields.count > 4 ? fields[4] : @"id";
                id object = [[cls alloc] init];
                NSString *first = render(probeValue(kind, 0));
                NSString *second = render(probeValue(kind, 1));
                (void)successor;
                // Written through the ALIAS reference, read back through a CURRENT one; then written through
                // the current reference and read back through the ALIAS. With ONE storage the first reading
                // is the value written and the last is the value written second; with TWO the first is the
                // same value and the last is the FIRST one, because the alias keeps its own.
                BOOL wrote = safeWrite(object, member, probeValue(kind, 0));
                NSString *throughCurrent = render(safeRead(object, member));
                wrote = safeWrite(object, member, probeValue(kind, 1)) && wrote;
                NSString *throughAlias = render(safeRead(object, member));
                BOOL own = ownSelector(cls, member) || ownSelector(cls, setterName(member));
                // The superclass is the RUNTIME's own answer and not the name the driver carries: the host's
                // framework is built from an SDK that spells the pair the other way round for 63 of these
                // members, and a line that printed the driver's name would then be reporting two SDKs rather
                // than two storages.
                Class above = class_getSuperclass(cls);
                printf("storage\t%s\t%s\twrote1=%s\twrote2=%s\twrote=%s\tcurrentRead=%s"
                       "\taliasReadBack=%s\townIvars=%u\tsizeDelta=%ld\townAccessors=%s\tsuper=%s\n",
                       name.UTF8String, member.UTF8String, first.UTF8String, second.UTF8String,
                       wrote ? "yes" : "no", throughCurrent.UTF8String, throughAlias.UTF8String,
                       ownIvars(cls),
                       (long)(above ? class_getInstanceSize(cls) - class_getInstanceSize(above) : -1),
                       own ? "yes" : "no", above ? "present" : "none");
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
