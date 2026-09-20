#import "CharonMenus.h"

@implementation UIContextMenuConfiguration {
@private
    id<NSCopying> _identifier;
    UIContextMenuContentPreviewProvider _previewProvider;
    UIContextMenuActionProvider _actionProvider;
}

@dynamic secondaryItemIdentifiers, badgeCount, preferredMenuElementOrder;

+ (instancetype)configurationWithIdentifier:(id<NSCopying>)identifier previewProvider:(UIContextMenuContentPreviewProvider)previewProvider
                             actionProvider:(UIContextMenuActionProvider)actionProvider
{
    UIContextMenuConfiguration *configuration = [[self alloc] init];
    if (identifier)
        configuration->_identifier = [(id)identifier copy];
    configuration->_previewProvider = [previewProvider copy];
    configuration->_actionProvider = [actionProvider copy];
    return configuration;
}

- (instancetype)init
{
    if ((self = [super init]))
        _identifier = [NSUUID UUID];
    return self;
}

- (id<NSCopying>)identifier
{
    return _identifier;
}

- (UIContextMenuActionProvider)charon_actionProvider
{
    return _actionProvider;
}

@end
