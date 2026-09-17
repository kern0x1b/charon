#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface NSDimension (CharonSpecifier)
- (instancetype)initWithSpecifier:(NSUInteger)specifier symbol:(NSString *)symbol converter:(NSUnitConverter *)converter;
@property (readonly) NSUInteger specifier;
@end

@interface NSUnitConverterReciprocal : NSUnitConverter <NSSecureCoding>
- (instancetype)initWithReciprocalValue:(double)reciprocal;
@property (readonly) double reciprocalValue;
@end
