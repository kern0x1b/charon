#!/bin/sh
# run.sh — differential host tests for the second UIKit batch: the backported sources are compiled for
# Mac Catalyst with their classes and exported C symbols renamed by renames.sh, and the selectors their
# Charon categories carry prefixed whole by prefix_selectors.py, so each test can put the backport and the
# system implementation side by side in one process. The spring curve is checked against a real
# CASpringAnimation, which needs AppKit, so that part runs as a plain macOS tool.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sources=${UIKIT2_SOURCES:-$here/../../../../packages/a/apple-backports/UIKit}
harness=${UIKIT2_HARNESS:-$here/../../device}
build=${UIKIT2_BUILD:-${TMPDIR:-/tmp}/charon-uikit2-host}
sdk=$(xcrun --show-sdk-path)
target="-target arm64-apple-ios15.0-macabi -isysroot $sdk -iframework $sdk/System/iOSSupport/System/Library/Frameworks"
frameworks="-framework LocalAuthentication -framework MobileCoreServices -framework SafariServices -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation"
flags="-DCHARON_HOST_DIFFERENTIAL=1 -fobjc-arc -fvisibility=hidden -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-protocol-method-implementation -Wno-incomplete-implementation -Wno-objc-property-implementation"
rm -rf "$build"
mkdir -p "$build/plain"
export CHARON_DATA_ASSETS="$here/../../device/data-assets/Assets.car"
if [ -n "${CHARON_DATA_ASSET_CATALOG:-}" ] && [ -f "$CHARON_DATA_ASSET_CATALOG" ]; then
    assetutil --info "$CHARON_DATA_ASSET_CATALOG" > "${TMPDIR:-/tmp}/charon-dataassets.json"
fi

. "$here/renames.sh"
prefixer="$here/../prefix_selectors.py"

defines_what_it_calls() {
    # $1: the test's binary, rest: the port's objects. A renamed selector the test names and no object
    # defines is a link-time no-op and an unrecognized selector when the test reaches it, which nothing in
    # the gate sees; check-private-selectors.py is the check, and it runs over what this group just built.
    if ! python3 "$here/../check-private-selectors.py" "$@"; then
        status=1
    fi
}

carried() {
    # $1: every object of the group. The selectors the port's Charon categories carry, in the whole group and not
    # per file: a file that sends one of them without defining it - NSOrderedSet+Difference.m sending
    # -charon_differenceFromArray:... to an NSArray, which NSArray+Difference.m defines - needs the rename as
    # much as the file that defines it, and a send left unrenamed is an unrecognized selector at run time.
    nm $1 | sed -n 's/.*[-+]\[[A-Za-z_]*(\(Charon[A-Za-z0-9_]*\)) \([A-Za-z_][A-Za-z0-9_:]*\)\]$/\2/p' | sort -u > "$build/$name.carried"
    [ -s "$build/$name.carried" ]
}

build() {
    # $1: group name, $2: the source files. Each is compiled once plain, to learn the classes and C symbols it
    # defines and the selectors its Charon categories carry, then rewritten by prefix_selectors.py, which prefixes
    # those selectors whole (a -D could only prefix one piece, and the SDK's own headers use those words), then
    # compiled again with the class renames and the declarations of the prefixed selectors. A file that does not
    # compile fails its own group and no other: 74 groups in one run must all report.
    name=$1
    files=$2
    objects=""
    for file in $files; do
        if ! xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"; then
            printf 'FAIL %s: %s does not compile\n' "$name" "$file"
            status=1
            return 1
        fi
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" > "$build/$name.flags"
    carried "$objects" || : > "$build/$name.carried"
    [ -s "$build/$name.carried" ] || printf 'note %s carries no selector a category adds\n' "$name"
    mkdir -p "$build/rewritten/$name" "$build/$name"
    printf '#import <UIKit/UIKit.h>\n' > "$build/$name.declarations.h"
    # Every file of a group that carries a selector is rewritten, and all of them before any is compiled: a file
    # sends a selector another file defines (NSOrderedSet+Difference.m sends -charon_differenceFromArray:... to
    # an NSArray), and a send is invisible in nm, so nothing here can tell which files send what - only the
    # rewrite can, and it either renames every carried send or fails with the file and line it cannot place.
    for file in $files; do
        base=$(basename "$file")
        source=$build/rewritten/$name/$base
        # a rewritten file sits outside the source tree, so the headers it imports by name are reached by path
        if [ -s "$build/$name.carried" ]; then
            if ! python3 "$prefixer" "$sources/$file" "$source" charonHost \
                --declarations="$build/$name.declarations.h" $flags -I"$sources" -I"$(dirname "$sources/$file")" \
                -target arm64-apple-ios15.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" \
                -- $objects; then
                printf 'FAIL %s: %s cannot be rewritten\n' "$name" "$file"
                status=1
                return 1
            fi
        else
            cp "$sources/$file" "$source"
        fi
    done
    built=""
    for file in $files; do
        base=$(basename "$file").o
        source=$build/rewritten/$name/${base%.o}
        if ! xcrun clang $target $flags -I"$sources" -I"$(dirname "$sources/$file")" \
            -include "$build/$name.declarations.h" $(cat "$build/$name.flags") -c "$source" -o "$build/$name/$base"; then
            printf 'FAIL %s: the rewritten %s does not compile\n' "$name" "$file"
            status=1
            return 1
        fi
        built="$built $build/$name/$base"
    done
}

