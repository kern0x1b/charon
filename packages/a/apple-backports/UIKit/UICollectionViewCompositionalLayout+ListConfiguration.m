#import "CharonLists.h"
#import <objc/runtime.h>

static const char CharonListConfigurationKey;

@implementation UICollectionViewCompositionalLayout (CharonListState)

- (UICollectionLayoutListConfiguration *)charon_listConfiguration
{
    return objc_getAssociatedObject(self, &CharonListConfigurationKey);
}

- (void)charon_setListConfiguration:(UICollectionLayoutListConfiguration *)configuration
{
    objc_setAssociatedObject(self, &CharonListConfigurationKey, configuration, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
