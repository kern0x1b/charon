#import <Foundation/Foundation.h>

NSString *const UIKeyInputUpArrow = @"UIKeyInputUpArrow";
NSString *const UIKeyInputDownArrow = @"UIKeyInputDownArrow";
NSString *const UIKeyInputLeftArrow = @"UIKeyInputLeftArrow";
NSString *const UIKeyInputRightArrow = @"UIKeyInputRightArrow";
NSString *const UIKeyInputEscape = @"UIKeyInputEscape";

API_AVAILABLE(ios(7.0))
@interface UIKeyCommand : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)keyCommandWithInput:(NSString *)input modifierFlags:(NSInteger)modifierFlags action:(SEL)action;
+ (instancetype)keyCommandWithInput:(NSString *)input modifierFlags:(NSInteger)modifierFlags action:(SEL)action discoverabilityTitle:(NSString *)discoverabilityTitle;
@property (nullable, nonatomic, copy) NSString *discoverabilityTitle;
@property (nullable, nonatomic, readonly) SEL action;
@property (nullable, nonatomic, readonly) NSString *input;
@property (nonatomic, readonly) NSInteger modifierFlags;
@end

@implementation UIKeyCommand {
    NSString *_input;
    NSInteger _modifierFlags;
    SEL _action;
    NSString *_discoverabilityTitle;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)init
{
    self = [super init];
    if (self)
        _action = sel_registerName("_nop");
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [self init];
    if (self) {
        _input = [coder decodeObjectOfClass:[NSString class] forKey:@"UIKeyCommandInput"];
        _modifierFlags = [coder decodeIntegerForKey:@"UIKeyCommandModifierFlags"];
        NSString *action = [coder decodeObjectOfClass:[NSString class] forKey:@"UIKeyCommandAction"];
        if (action)
            _action = NSSelectorFromString(action);
        _discoverabilityTitle = [coder decodeObjectOfClass:[NSString class] forKey:@"UIKeyCommandDiscoverabilityTitle"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_input forKey:@"UIKeyCommandInput"];
    [coder encodeInteger:_modifierFlags forKey:@"UIKeyCommandModifierFlags"];
    [coder encodeObject:NSStringFromSelector(_action) forKey:@"UIKeyCommandAction"];
    [coder encodeObject:_discoverabilityTitle forKey:@"UIKeyCommandDiscoverabilityTitle"];
}

+ (instancetype)keyCommandWithInput:(NSString *)input modifierFlags:(NSInteger)modifierFlags action:(SEL)action
{
    UIKeyCommand *command = [[self alloc] init];
    command->_input = [input copy];
    command->_modifierFlags = modifierFlags;
    command->_action = action;
    return command;
}

+ (instancetype)keyCommandWithInput:(NSString *)input modifierFlags:(NSInteger)modifierFlags action:(SEL)action discoverabilityTitle:(NSString *)discoverabilityTitle
{
    UIKeyCommand *command = [self keyCommandWithInput:input modifierFlags:modifierFlags action:action];
    command->_discoverabilityTitle = [discoverabilityTitle copy];
    return command;
}

- (NSString *)input
{
    return _input;
}

- (NSInteger)modifierFlags
{
    return _modifierFlags;
}

- (SEL)action
{
    return _action;
}

- (NSString *)discoverabilityTitle
{
    return _discoverabilityTitle;
}

- (void)setDiscoverabilityTitle:(NSString *)title
{
    _discoverabilityTitle = [title copy];
}

- (id)copyWithZone:(NSZone *)zone
{
    UIKeyCommand *copy = [[[self class] alloc] init];
    copy->_input = [_input copy];
    copy->_modifierFlags = _modifierFlags;
    copy->_action = _action;
    copy->_discoverabilityTitle = [_discoverabilityTitle copy];
    return copy;
}

- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[UIKeyCommand class]])
        return NO;
    UIKeyCommand *command = other;
    return (command->_input == _input || [command->_input isEqual:_input]) && command->_modifierFlags == _modifierFlags && command->_action == _action;
}

- (NSUInteger)hash
{
    return _input.hash ^ (NSUInteger)_modifierFlags ^ (NSUInteger)(uintptr_t)_action;
}

@end
