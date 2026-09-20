#import "CharonDiffable.h"
#import "CharonMenus.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

static const char charon_reordering_key = 0, charon_snapshot_handlers_key = 0, charon_sections_key = 0, charon_applying_key = 0;

@implementation UICollectionViewDiffableDataSource (CharonFourteen)

- (UICollectionViewDiffableDataSourceReorderingHandlers *)reorderingHandlers
{
    id handlers = objc_getAssociatedObject(self, &charon_reordering_key);
    if (!handlers) {
        handlers = [[UICollectionViewDiffableDataSourceReorderingHandlers alloc] init];
        objc_setAssociatedObject(self, &charon_reordering_key, handlers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return handlers;
}

- (void)setReorderingHandlers:(UICollectionViewDiffableDataSourceReorderingHandlers *)reorderingHandlers
{
    charon_menus_say_once(@"reorderingHandlers", @"UICollectionViewDiffableDataSource.reorderingHandlers: iOS 6 collection views cannot reorder items interactively, so the handlers are kept and never called");
    objc_setAssociatedObject(self, &charon_reordering_key, [reorderingHandlers copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UICollectionViewDiffableDataSourceSectionSnapshotHandlers *)sectionSnapshotHandlers
{
    id handlers = objc_getAssociatedObject(self, &charon_snapshot_handlers_key);
    if (!handlers) {
        handlers = [[UICollectionViewDiffableDataSourceSectionSnapshotHandlers alloc] init];
        objc_setAssociatedObject(self, &charon_snapshot_handlers_key, handlers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return handlers;
}

- (void)setSectionSnapshotHandlers:(UICollectionViewDiffableDataSourceSectionSnapshotHandlers *)sectionSnapshotHandlers
{
    charon_menus_say_once(@"sectionSnapshotHandlers", @"UICollectionViewDiffableDataSource.sectionSnapshotHandlers: iOS 6 has no outline cell to expand or collapse, so the handlers are kept and never called");
    objc_setAssociatedObject(self, &charon_snapshot_handlers_key, [sectionSnapshotHandlers copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSMutableDictionary *)charon_sectionSnapshots
{
    NSMutableDictionary *snapshots = objc_getAssociatedObject(self, &charon_sections_key);
    if (!snapshots) {
        snapshots = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &charon_sections_key, snapshots, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return snapshots;
}

- (void)charon_rebaseSectionSnapshotsFrom:(NSDiffableDataSourceSnapshot *)previous onto:(NSDiffableDataSourceSnapshot *)snapshot
{
    if ([objc_getAssociatedObject(self, &charon_applying_key) boolValue])
        return;
    NSMutableDictionary *snapshots = [self charon_sectionSnapshots];
    for (id section in snapshots.allKeys) {
        NSDiffableDataSourceSectionSnapshot *stored = snapshots[section];
        NSInteger index = [snapshot indexOfSectionIdentifier:section];
        if (index == NSNotFound) {
            [snapshots removeObjectForKey:section];
            continue;
        }
        NSArray *items = [snapshot itemIdentifiersInSectionWithIdentifier:section], *visible = [previous indexOfSectionIdentifier:section] == NSNotFound ? @[] : [previous itemIdentifiersInSectionWithIdentifier:section];
        if ([items isEqual:visible])
            continue;
        visible = stored.visibleItems;
        NSMutableArray *gone = [NSMutableArray array];
        for (id item in visible)
            if (![items containsObject:item])
                [gone addObject:item];
        NSDiffableDataSourceSectionSnapshot *rebased = [stored copy];
        BOOL usable = YES;
        for (id item in gone)
            if ([rebased containsItem:item])
                [rebased deleteItems:@[item]];
        for (NSUInteger position = 0; position < items.count; position++) {
            id item = items[position];
            if ([visible containsObject:item])
                continue;
            if ([rebased containsItem:item])
                usable = NO;
            else if (position > 0 && [rebased containsItem:items[position - 1]])
                [rebased insertItems:@[item] afterItem:items[position - 1]];
            else if (rebased.rootItems.count)
                [rebased insertItems:@[item] beforeItem:rebased.rootItems.firstObject];
            else
                [rebased appendItems:@[item]];
        }
        if (usable && [rebased.visibleItems isEqual:items])
            snapshots[section] = rebased;
        else
            [snapshots removeObjectForKey:section];
    }
}

- (void)applySnapshot:(NSDiffableDataSourceSectionSnapshot *)snapshot toSection:(id)sectionIdentifier animatingDifferences:(BOOL)animatingDifferences
{
    [self applySnapshot:snapshot toSection:sectionIdentifier animatingDifferences:animatingDifferences completion:nil];
}

- (void)applySnapshot:(NSDiffableDataSourceSectionSnapshot *)snapshot toSection:(id)sectionIdentifier animatingDifferences:(BOOL)animatingDifferences completion:(void (^)(void))completion
{
    if (!sectionIdentifier)
        [NSException raise:NSInternalInconsistencyException format:@"Invalid parameter not satisfying: section"];
    if (!snapshot)
        [NSException raise:NSInternalInconsistencyException format:@"Invalid parameter not satisfying: snapshot"];
    NSDiffableDataSourceSnapshot *updated = [self snapshot];
    if ([updated indexOfSectionIdentifier:sectionIdentifier] == NSNotFound)
        [updated appendSectionsWithIdentifiers:@[sectionIdentifier]];
    [updated charon_replaceItems:snapshot.visibleItems inSectionAtIndex:(NSUInteger)[updated indexOfSectionIdentifier:sectionIdentifier]];
    objc_setAssociatedObject(self, &charon_applying_key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [self applySnapshot:updated animatingDifferences:animatingDifferences completion:completion];
    } @finally {
        objc_setAssociatedObject(self, &charon_applying_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self charon_sectionSnapshots][sectionIdentifier] = [snapshot copy];
}

- (NSDiffableDataSourceSectionSnapshot *)snapshotForSection:(id)section
{
    NSDiffableDataSourceSectionSnapshot *stored = section ? [self charon_sectionSnapshots][section] : nil;
    if (stored)
        return [stored copy];
    NSDiffableDataSourceSectionSnapshot *snapshot = [[NSDiffableDataSourceSectionSnapshot alloc] init];
    NSDiffableDataSourceSnapshot *current = [self charon_current];
    if (section && [current indexOfSectionIdentifier:section] != NSNotFound)
        [snapshot appendItems:[current itemIdentifiersInSectionWithIdentifier:section]];
    return snapshot;
}

@end
