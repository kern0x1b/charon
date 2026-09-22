#import "JSInternal.h"

/*
 * "Conditionally retained": the real engine keeps a JSManagedValue's JSValue alive for as long
 * as either the JavaScript object graph or the graph reported to -[JSVirtualMachine
 * addManagedReference:withOwner:] reaches it, and releases it - reading back as nil - the moment
 * neither does. This backport has no collector that walks either graph, so it holds the value
 * weakly and leaves the "kept alive" half of the contract to whatever already retains the
 * JSValue: ARC, for as long as an Objective-C reference to it exists, or the retaining map behind
 * -addManagedReference:withOwner:, for as long as the owner given there is alive. A JSManagedValue
 * with nothing else holding its value reads back nil, matching a value the real engine has
 * collected - it is only the timing of the collection that is not reproduced.
 */

@interface JSManagedValue ()
{
    __weak JSValue *_value;
}
@end

@implementation JSManagedValue

+ (JSManagedValue *)managedValueWithValue:(JSValue *)value
{
    return [[self alloc] initWithValue:value];
}

+ (JSManagedValue *)managedValueWithValue:(JSValue *)value andOwner:(id)owner
{
    JSManagedValue *managed = [[self alloc] initWithValue:value];
    if (value)
        [value.context.virtualMachine addManagedReference:value withOwner:owner];
    return managed;
}

- (instancetype)initWithValue:(JSValue *)value
{
    if ((self = [super init]))
        _value = value;
    return self;
}

- (JSValue *)value
{
    return _value;
}

@end
