#import "CharonMenus.h"
#import <objc/runtime.h>

static const char CharonAutomaticScopeBarKey;

@implementation UISearchController (CharonScopeBar)

- (BOOL)automaticallyShowsScopeBar
{
    NSNumber *held = objc_getAssociatedObject(self, &CharonAutomaticScopeBarKey);
    return held ? held.boolValue : YES;
}

- (void)setAutomaticallyShowsScopeBar:(BOOL)automaticallyShowsScopeBar
{
    objc_setAssociatedObject(self, &CharonAutomaticScopeBarKey, @(automaticallyShowsScopeBar), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    charon_menus_say_once(@"search-scope-bar", @"UISearchController.automaticallyShowsScopeBar: the scope bar is not shown by the controller on this release; the application shows the search bar's scope bar itself");
}

@end
