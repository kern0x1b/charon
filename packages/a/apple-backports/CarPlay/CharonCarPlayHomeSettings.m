// The settings pane, and the state it keeps. See CharonCarPlayHomeSettings.h, and
// facts/CarPlay/CarPlay.md for what it is for and what it is not.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "CharonCarPlayHomeSettings.h"

// The row's own members. CPListItem is a CATEGORY on the aliased name (CPListItem.m), so the
// compiler does not know these here; they are the header's own, and the row is the class they are
// carried on.
@interface CPListItem (CharonSettingsRow)
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *detailText;
- (id)initWithText:(NSString *)text
         detailText:(NSString *)detailText
              image:(UIImage *)image
     accessoryImage:(UIImage *)accessoryImage
      accessoryType:(NSInteger)accessoryType;
- (void)charon_selected;
@end

// The key the state is kept under. The release's own defaults, so the daemon and the car screen read
// one thing, and the name is the port's own because this is the port's own state.
static NSString *const CharonCarPlayHomeStateKey = @"CharonCarPlayHomeState";

@implementation CharonCarPlayHomeSettings {
    CharonCarPlayAppList *_apps;
}

@synthesize apps = _apps;

+ (NSString *)defaultsKey
{
    return CharonCarPlayHomeStateKey;
}

+ (instancetype)shared
{
    static CharonCarPlayHomeSettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [[CharonCarPlayHomeSettings alloc] initWithApps:[[CharonCarPlayAppList alloc] initWithSearchPath:nil]];
    });
    return shared;
}

- (instancetype)initWithApps:(CharonCarPlayAppList *)apps
{
    self = [super init];
    if (self) {
        _apps = apps;
        [self charon_load];
    }
    return self;
}

// The state, out of the release's own defaults: the excluded bundle identifiers, and the order of the
// ones that are left. Both are plain strings, and a defaults domain the daemon can read.
- (void)charon_load
{
    NSDictionary *state = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CharonCarPlayHomeStateKey];
    if (![state isKindOfClass:[NSDictionary class]]) {
        return;
    }
    id excluded = [state objectForKey:@"excluded"];
    if ([excluded isKindOfClass:[NSArray class]]) {
        _apps.excludedBundleIdentifiers = excluded;
    }
    id order = [state objectForKey:@"order"];
    if (![order isKindOfClass:[NSArray class]]) {
        return;
    }
    // The order is applied by moving each app to the index it is listed at, so a partial or stale
    // order leaves the rest where they were rather than emptying the grid.
    NSArray *all = _apps.apps;
    for (NSUInteger at = 0; at < [order count]; at++) {
        NSString *identifier = [order objectAtIndex:at];
        if (![identifier isKindOfClass:[NSString class]]) {
            continue;
        }
        for (NSUInteger find = 0; find < all.count; find++) {
            if ([[all objectAtIndex:find] bundleIdentifier] == identifier ||
                [[[all objectAtIndex:find] bundleIdentifier] isEqualToString:identifier]) {
                [_apps moveBundleIdentifier:identifier toIndex:at];
                break;
            }
        }
    }
}

