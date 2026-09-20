#import "CharonSymbols.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static char charon_preferred_symbol_configuration_key;

@implementation UIImageView (CharonSymbolConfiguration)

- (UIImageSymbolConfiguration *)preferredSymbolConfiguration
{
    return objc_getAssociatedObject(self, &charon_preferred_symbol_configuration_key);
}

- (void)setPreferredSymbolConfiguration:(UIImageSymbolConfiguration *)preferredSymbolConfiguration
{
    UIImageSymbolConfiguration *current = self.preferredSymbolConfiguration;
    if (preferredSymbolConfiguration == current || [preferredSymbolConfiguration isEqual:current])
        return;
    objc_setAssociatedObject(self, &charon_preferred_symbol_configuration_key, preferredSymbolConfiguration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
