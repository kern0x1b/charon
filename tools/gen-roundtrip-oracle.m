// Round-trip oracle for gen.py classify: runs on the host (macOS, or Mac Catalyst for UIKit) and reports, for each class
// named in the input, whether it instantiates with -init, and for each property whether it reads back what was set, and
// whether setting it moves any other property (a derived property).
//
// Input (one record per line, tab separated):
//   CLASS <TAB> class
//   PROP  <TAB> class <TAB> property <TAB> getter <TAB> type <TAB> readwrite(yes|no)
// type is one of: bool, integer, double, float, string, other. Only the first four and string are set and read back.
// Output: CLASS <TAB> class <TAB> init(yes|no|absent)
//         PROP  <TAB> class <TAB> property <TAB> status(ok|fail|readonly|untested) <TAB> moved(comma list of properties)
// Build: clang -fobjc-arc -w -framework Foundation [-framework UIKit ...] roundtrip.m -o roundtrip
// The sample values are fixed and ASCII; a property is ok only if every sample reads back equal.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// A property record is a dictionary (name, getter, type, readwrite): object pointers kept in a struct inside NSValue are not
// retained under ARC and dangle.
typedef NSDictionary *Prop;
static NSString *nameOf(Prop p) { return p[@"name"]; }
static NSString *typeOf(Prop p) { return p[@"type"]; }
static BOOL writableOf(Prop p) { return [p[@"rw"] boolValue]; }

static BOOL same(id a, id b) {
    if (a == nil || b == nil) return a == b;
    return [a isEqual:b];
}

// Reads one property through its getter, boxed so the snapshot can compare it.
static id readValue(id obj, Prop p) {
    SEL g = NSSelectorFromString(p[@"getter"]);
    NSString *t = typeOf(p);
    if ([t isEqualToString:@"bool"]) return @(((BOOL (*)(id, SEL))objc_msgSend)(obj, g));
    if ([t isEqualToString:@"integer"]) return @(((NSInteger (*)(id, SEL))objc_msgSend)(obj, g));
    if ([t isEqualToString:@"double"]) return @(((double (*)(id, SEL))objc_msgSend)(obj, g));
    if ([t isEqualToString:@"float"]) return @(((float (*)(id, SEL))objc_msgSend)(obj, g));
    if ([t isEqualToString:@"string"]) return ((id (*)(id, SEL))objc_msgSend)(obj, g);
    return nil;
}

static void writeValue(id obj, Prop p, id value) {
    NSString *n = nameOf(p), *t = typeOf(p);
    SEL s = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:", [[n substringToIndex:1] uppercaseString], [n substringFromIndex:1]]);
    if ([t isEqualToString:@"bool"]) ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, s, [value boolValue]);
    else if ([t isEqualToString:@"integer"]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(obj, s, [value integerValue]);
    else if ([t isEqualToString:@"double"]) ((void (*)(id, SEL, double))objc_msgSend)(obj, s, [value doubleValue]);
    else if ([t isEqualToString:@"float"]) ((void (*)(id, SEL, float))objc_msgSend)(obj, s, [value floatValue]);
    else if ([t isEqualToString:@"string"]) ((void (*)(id, SEL, id))objc_msgSend)(obj, s, value);
}

// The two samples per type: the second is distinct from the first, so a setter that ignores its argument fails.
static id sampleFor(NSString *type, int which) {
    if ([type isEqualToString:@"bool"]) return which ? @NO : @YES;
    if ([type isEqualToString:@"integer"]) return which ? @9 : @7;
    if ([type isEqualToString:@"double"]) return which ? @3.75 : @2.5;
    if ([type isEqualToString:@"float"]) return which ? @3.75f : @2.5f;
    if ([type isEqualToString:@"string"]) return which ? @"probe-b" : @"probe-a";
    return nil;
}

static NSArray *fields(NSString *line) { return [line componentsSeparatedByString:@"\t"]; }

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "usage: roundtrip <input>\n"); return 2; }
        NSString *text = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:NULL];
        NSMutableDictionary<NSString *, NSMutableArray<Prop> *> *props = [NSMutableDictionary dictionary];
        NSMutableArray<NSString *> *classes = [NSMutableArray array];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            NSArray *f = fields(line);
            if (f.count == 2 && [f[0] isEqualToString:@"CLASS"]) { [classes addObject:f[1]]; }
            else if (f.count == 6 && [f[0] isEqualToString:@"PROP"]) {
                Prop p = @{@"name": f[2], @"getter": f[3], @"type": f[4], @"rw": @([f[5] isEqualToString:@"yes"])};
                NSMutableArray<Prop> *list = props[f[1]] ?: [NSMutableArray array];
                [list addObject:p];
                props[f[1]] = list;
            }
        }
        for (NSString *cls in classes) {
            Class c = NSClassFromString(cls);
            if (!c) { printf("CLASS\t%s\tabsent\n", cls.UTF8String); continue; }
            id obj = nil;
            @try { obj = [[c alloc] init]; } @catch (NSException *e) { obj = nil; }
            printf("CLASS\t%s\t%s\n", cls.UTF8String, obj ? "yes" : "no");
            NSArray<Prop> *all = props[cls] ?: @[];
            for (Prop p in all) {
                if (!obj || [typeOf(p) isEqualToString:@"other"]) { printf("PROP\t%s\t%s\tuntested\t\n", cls.UTF8String, nameOf(p).UTF8String); continue; }
                if (!writableOf(p)) { printf("PROP\t%s\t%s\treadonly\t\n", cls.UTF8String, nameOf(p).UTF8String); continue; }
                BOOL ok = YES;
                NSMutableArray<NSString *> *moved = [NSMutableArray array];
                for (int which = 0; which < 2; which++) {
                    NSMutableDictionary *before = [NSMutableDictionary dictionary];
                    for (Prop q in all) if (![typeOf(q) isEqualToString:@"other"]) before[nameOf(q)] = readValue(obj, q) ?: [NSNull null];
                    @try { writeValue(obj, p, sampleFor(typeOf(p), which)); } @catch (NSException *e) { ok = NO; }
                    if (!same(readValue(obj, p), sampleFor(typeOf(p), which))) ok = NO;
                    for (Prop q in all) {
                        if ([typeOf(q) isEqualToString:@"other"] || [nameOf(q) isEqualToString:nameOf(p)]) continue;
                        id now = readValue(obj, q) ?: [NSNull null];
                        if (!same(now, before[nameOf(q)]) && ![moved containsObject:nameOf(q)]) [moved addObject:nameOf(q)];
                    }
                }
                printf("PROP\t%s\t%s\t%s\t%s\n", cls.UTF8String, nameOf(p).UTF8String, ok ? "ok" : "fail",
                       [[moved componentsJoinedByString:@","] UTF8String]);
            }
        }
    }
    return 0;
}
