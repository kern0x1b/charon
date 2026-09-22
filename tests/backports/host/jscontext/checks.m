#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@protocol PointExport <JSExport>
@property (nonatomic) double x;
@property (nonatomic) double y;
- (double)distanceTo:(id)other;
JSExportAs(addTo,
- (double)addTo:(double)a and:(double)b
);
@end

@interface PointObject : NSObject <PointExport>
@property (nonatomic) double x;
@property (nonatomic) double y;
@end

@implementation PointObject
- (double)distanceTo:(id)other
{
    double ox = [other[@"x"] doubleValue];
    double oy = [other[@"y"] doubleValue];
    double dx = self.x - ox, dy = self.y - oy;
    return sqrt(dx * dx + dy * dy);
}
- (double)addTo:(double)a and:(double)b
{
    return a + b;
}
@end

static int failures;

static void check(BOOL condition, NSString *name)
{
    if (condition) {
        printf("ok %s\n", name.UTF8String);
    } else {
        failures++;
        printf("FAIL %s\n", name.UTF8String);
    }
}

int main(void)
{
    @autoreleasepool {
        JSContext *context = [[JSContext alloc] init];
        check([[context evaluateScript:@"1 + 2"] toInt32] == 3, @"evaluateScript arithmetic");

        context[@"greeting"] = @"hello";
        check([[context[@"greeting"] toString] isEqualToString:@"hello"], @"subscript round trip");

        context[@"add"] = ^(NSNumber *a, NSNumber *b) {
            return @(a.doubleValue + b.doubleValue);
        };
        check([[context evaluateScript:@"add(3, 4)"] toInt32] == 7, @"block boxed as a callable JS function");

        PointObject *point = [PointObject new];
        point.x = 3;
        point.y = 4;
        context[@"origin"] = point;
        JSValue *distance = [context evaluateScript:@"origin.distanceTo({x:0,y:0})"];
        check(fabs([distance toDouble] - 5.0) < 0.0001, @"JSExport instance method, called from JavaScript with a plain object literal argument");
        check([[context evaluateScript:@"origin.addTo(2, 5)"] toInt32] == 7, @"JSExportAs renames the exported selector");
        [context evaluateScript:@"origin.x = 10"];
        check(point.x == 10, @"JSExport property setter mutates the native object");

        NSArray *array = @[@1, @2, @3];
        context[@"arr"] = array;
        check([[context evaluateScript:@"arr.length"] toInt32] == 3, @"NSArray boxed as a JS array");
        check([[context[@"arr"] toArray] isEqualToArray:array], @"JS array round trips back to NSArray");
        check([context[@"arr"] isArray], @"isArray agrees with the JS engine's own Array.isArray");

        NSDictionary *dict = @{@"a": @1, @"b": @2};
        context[@"dict"] = dict;
        check([[context evaluateScript:@"dict.a"] toInt32] == 1, @"NSDictionary boxed as a JS object");

        JSValue *undefinedRead = [context evaluateScript:@"thisNameIsNotDefinedAnywhere"];
        check(context.exception != nil, @"an uncaught reference error lands on context.exception");
        check(undefinedRead.isUndefined, @"a failed evaluation still returns a usable JSValue (undefined)");
        context.exception = nil;

        JSValue *product = [[context evaluateScript:@"(function(a,b){ return a*b; })"] callWithArguments:@[@6, @7]];
        check([product toInt32] == 42, @"callWithArguments invokes a JS function value directly");

        JSValue *five = [JSValue valueWithInt32:5 inContext:context];
        JSManagedValue *managed = [JSManagedValue managedValueWithValue:five];
        check([managed.value toInt32] == 5, @"JSManagedValue reads back its value while something else retains it");
        five = nil;
        check(managed.value == nil, @"JSManagedValue reads back nil once nothing else retains its value");

        JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
        JSContext *second = [[JSContext alloc] initWithVirtualMachine:vm];
        check(second.virtualMachine == vm, @"a context created with an explicit JSVirtualMachine reports it back");

        printf(failures == 0 ? "checks=all passed\n" : "checks=%d failed\n", failures);
    }
    return failures;
}
