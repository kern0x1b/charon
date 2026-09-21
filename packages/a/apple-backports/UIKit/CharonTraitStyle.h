#import <UIKit/UIKit.h>

UIUserInterfaceStyle charon_trait_style(UITraitCollection *collection);
void charon_set_trait_style(UITraitCollection *collection, UIUserInterfaceStyle style);

typedef struct {
    __unsafe_unretained NSString *name;
    NSInteger screenDefault;
    int described;
    __unsafe_unretained NSString *first;
    __unsafe_unretained NSString *second;
} CharonTraitKind;

void charon_register_trait_kind(CharonTraitKind kind);
NSInteger charon_trait_extra(UITraitCollection *collection, NSString *name);
void charon_set_trait_extra(UITraitCollection *collection, NSString *name, NSInteger value);
NSDictionary *charon_trait_extras(UITraitCollection *collection);
NSDictionary *charon_merge_trait_extras(NSArray *collections);
void charon_apply_trait_extras(UITraitCollection *collection, NSDictionary *extras);
void charon_apply_screen_trait_extras(UITraitCollection *collection);
BOOL charon_trait_extras_contained(UITraitCollection *collection, UITraitCollection *wanted);
BOOL charon_trait_extras_equal(UITraitCollection *a, UITraitCollection *b);
NSUInteger charon_trait_extras_hash(UITraitCollection *collection);
void charon_add_trait_extras_description(UITraitCollection *collection, NSMutableArray *traits);
void charon_encode_trait_extras(UITraitCollection *collection, NSCoder *coder);
void charon_decode_trait_extras(UITraitCollection *collection, NSCoder *coder);
