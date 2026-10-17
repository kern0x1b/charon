#import <UIKit/UIKit.h>
#include <stdio.h>

// UISearchController's iOS 16 properties (the search bar placement, the scope bar activation, the suggestions' flag) and the iOS 13 scope
// bar flag, checked on the same values in two processes: the host's classes in one, and the port's (renamed by run.sh, so this file's names
// mean the port's classes in that build) in the other. Each line is "check<TAB>value"; the two outputs must match line for line. The
// placement is read for a controller in no navigation item, and for one held by an item. Not measured here, on purpose: the defaults of the
// scope bar flag and the activation. A Mac starts them Manual and NO, and the port starts them where the header says, Automatic and YES, as
// its facts record; the tests that hold the port to the header (uikit2's searchcategories and the device's pointer test) check that start.
// The suggestions are not in this test either: a process with no application reads back an empty array whatever is set, so the release's
// answer is not measured here.

static void report(const char *check, NSString *value)
{
    printf("%s\t%s\n", check, value ? [value UTF8String] : "nil");
}

static NSString *yes_no(BOOL answer)
{
    return answer ? @"yes" : @"no";
}

static NSString *number(long long value)
{
    return [NSString stringWithFormat:@"%lld", value];
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);

        UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
        report("placement-default", number(search.searchBarPlacement));
        report("ignores-default", yes_no(search.ignoresSearchSuggestionsForSearchBarPlacementStacked));

        // The scope bar flag and the activation are one setting: YES is Automatic, NO is Manual, and OnTextEntry reads as YES.
        search.automaticallyShowsScopeBar = NO;
        report("automatic-set-no", yes_no(search.automaticallyShowsScopeBar));
        report("scope-activation-after-no", number(search.scopeBarActivation));
        search.automaticallyShowsScopeBar = YES;
        report("scope-activation-after-yes", number(search.scopeBarActivation));
        report("automatic-after-yes", yes_no(search.automaticallyShowsScopeBar));
        search.scopeBarActivation = UISearchControllerScopeBarActivationOnTextEntry;
        report("scope-activation-set", number(search.scopeBarActivation));
        report("automatic-after-on-text-entry", yes_no(search.automaticallyShowsScopeBar));
        search.automaticallyShowsScopeBar = NO;
        report("scope-activation-after-no-from-on-text-entry", number(search.scopeBarActivation));
        search.scopeBarActivation = UISearchControllerScopeBarActivationAutomatic;
        report("automatic-after-automatic", yes_no(search.automaticallyShowsScopeBar));

        search.ignoresSearchSuggestionsForSearchBarPlacementStacked = YES;
        report("ignores-set", yes_no(search.ignoresSearchSuggestionsForSearchBarPlacementStacked));
        search.ignoresSearchSuggestionsForSearchBarPlacementStacked = NO;
        report("ignores-cleared", yes_no(search.ignoresSearchSuggestionsForSearchBarPlacementStacked));

        // A controller held by a navigation item is placed inline, and placed as a bare controller again once the item lets it go.
        UIViewController *root = [[UIViewController alloc] init];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
        root.navigationItem.searchController = search;
        report("placement-in-item", number(search.searchBarPlacement));
        report("navigation-class", NSStringFromClass([navigation class]));
        root.navigationItem.searchController = nil;
        report("placement-after-item-lets-go", number(search.searchBarPlacement));
    }
    return 0;
}
