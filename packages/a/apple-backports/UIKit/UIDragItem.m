#import <UIKit/UIKit.h>

@implementation UIDragItem {
    NSItemProvider *_itemProvider;
    id _localObject;
    UIDragPreview * (^_previewProvider)(void);
}

- (instancetype)initWithItemProvider:(NSItemProvider *)itemProvider
{
    self = [super init];
    if (self)
        _itemProvider = itemProvider;
    return self;
}

- (NSItemProvider *)itemProvider
{
    return _itemProvider;
}

- (id)localObject
{
    return _localObject;
}

- (void)setLocalObject:(id)localObject
{
    _localObject = localObject;
}

- (UIDragPreview * (^)(void))previewProvider
{
    return _previewProvider;
}

- (void)setPreviewProvider:(UIDragPreview * (^)(void))previewProvider
{
    _previewProvider = [previewProvider copy];
}

@end