group() {
    # $1: group name, $2: sources, $3: test source
    name=$1
    build "$name" "$2" || return 0
    test=$3
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/$test" "$harness/check.m" $built $frameworks -o "$build/$name-test"
    defines_what_it_calls "$build/$name-test" $built
    if "$build/$name-test" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed() {
    # $1: group name, $2: sources, $3: test source; the test runs in an application with a window
    name=$1
    build "$name" "$2" || return 0
    test=$3
    bundle="$build/$name.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/windowed.m" "$here/$test" "$harness/check.m" $built $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    defines_what_it_calls "$bundle/Contents/MacOS/app" $built
    if "$bundle/Contents/MacOS/app" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" | grep -a 'FAIL\|checks=\|info' || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed_expected() {
    # $1: group name, $2: sources, $3: test source run against the port, $4: source that records what the system
    # answers, in a process with none of the port's code
    name=$1
    files=$2
    test=$3
    recorder=$4
    bundle="$build/$name-system.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -w -I"$harness" "$here/windowed.m" "$here/$recorder" "$harness/check.m" $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    expected="$build/$name.expected"
    if CHARON_EXPECTED="$expected" "$bundle/Contents/MacOS/app" > "$build/$name-system.log" 2>&1; then result=0; else result=$?; fi
    echo "$name-system: exit=$result log=$build/$name-system.log"
    [ "$result" = 0 ] || status=1
    CHARON_EXPECTED="$expected"
    export CHARON_EXPECTED
    windowed "$name" "$files" "$test"
}

status=0
group traits "UITraitCollection.m UITraitCollection+UserInterfaceStyle.m UITraitCollection+Appearance13.m UITraitCollection+Appearance14.m UIImageConfiguration.m UIImageSymbolConfiguration.m UIImageSymbolWeight.m UIImageSymbolGlyphs.m UIImage+Baseline13.m UIImage+iOS13.m UIImage+Symbols.m UIImageView+SymbolConfiguration.m" traits_test.m
group notifications "UIUserNotificationSettings.m" notifications_test.m
group misc "UIScreen+NativeBounds.m UIFont+TextStyles.m UIFont+Weights.m UIFontWidths.m UIFontWidths8.m UIColor+SystemColors.m UIColor+SystemPurpleColor.m UIColorDynamic.m UIImage+RenderingMode.m UITextField+DefaultTextAttributes.m UIViewController+ExtendedLayout.m" misc_test.m
group motion "UIMotionEffect.m UIView+MotionEffects.m" motion_test.m
group sizes "UIContentSizeCategory.m UIContentSizeCategory+Unspecified.m" sizes_test.m
group tint "UIView+TintColor.m" tint_test.m
group bars "UINavigationBar+BarAppearance.m UISearchBar+BarStyle.m UIToolbar+BarTintColor.m UITabBar+BarTintColor.m" bars_test.m
group viewmisc "UIView+MaskView.m UIView+PerformWithoutAnimation.m UIView+SemanticContentAttribute.m UIViewController+ViewLoading.m UIViewController+PreferredContentSize.m UIViewController+StatusBarAppearance.m" viewmisc_test.m
group attributestransform "UICollectionViewLayoutAttributes+Transform7.m" attributestransform_test.m
group rowaction "UITableViewRowAction.m" rowaction_test.m
group visualeffect "UIVisualEffect.m UIVisualEffectView.m CharonBlur.m CharonBackdrop.m" visualeffect_test.m
group useractivity "../Foundation/NSUserActivity.m" useractivity_test.m
group localauth "../LocalAuthentication/LAContext.m ../LocalAuthentication/LAErrorDomain.m ../LocalAuthentication/LATouchIDAuthenticationMaximumAllowableReuseDuration.m" localauth_test.m
group documentpicker "UIDocumentPickerViewController.m CharonDocumentBrowser.m" documentpicker_test.m
group datecomponentsformatter "../Foundation/NSDateComponentsFormatter.m" datecomponentsformatter_test.m
group runloopobserver "../Foundation/CFRunLoopObserverHandler.m" runloopobserver_test.m
group tabledimension "UITableViewAutomaticDimension.m" tabledimension_test.m
group scenes "UISceneValues.m UISceneConstants.m UISceneConstants16.m" scenes_test.m
group cornercurve "CALayer+CornerCurve.m" cornercurve_test.m
group relativedatetimeformatter "../Foundation/NSRelativeDateTimeFormatter.m" relativedatetimeformatter_test.m
group itemprovider "../Foundation/NSItemProvider.m" itemprovider_test.m
group itemproviderbuiltins "../Foundation/NSString+ItemProvider.m ../Foundation/NSURL+ItemProvider.m" itemproviderbuiltins_test.m
group nsdataasset "NSDataAsset.m" nsdataasset_test.m
group safariviewcontroller "../SafariServices/CharonSafariPage.m ../SafariServices/SFSafariViewController.m ../SafariServices/SFSafariViewControllerConfiguration.m ../SafariServices/SFSafariViewControllerActivityButton.m ../SafariServices/SFSafariViewControllerPrewarmingToken.m ../SafariServices/SFAuthenticationSession.m ../SafariServices/SFAuthenticationErrorDomain.m" safariviewcontroller_test.m
export APPEARANCES_EXPECTATIONS="$harness/appearances-expectations.h"
group appearances "CharonBarAppearance.m CharonBarAppearanceApply.m CharonBarAppearanceTracking.m UIBarAppearance.m UINavigationBarAppearance.m UIToolbarAppearance.m UITabBarAppearance.m UIBarButtonItemAppearance.m UITabBarItemAppearance.m UINavigationBarAppearance+Prominent.m UINavigationBar+Appearances.m UIToolbar+Appearances.m UITabBar+Appearances.m UINavigationItem+Appearances.m UITabBarItem+Appearances.m UIBar+ScrollEdgeAppearances.m" appearances_test.m
group orderedcollections "../Foundation/NSOrderedCollectionChange.m ../Foundation/NSOrderedCollectionDifference.m ../Foundation/NSArray+Difference.m ../Foundation/NSOrderedSet+Difference.m" orderedcollections_test.m
group diffable "NSDiffableDataSourceSnapshot.m" diffable_test.m
group diffablesection "NSDiffableDataSourceSectionSnapshot.m" diffablesection_test.m
windowed diffabledatasource "NSDiffableDataSourceSnapshot.m CharonDiffable.m UICollectionViewDiffableDataSource.m UITableViewDiffableDataSource.m" diffabledatasource_test.m
windowed diffablesectiondatasource "NSDiffableDataSourceSnapshot.m NSDiffableDataSourceSectionSnapshot.m CharonDiffable.m UICollectionViewDiffableDataSource.m UITableViewDiffableDataSource.m UICollectionViewDiffableDataSource+iOS14.m UICollectionViewDiffableDataSourceHandlers.m" diffablesectiondatasource_test.m
windowed snapshots "UIView+Snapshots.m" snapshots_test.m
windowed menucontroller "UIMenuController+iOS13.m" menucontroller_test.m
group symbols "UIImageConfiguration.m UIImageSymbolConfiguration.m UIImageSymbolWeight.m UIImageSymbolGlyphs.m UIImage+Baseline13.m UIImage+iOS13.m UIImage+Symbols.m UIImageView+SymbolConfiguration.m" symbols_test.m
windowed menus "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m" menus_test.m
windowed pointer "UIPointerRegion.m UIPointerStyle.m UIPointerInteraction.m UIHoverGestureRecognizer.m UIKey.m UIKeyInputKeys.m" pointer_test.m
windowed pointercategories "UIEvent+Pointer.m UIGestureRecognizer+Pointer.m UIButton+Pointer.m" pointercategories_test.m
windowed search "UISearchToken.m UISearchTextField.m" search_test.m
windowed searchcategories "UISearchBar+SearchTextField.m UISearchController+ScopeBar.m" searchcategories_test.m
windowed colors "UIColorWell.m UIColorPickerViewController.m" colors_test.m
group commands "UIMenuElement.m UICommand.m UIKeyCommand.m UIKeyCommand+Priority.m" commands_test.m
group activityitems "UIActivityItemsConfiguration.m" activityitems_test.m
windowed fontpicker "UIFontPickerViewController.m" fontpicker_test.m
windowed_renamed inert "UILargeContentViewer.m UIScreenshotService.m UITextFormattingCoordinator.m UITextPlaceholder.m UIScribbleInteraction.m UIPointerLockState.m" inert_test.m
windowed_renamed traits13 "UITraitCollection.m UITraitCollection+UserInterfaceStyle.m UITraitCollection+Appearance13.m UITraitCollection+Appearance14.m UIScreen+TraitEnvironment.m UIImageConfiguration.m UIImageSymbolConfiguration.m UIImageSymbolWeight.m UIImageSymbolGlyphs.m UIImage+Baseline13.m UIImage+iOS13.m UIImage+Symbols.m UIImageView+SymbolConfiguration.m" traits13_test.m
windowed_expected controlactions "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m UICommand.m UIControl+Actions14.m UIControl+Menus14.m UIButton+Actions14.m" controlactions_test.m controlactions_system.m
windowed_expected controlmenus "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m UICommand.m UIControl+Actions14.m UIControl+Menus14.m UIButton+Actions14.m UIButton+iOS13.m UIBarButtonItem+Actions14.m UISegmentedControl+Actions14.m" controlmenus_test.m controlmenus_system.m
windowed_expected views13 "UIView+iOS13.m UIViewController+iOS13.m UIDatePicker+Style134.m UIPanGestureRecognizer+ScrollTypes134.m UISwitch+Style14.m UIPageControl+Indicators14.m UILabel+LineBreakStrategy14.m UIView+FocusGroup14.m UIScrollView+IndicatorInsets13.m UISegmentedControl+SelectedTint13.m UISplitViewController+Background13.m UITextView+TextScaling13.m UISearchBar+ScopeBar13.m UIScreen+Latency13.m UIAccessibility13.m UIAccessibility14.m UIAccessibilityCustomAction+Handler13.m UIAccessibilityCustomAction+Image14.m NSLayoutManager+Text13.m UIResponder+ItemsConfiguration.m UIVibrancyEffect+Style13.m UIFontSystemDesign.m UIViewController+Appearing13.m UIViewController+Unwind13.m NSAttributedString+Constants13.m NSAttributedString+Tracking14.m UIPasteboard+Detection14.m UINavigationItem+BackDisplayMode14.m UITextInput+AttributedReplace13.m UICommand.m UIMenuElement.m" views13_test.m views13_system.m
windowed_expected images13 "UIImage+iOS13.m UIImage+Baseline13.m UIImageConfiguration.m UIImageSymbolConfiguration.m UIImageSymbolWeight.m UIImageSymbolGlyphs.m UIImage+Symbols.m UIImageView+SymbolConfiguration.m" images13_test.m images13_system.m
windowed_renamed_expected colors13 "UIColorDynamic.m" colors13_test.m colors13_system.m
windowed_renamed listmenus "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m UICommand.m CharonListMenu.m UITableView+ContextMenu14.m UICollectionView+ContextMenu132.m" listmenus_test.m
windowed_renamed appearing "UIViewController+Appearing13.m" appearing_test.m
windowed textinteraction "UITextInteraction.m" textinteraction_test.m
group layoutvalues "NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m" layoutvalues_test.m
export CHARON_ORTHOGONAL_EXPECTATIONS="$here/../../device/compositional-orthogonal-expectations.h"
export CHARON_SIZED_EXPECTATIONS="$here/../../device/compositional-sized-expectations.h"
export CHARON_COMPOSITIONAL_EXPECTATIONS="$here/../../device/compositional-expectations.h"
windowed compositionallayout "NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m CharonLists.m UICollectionViewCompositionalLayout+ListConfiguration.m" compositionallayout_test.m
windowed orthogonal "NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m CharonLists.m UICollectionViewCompositionalLayout+ListConfiguration.m" orthogonal_test.m
windowed sizedlayout "NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m CharonLists.m UICollectionViewCompositionalLayout+ListConfiguration.m" sizedlayout_test.m
group listvalues "CharonLists.m UICellAccessory.m UIViewConfigurationState.m UIListContentProperties.m UIListContentConfiguration.m UIBackgroundConfiguration.m UIListContentView.m" listvalues_test.m
export CHARON_LISTS_EXPECTATIONS="$here/../../device/lists-expectations.h"
windowed_renamed listcell "CharonLists.m CharonConfigurationHost.m UICellAccessory.m UIViewConfigurationState.m UIListContentProperties.m UIListContentConfiguration.m UIBackgroundConfiguration.m UIListContentView.m UICollectionViewCell+Configuration.m UITableViewCell+Configuration.m UITableViewHeaderFooterView+Configuration.m UICollectionViewListCell.m UICollectionView+Editing.m UICollectionViewRegistration.m UICollectionLayoutListConfiguration.m UICollectionViewCompositionalLayout+ListConfiguration.m NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m NSDiffableDataSourceSnapshot.m CharonDiffable.m UICollectionViewDiffableDataSource.m CharonSwipeViews.m UICollectionView+SwipeActions.m UIContextualAction.m UISwipeActionsConfiguration.m" listcell_test.m
windowed_expected transformers "UIConfigurationColorTransformers14.m" transformers_test.m transformers_system.m
windowed_renamed listactions "CharonLists.m CharonConfigurationHost.m UICellAccessory.m UIViewConfigurationState.m UIListContentProperties.m UIListContentConfiguration.m UIBackgroundConfiguration.m UIListContentView.m UICollectionViewCell+Configuration.m UITableViewCell+Configuration.m UITableViewHeaderFooterView+Configuration.m UICollectionViewListCell.m UICollectionView+Editing.m UICollectionViewRegistration.m UICollectionLayoutListConfiguration.m UICollectionViewCompositionalLayout+ListConfiguration.m NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m NSDiffableDataSourceSnapshot.m CharonDiffable.m UICollectionViewDiffableDataSource.m NSDiffableDataSourceSectionSnapshot.m UICollectionViewDiffableDataSource+iOS14.m UICollectionViewDiffableDataSourceHandlers.m NSDiffableDataSourceTransaction.m UICollectionView+InteractiveMovement.m CharonSwipeViews.m UICollectionView+SwipeActions.m UIContextualAction.m UISwipeActionsConfiguration.m" listactions_test.m


group foundation14filehandle "../Foundation/NSFileHandle+Errors13.m" foundation14_filehandle_test.m
group foundation14compression "../Foundation/NSData+Compression13.m ../Foundation/CharonLZMA.m" foundation14_compression_test.m
group foundation14listformatter "../Foundation/NSListFormatter.m" foundation14_listformatter_test.m
group foundation14units "../Foundation/NSDimension.m ../Foundation/NSUnit.m ../Foundation/NSUnitConverter.m ../Foundation/NSUnitConverterLinear.m ../Foundation/NSUnitConverterReciprocal.m ../Foundation/NSMeasurement.m ../Foundation/NSUnitInformationStorage.m" foundation14_units_test.m
renamed foundation14bytecount "../Foundation/NSDimension.m ../Foundation/NSUnit.m ../Foundation/NSUnitConverter.m ../Foundation/NSUnitConverterLinear.m ../Foundation/NSUnitConverterReciprocal.m ../Foundation/NSMeasurement.m ../Foundation/NSUnitInformationStorage.m ../Foundation/NSUnitLength.m ../Foundation/NSByteCountFormatter+Measurement13.m" foundation14_bytecount_test.m
group foundation14httpresponse "../Foundation/NSHTTPURLResponse+HeaderField13.m" foundation14_httpresponse_test.m
group foundation14collections "../Foundation/NSCoder+Collections14.m ../Foundation/NSKeyedUnarchiver+Collections14.m" foundation14_collections_test.m
renamed foundation14queue "../Foundation/NSOperationQueue+Barrier13.m" foundation14_queue_test.m
renamed foundation14websocket "../Foundation/NSURLSessionWebSocket13.m" foundation14_websocket_test.m
renamed foundation14directoryenumerator "../Foundation/NSDirectoryEnumerator+PostOrder13.m" foundation14_directoryenumerator_test.m
group foundation14cookie "../Foundation/NSHTTPCookie+SameSite13.m" foundation14_cookie_test.m
renamed foundation14networkaccess "../Foundation/NSURLRequest+NetworkAccess13.m ../Foundation/NSURLSessionConfiguration+NetworkAccess13.m" foundation14_networkaccess_test.m
group foundation14resourcekeys "../Foundation/NSURLResourceKeys14.m" foundation14_resourcekeys_test.m
group foundation14useractivity "../Foundation/NSUserActivity.m ../Foundation/NSUserActivity+TargetContent13.m" foundation14_useractivity_test.m
group foundation14urlcache "../Foundation/NSURLCache+DirectoryURL13.m" foundation14_urlcache_test.m