- (void)save
{
    NSMutableArray *order = [NSMutableArray array];
    for (id app_ in _apps.apps) {
        CharonCarPlayApp *app = app_;
        [order addObject:app.bundleIdentifier];
    }
    NSDictionary *state = @{@"excluded": _apps.excludedBundleIdentifiers ?: @[], @"order": order};
    [[NSUserDefaults standardUserDefaults] setObject:state forKey:CharonCarPlayHomeStateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

// The rows: the header's own CPListItem, with its own text, its own image -- the app's own icon, read
// at run time -- and this pane's own handler, which the release's own list template calls when the row
// is chosen.
@interface CharonCarPlaySettingsRow : CPListItem
@property (nonatomic, copy) NSString *action;   // "exclude", "include" or "move"
@property (nonatomic, assign) NSUInteger targetIndex;
- (instancetype)charon_initWithApp:(CharonCarPlayApp *)app
                             action:(NSString *)action
                              index:(NSUInteger)index
                           settings:(CharonCarPlayHomeSettings *)settings;
@end

@implementation CharonCarPlaySettingsRow {
    NSString *_action;
    NSUInteger _targetIndex;
    CharonCarPlayHomeSettings *_settings;
}

@synthesize action = _action;
@synthesize targetIndex = _targetIndex;

// The pane this row belongs to, held beside it because a row made through the header's own
// initialiser is the alias's class and not a fresh CharonCarPlaySettingsRow. Charon's own.
- (void)charon_setSettings:(CharonCarPlayHomeSettings *)settings
{
    _settings = settings;
    __weak CharonCarPlaySettingsRow *weak = self;
    // The row's own handler, which the release's own list template calls when the row is chosen.
    [self setHandler:^(id<CPSelectableListItem> item, dispatch_block_t completion) {
        [weak charon_perform];
        if (completion) {
            completion();
        }
    }];
}

- (instancetype)charon_initWithApp:(CharonCarPlayApp *)app
                             action:(NSString *)action
                              index:(NSUInteger)index
                           settings:(CharonCarPlayHomeSettings *)settings
{
    // Through the header's own designated initialiser, which the alias answers: a name the release
    // carries under a class of its own is an alias, and the category on it in this image is merged
    // into the alias's class.
    // Through the header's own designated initialiser, which the alias answers: a name the release
    // carries under a class of its own is an alias, and the category on it in this image is merged
    // into the alias's class. The result IS the row, so it is not assigned back to self -- a method
    // outside the init family may not do that.
    CharonCarPlaySettingsRow *row =
        ((id (*)(id, SEL, id, id, id, id, NSInteger))objc_msgSend)((id)[CPListItem class],
            @selector(initWithText:detailText:image:accessoryImage:accessoryType:),
            app.displayName, app.bundleIdentifier, app.icon, nil, (NSInteger)CPListItemAccessoryTypeNone);
    if (![row isKindOfClass:[CharonCarPlaySettingsRow class]]) {
        return nil;
    }
    [row setAction:[action copy]];
    [row setTargetIndex:index];
    [row charon_setSettings:settings];
    return row;
}

// The three actions, each one the port's own state and nothing else.
- (void)charon_perform
{
    if (!_settings || !_action) {
        return;
    }
    if ([_action isEqualToString:@"exclude"]) {
        [_settings.apps excludeBundleIdentifier:self.bundleIdentifier];
    } else if ([_action isEqualToString:@"include"]) {
        [_settings.apps includeBundleIdentifier:self.bundleIdentifier];
    } else if ([_action isEqualToString:@"move"]) {
        [_settings.apps moveBundleIdentifier:self.bundleIdentifier toIndex:_targetIndex];
    }
    [_settings save];
}

@end

// The pane's own data source and delegate, its own class beside the list template's, and the
// release's own grouped cells under it.
@interface CharonCarPlaySettingsSource : NSObject <UITableViewDataSource, UITableViewDelegate>
+ (instancetype)sourceForTemplate:(CharonCarPlayHomeSettingsTemplate *)template;
@end

@implementation CharonCarPlaySettingsSource {
    __weak CPListTemplate *_template;
}

+ (instancetype)sourceForTemplate:(CPListTemplate *)template
{
    CharonCarPlaySettingsSource *source = [[CharonCarPlaySettingsSource alloc] init];
    source->_template = template;
    return source;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)_template.sectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray<CPListSection *> *sections = _template.sections;
    if (section < 0 || (NSUInteger)section >= sections.count) {
        return 0;
    }
    return (NSInteger)sections[(NSUInteger)section].items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSArray<CPListSection *> *sections = _template.sections;
    if (section < 0 || (NSUInteger)section >= sections.count) {
        return nil;
    }
    return sections[(NSUInteger)section].header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *const cellIdentifier = @"CharonCarPlaySettingsRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:cellIdentifier];
        cell.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
        cell.textLabel.textColor = [CharonCarPlaySkin labelColour];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    }
    NSArray<CPListSection *> *sections = _template.sections;
    if ((NSUInteger)indexPath.section < sections.count) {
        NSArray<id<CPListTemplateItem>> *rows = sections[(NSUInteger)indexPath.section].items;
        if ((NSUInteger)indexPath.row < rows.count && [rows[(NSUInteger)indexPath.row] isKindOfClass:[CPListItem class]]) {
            CPListItem *item = (CPListItem *)rows[(NSUInteger)indexPath.row];
            cell.textLabel.text = item.text;
            cell.detailTextLabel.text = item.detailText;
            cell.imageView.image = item.image;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<CPListSection *> *sections = _template.sections;
    if ((NSUInteger)indexPath.section >= sections.count) {
        return;
    }
    NSArray<id<CPListTemplateItem>> *rows = sections[(NSUInteger)indexPath.section].items;
    if ((NSUInteger)indexPath.row >= rows.count) {
        return;
    }
    id<CPListTemplateItem> row = rows[(NSUInteger)indexPath.row];
    // The row's own handler, which is what a program gave the row, through the release's own list
    // template's own selection path.
    if ([row isKindOfClass:[CPListItem class]]) {
        [(CPListItem *)row charon_selected];
    }
}

@end

@implementation CharonCarPlayHomeSettingsTemplate {
    CharonCarPlayHomeSettings *_settings;
    UITableViewController *_list;
    UINavigationBar *_bar;
}

- (instancetype)initWithApps:(CharonCarPlayAppList *)apps
{
    self = [super initWithTitle:@"CarPlay" sections:@[]];
    if (self) {
        _settings = [[CharonCarPlayHomeSettings alloc] initWithApps:apps];
        self.tabTitle = @"Settings";
        [self charon_rebuild];
    }
    return self;
}

// Two sections: what is on the car screen, and what is not. A row in the first moves down, a row in
// the second goes back, and the state is saved after each so the daemon and the screen agree.
- (void)charon_rebuild
{
    NSMutableArray *included = [NSMutableArray array];
    NSMutableArray *excluded = [NSMutableArray array];
    NSUInteger visibleIndex = 0;
    for (id app_ in _settings.apps.apps) {
        CharonCarPlayApp *app = app_;
        if ([_settings.apps excludesBundleIdentifier:app.bundleIdentifier]) {
            CharonCarPlaySettingsRow *row = [[CharonCarPlaySettingsRow alloc]
                charon_initWithApp:app action:@"include" index:0 settings:_settings];
            [excluded addObject:row];
        } else {
            // A visible app gets a move row to the bottom, and the ones above it get a move row one
            // place down, so the order is set with a tap and not with a gesture a car screen has no
            // room for.
            CharonCarPlaySettingsRow *down = [[CharonCarPlaySettingsRow alloc]
                charon_initWithApp:app action:@"move" index:visibleIndex + 1 settings:_settings];
            down.detailText = [NSString stringWithFormat:@"%@ -- move down", app.bundleIdentifier];
            [included addObject:down];
            visibleIndex++;
        }
    }
    NSArray *sections = @[[[CPListSection alloc] initWithItems:included],
                          [[CPListSection alloc] initWithItems:excluded]];
    [self updateSections:sections];
    [_list.tableView reloadData];
}

// The pane, drawn by the list template's own code: the same release chrome as every other list, the
// same cells, the same bar.
- (UIViewController *)charon_viewControllerForInterfaceController:(CPInterfaceController *)controller
{
    if (_list) {
        return _list;
    }
    _list = [[UITableViewController alloc] initWithStyle:UITableViewStyleGrouped];
    _list.view.backgroundColor = [UIColor blackColor];
    _list.tableView.dataSource = (id)[CharonCarPlaySettingsSource sourceForTemplate:self];
    _list.tableView.delegate = (id)[CharonCarPlaySettingsSource sourceForTemplate:self];
    _bar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0.0, 0.0, 1024.0, 44.0)];
    _bar.barStyle = UIBarStyleBlack;
    _bar.translucent = NO;
    // UINavigationItem's title is a property and the bar's own top item is set through it: the
    // release's bar is told what to show, not handed a replacement item.
    _bar.topItem.title = @"CarPlay";
    [_list.view addSubview:_bar];
    [self charon_rebuild];
    return _list;
}

@end
