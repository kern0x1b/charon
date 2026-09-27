#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

// Prefetching for a table view, the same scheme as UICollectionView+Prefetching10.m and for the
// same reason: the release's table view has no prefetching, so the port asks itself, after the
// table has laid out, for the rows just past what is on screen, nearest first, and calls off the
// ones scrolled past. A prefetch data source is held the way the tree holds a weak sender, and
// prefetching happens only once a data source is set.
static const char CharonTablePrefetchDataSourceKey;
static const char CharonTablePrefetchAskedKey;
static const NSInteger CharonTablePrefetchDistance = 3;

// Declared here because the installer's +load runs before this category is attached, and it calls
// this on the view.
@interface UITableView (CharonPrefetching10)
- (void)charon_prefetchRows;
@end

@interface CharonTablePrefetchInstaller : NSObject
@end

@implementation CharonTablePrefetchInstaller

+ (void)load
{
    if ([UITableView instancesRespondToSelector:@selector(prefetchDataSource)])
        return;
    Class table = [UITableView class];
    IMP original = class_getMethodImplementation(table, @selector(layoutSubviews));
    if (!original)
        return;
    class_replaceMethod(table, @selector(layoutSubviews), imp_implementationWithBlock(^(UITableView *self_) {
        ((void (*)(id, SEL))original)(self_, @selector(layoutSubviews));
        [self_ charon_prefetchRows];
    }), "ccharon_layoutSubviews");
}

@end

@implementation UITableView (CharonPrefetching10)

- (id<UITableViewDataSourcePrefetching>)prefetchDataSource
{
    return objc_getAssociatedObject(self, &CharonTablePrefetchDataSourceKey);
}

- (void)setPrefetchDataSource:(id<UITableViewDataSourcePrefetching>)prefetchDataSource
{
    objc_setAssociatedObject(self, &CharonTablePrefetchDataSourceKey, prefetchDataSource, OBJC_ASSOCIATION_ASSIGN);
}

- (NSArray<NSIndexPath *> *)charon_prefetchRowCandidates
{
    NSArray<NSIndexPath *> *visible = self.indexPathsForVisibleRows;
    if (!visible.count)
        return @[];
    NSMutableArray<NSIndexPath *> *candidates = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSMutableDictionary<NSNumber *, NSNumber *> *distance = [NSMutableDictionary dictionary];
    for (NSIndexPath *path in visible) {
        for (NSInteger step = 1; step <= CharonTablePrefetchDistance; step++) {
            for (NSInteger direction = -1; direction <= 1; direction += 2) {
                NSInteger row = path.row + direction * step;
                if (row < 0 || row >= [self numberOfRowsInSection:path.section])
                    continue;
                NSIndexPath *candidate = [NSIndexPath indexPathForRow:row inSection:path.section];
                NSNumber *key = @(candidate.section * 1000000 + candidate.row);
                if ([seen containsObject:key])
                    continue;
                [seen addObject:key];
                [candidates addObject:candidate];
                distance[key] = @(step);
            }
        }
    }
    return [candidates sortedArrayUsingComparator:^NSComparisonResult(NSIndexPath *a, NSIndexPath *b) {
        NSComparisonResult byDistance = [distance[@(a.section * 1000000 + a.row)] compare:distance[@(b.section * 1000000 + b.row)]];
        if (byDistance != NSOrderedSame)
            return byDistance;
        if (a.section != b.section)
            return a.section < b.section ? NSOrderedAscending : NSOrderedDescending;
        return a.row < b.row ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)charon_prefetchRows
{
    id<UITableViewDataSourcePrefetching> source = self.prefetchDataSource;
    if (!source)
        return;
    NSArray<NSIndexPath *> *candidates = [self charon_prefetchRowCandidates];
    NSMutableSet<NSIndexPath *> *wants = [NSMutableSet setWithArray:candidates];
    NSMutableSet<NSIndexPath *> *asked = objc_getAssociatedObject(self, &CharonTablePrefetchAskedKey);
    if (!asked) {
        asked = [NSMutableSet set];
        objc_setAssociatedObject(self, &CharonTablePrefetchAskedKey, asked, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSArray<NSIndexPath *> *cancelled = [asked.allObjects filteredArrayUsingPredicate:
                                         [NSPredicate predicateWithBlock:^BOOL(NSIndexPath *path, NSDictionary *bindings) {
                                             return ![wants containsObject:path];
                                         }]];
    if (cancelled.count && [source respondsToSelector:@selector(tableView:cancelPrefetchingForRowsAtIndexPaths:)])
        [source tableView:self cancelPrefetchingForRowsAtIndexPaths:cancelled];
    [asked minusSet:[NSSet setWithArray:cancelled]];
    NSArray<NSIndexPath *> *fresh = [candidates filteredArrayUsingPredicate:
                                      [NSPredicate predicateWithBlock:^BOOL(NSIndexPath *path, NSDictionary *bindings) {
                                          return ![asked containsObject:path];
                                      }]];
    if (fresh.count && [source respondsToSelector:@selector(tableView:prefetchRowsAtIndexPaths:)])
        [source tableView:self prefetchRowsAtIndexPaths:fresh];
    [asked addObjectsFromArray:fresh];
}

@end
