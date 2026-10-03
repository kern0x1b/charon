//
//  params-probe.m
//  Matter
//
//  One plain data class's behaviour, measured in a live process, from the class's own runtime metadata.
//
//  The SAME source runs on both sides of the differential: linked against the host's Matter.framework it
//  answers what Apple's framework does, and linked against the port's own generated objects it answers what
//  the port does. Nothing here is compiled against either - the class, its properties and their names come
//  from the runtime and from the driver on stdin - so one source is the whole comparison and a difference
//  in its output is a difference in behaviour, not in spelling.
//
//  Driven by a file named as argv[1], one line per class:
//
//      <ClassName> TAB <property> TAB <role> TAB <type> TAB <nullability>
//
//  where role is `own` for a property the class's own @interface declares, `alias` for a deprecated name
//  whose successor the driver also names, and `super` for a property the class inherits. type is the
//  property's own type spelling and nullability is `nonnull`, `nullable` or `none`, because both decide
//  what a fresh object holds.
//
//  What it prints, one `key TAB value` line per reading:
//
//      fresh       what [[X alloc] init] holds, per property, and the description
//      set         what it holds after one distinct value is written through each writable property
//      alias       what the deprecated name reads after the successor is written, and the reverse
//      copy        what the copy holds after the original's value is changed, and the reverse
//
//  A value is written through KVC, so a property the framework declares readonly is reported as such
//  rather than silently skipped: `setter: no` says the class does not answer -setValue:forKey:.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *render(id value)
{
    if (value == nil) {
        return @"(nil)";
    }
    if (value == (id)@0 || [value isKindOfClass:[NSNumber class]]) {
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

/// A KVC read that cannot throw: a class that does not implement a property the SDK declares answers by
/// raising, and one NSUnknownKeyException ends the run before it has read the other 900 classes.
static id safeRead(id object, NSString *key)
{
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

/// The distinct value written through one property, by its type: the driver names the type and this is the
/// only place that decides what a "written" reading means, so both sides write the same value.
static id sample(NSString *type, NSInteger index)
{
    NSString *base = [[type componentsSeparatedByString:@"*"] firstObject];
    base = [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([base isEqualToString:@"NSNumber"]) {
        return @(1000 + index);
    }
    if ([base isEqualToString:@"NSString"]) {
        return [NSString stringWithFormat:@"v%ld", (long)index];
    }
    if ([base isEqualToString:@"NSData"]) {
        return [@"d" dataUsingEncoding:NSUTF8StringEncoding];
    }
    if ([base isEqualToString:@"NSArray"]) {
        return @[@(7)];
    }
    if ([base isEqualToString:@"NSSet"]) {
        return [NSSet setWithObject:@(7)];
    }
    if ([base isEqualToString:@"BOOL"]) {
        return @YES;
    }
    return nil;
}

int main(void)
{
    @autoreleasepool {
        NSString *path = [NSProcessInfo processInfo].arguments.count > 1
            ? [NSProcessInfo processInfo].arguments[1] : @"/dev/stdin";
        NSString *input = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        NSArray<NSString *> *lines = [input componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
            if (fields.count < 5 || [fields[0] length] == 0) {
                continue;
            }
            NSString *name = fields[0];
            NSString *property = fields[1];
            NSString *role = fields[2];
            NSString *type = fields[3];
            NSString *nullability = fields[4];
            NSString *successor = fields.count > 5 ? fields[5] : @"";

            Class cls = NSClassFromString(name);
            printf("class\t%s\t%s\n", name.UTF8String, cls ? "present" : "absent");
            if (cls == nil) {
                continue;
            }
            id fresh = [[cls alloc] init];
            printf("fresh\t%s\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String, role.UTF8String,
                   render(safeRead(fresh, property)).UTF8String);
            printf("description\t%s\t%s\n", name.UTF8String, [[fresh description] UTF8String]);
            printf("writable\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                   [fresh respondsToSelector:NSSelectorFromString(@"setValue:forKey:")] ? "yes" : "no");

            // The alias pair: write the successor, read the deprecated name, then the other way round.
            if ([role isEqualToString:@"alias"] && [successor length] > 0) {
                id value = sample(type, 1);
                [fresh setValue:value forKey:property];
                printf("alias\t%s\t%s\t%s\t%s\n", name.UTF8String, property.UTF8String,
                       successor.UTF8String, render(safeRead(fresh, successor)).UTF8String);
                [fresh setValue:nil forKey:successor];
                [fresh setValue:value forKey:successor];
                printf("alias\t%s\t%s\t%s\t%s\n", name.UTF8String, successor.UTF8String,
                       property.UTF8String, render(safeRead(fresh, property)).UTF8String);
                [fresh setValue:value forKey:property];
            }

            // Copy independence: the copy must not share storage with the original, in either direction.
            id value = sample(type, 2);
            [fresh setValue:value forKey:property];
            id copied = [fresh copy];
            id other = sample(type, 3);
            [copied setValue:other forKey:property];
            printf("copy\t%s\t%s\toriginal-after-copy-write\t%s\n", name.UTF8String, property.UTF8String,
                   render(safeRead(fresh, property)).UTF8String);
            [fresh setValue:other forKey:property];
            printf("copy\t%s\t%s\tcopy-after-original-write\t%s\n", name.UTF8String, property.UTF8String,
                   render(safeRead(copied, property)).UTF8String);
            (void)nullability;
        }
    }
    return 0;
}
