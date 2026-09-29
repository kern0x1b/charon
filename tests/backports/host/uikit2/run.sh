#!/bin/sh
# run.sh — differential host tests for the second UIKit batch: the backported sources are compiled for
# Mac Catalyst with their classes, selectors and constants renamed, so each test can put the backport and
# the system implementation side by side in one process. The spring curve is checked against a real
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

group() {
    # $1: group name, $2: sources, $3: selectors to keep, $4: test source
    name=$1
    files=$2
    keep=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$keep" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/$test" "$harness/check.m" $built $frameworks -o "$build/$name-test"
    if "$build/$name-test" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed() {
    # $1: group name, $2: sources, $3: selectors to keep, $4: test source; the test runs in an application with a window
    name=$1
    files=$2
    keep=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$keep" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    bundle="$build/$name.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/windowed.m" "$here/$test" "$harness/check.m" $built $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    if "$bundle/Contents/MacOS/app" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" | grep -a 'FAIL\|checks=\|info' || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed_expected() {
    # $1: group name, $2: sources, $3: selectors to keep, $4: test source run against the port, $5: source that records what the system answers, in a process with none of the port's code
    name=$1
    files=$2
    keep=$3
    test=$4
    recorder=$5
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
    windowed "$name" "$files" "$keep" "$test"
}

renamed_keep() {
    # $1: object files, $2: the selectors that are renamed; every other selector the objects define keeps its name
    printf '%s\n' $2 > "$build/rename.list"
    nm $1 | sed -n 's/.*[-+]\[[A-Za-z_]*(*[A-Za-z]*)* \([A-Za-z_][A-Za-z0-9_]*\).*\]$/\1/p' | grep -v '^charon_' | sort -u | grep -v -x -f "$build/rename.list" | tr '\n' ' '
}

windowed_renamed() {
    # $1: group name, $2: sources, $3: selectors that get renamed, $4: test source; as windowed, but only the classes and the named selectors are renamed
    name=$1
    files=$2
    renamed=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$(renamed_keep "$objects" "$renamed")" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    bundle="$build/$name.app"
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/windowed.m" "$here/$test" "$harness/check.m" $built $frameworks -o "$bundle/Contents/MacOS/app"
    cp "$here/windowed.plist" "$bundle/Contents/Info.plist"
    codesign -s - --force "$bundle" > /dev/null 2>&1
    if "$bundle/Contents/MacOS/app" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" | grep -a 'FAIL\|checks=\|info' || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

renamed() {
    # $1: group name, $2: sources, $3: selectors that get renamed, $4: test source; as group, but only the classes and the named selectors are renamed
    name=$1
    files=$2
    renamed=$3
    test=$4
    objects=""
    for file in $files; do
        xcrun clang $target $flags -w -c "$sources/$file" -o "$build/plain/$name-$(basename "$file").o"
        objects="$objects $build/plain/$name-$(basename "$file").o"
    done
    renames "$objects" "$(renamed_keep "$objects" "$renamed")" > "$build/$name.flags"
    mkdir -p "$build/$name"
    built=""
    for file in $files; do
        xcrun clang $target $flags $(cat "$build/$name.flags") -c "$sources/$file" -o "$build/$name/$(basename "$file").o"
        built="$built $build/$name/$(basename "$file").o"
    done
    xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/$test" "$harness/check.m" $built $frameworks -o "$build/$name-test"
    if "$build/$name-test" > "$build/$name.log" 2>&1; then result=0; else result=$?; fi
    grep -v '^ok ' "$build/$name.log" || true
    echo "$name: exit=$result log=$build/$name.log"
    [ "$result" = 0 ] || status=1
}

windowed_renamed_expected() {
    # $1: group name, $2: sources, $3: selectors that get renamed, $4: test source run against the port, $5: source that records what the system answers, in a process with none of the port's code
    name=$1
    files=$2
    renamed=$3
    test=$4
    recorder=$5
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
    windowed_renamed "$name" "$files" "$renamed" "$test"
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

windowed inert "UILargeContentViewer.m UIScreenshotService.m UITextFormattingCoordinator.m UITextPlaceholder.m UIScribbleInteraction.m UIPointerLockState.m" inert_test.m

windowed traits13 "UITraitCollection.m UITraitCollection+UserInterfaceStyle.m UITraitCollection+Appearance13.m UITraitCollection+Appearance14.m UIScreen+TraitEnvironment.m UIImageConfiguration.m UIImageSymbolConfiguration.m UIImageSymbolWeight.m UIImageSymbolGlyphs.m UIImage+Baseline13.m UIImage+iOS13.m UIImage+Symbols.m UIImageView+SymbolConfiguration.m" traits13_test.m

windowed_expected controlactions "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m UICommand.m UIControl+Actions14.m UIControl+Menus14.m UIButton+Actions14.m" controlactions_test.m controlactions_system.m

windowed_expected controlmenus "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m UICommand.m UIControl+Actions14.m UIControl+Menus14.m UIButton+Actions14.m UIButton+iOS13.m UIBarButtonItem+Actions14.m UISegmentedControl+Actions14.m" controlmenus_test.m controlmenus_system.m

windowed_expected views13 "UIView+iOS13.m UIViewController+iOS13.m UIDatePicker+Style134.m UIPanGestureRecognizer+ScrollTypes134.m UISwitch+Style14.m UIPageControl+Indicators14.m UILabel+LineBreakStrategy14.m UIView+FocusGroup14.m UIScrollView+IndicatorInsets13.m UISegmentedControl+SelectedTint13.m UISplitViewController+Background13.m UITextView+TextScaling13.m UISearchBar+ScopeBar13.m UIScreen+Latency13.m UIAccessibility13.m UIAccessibility14.m UIAccessibilityCustomAction+Handler13.m UIAccessibilityCustomAction+Image14.m NSLayoutManager+Text13.m UIResponder+ItemsConfiguration.m UIVibrancyEffect+Style13.m UIFontSystemDesign.m UIViewController+Appearing13.m UIViewController+Unwind13.m NSAttributedString+Constants13.m NSAttributedString+Tracking14.m UIPasteboard+Detection14.m UINavigationItem+BackDisplayMode14.m UITextInput+AttributedReplace13.m UICommand.m UIMenuElement.m" views13_test.m views13_system.m

windowed_expected images13 "UIImage+iOS13.m UIImage+Baseline13.m UIImageConfiguration.m UIImageSymbolConfiguration.m UIImageSymbolWeight.m UIImageSymbolGlyphs.m UIImage+Symbols.m UIImageView+SymbolConfiguration.m" images13_test.m images13_system.m

windowed_expected colors13 "UIColorDynamic.m" colors13_test.m colors13_system.m

windowed listmenus "UIMenuElement.m UIAction.m UIAction+iOS14.m UIMenu.m UIMenu+iOS14.m UIDeferredMenuElement.m UIMenuIdentifiers.m UIMenuIdentifiers14.m UIMenuSystem.m UIContextMenuConfiguration.m UIContextMenuInteraction.m UIContextMenuInteraction+iOS14.m UIPreviewParameters.m UIPreviewParameters+iOS14.m UIPreviewTarget.m UITargetedPreview.m UICommand.m CharonListMenu.m UITableView+ContextMenu14.m UICollectionView+ContextMenu132.m" listmenus_test.m

windowed appearing "UIViewController+Appearing13.m" appearing_test.m

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
windowed listcell "CharonLists.m CharonConfigurationHost.m UICellAccessory.m UIViewConfigurationState.m UIListContentProperties.m UIListContentConfiguration.m UIBackgroundConfiguration.m UIListContentView.m UICollectionViewCell+Configuration.m UITableViewCell+Configuration.m UITableViewHeaderFooterView+Configuration.m UICollectionViewListCell.m UICollectionView+Editing.m UICollectionViewRegistration.m UICollectionLayoutListConfiguration.m UICollectionViewCompositionalLayout+ListConfiguration.m NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m NSDiffableDataSourceSnapshot.m CharonDiffable.m UICollectionViewDiffableDataSource.m CharonSwipeViews.m UICollectionView+SwipeActions.m UIContextualAction.m UISwipeActionsConfiguration.m" listcell_test.m

windowed listactions "CharonLists.m CharonConfigurationHost.m UICellAccessory.m UIViewConfigurationState.m UIListContentProperties.m UIListContentConfiguration.m UIBackgroundConfiguration.m UIListContentView.m UICollectionViewCell+Configuration.m UITableViewCell+Configuration.m UITableViewHeaderFooterView+Configuration.m UICollectionViewListCell.m UICollectionView+Editing.m UICollectionViewRegistration.m UICollectionLayoutListConfiguration.m UICollectionViewCompositionalLayout+ListConfiguration.m NSCollectionLayoutValues.m NSCollectionLayoutItems.m UICollectionViewCompositionalLayout.m CharonOrthogonalScroll.m CharonSelfSizing.m NSCollectionLayoutSection+iOS14.m UICollectionViewCompositionalLayoutConfiguration+iOS14.m NSDiffableDataSourceSnapshot.m CharonDiffable.m UICollectionViewDiffableDataSource.m NSDiffableDataSourceSectionSnapshot.m UICollectionViewDiffableDataSource+iOS14.m UICollectionViewDiffableDataSourceHandlers.m NSDiffableDataSourceTransaction.m UICollectionView+InteractiveMovement.m CharonSwipeViews.m UICollectionView+SwipeActions.m UIContextualAction.m UISwipeActionsConfiguration.m" listactions_test.m


windowed_expected transformers "UIConfigurationColorTransformers14.m" transformers_test.m transformers_system.m

group foundation14filehandle "../Foundation/NSFileHandle+Errors13.m" foundation14_filehandle_test.m

group foundation14compression "../Foundation/NSData+Compression13.m ../Foundation/CharonLZMA.m" foundation14_compression_test.m

group foundation14listformatter "../Foundation/NSListFormatter.m" foundation14_listformatter_test.m

group foundation14units "../Foundation/NSDimension.m ../Foundation/NSUnit.m ../Foundation/NSUnitConverter.m ../Foundation/NSUnitConverterLinear.m ../Foundation/NSUnitConverterReciprocal.m ../Foundation/NSMeasurement.m ../Foundation/NSUnitInformationStorage.m" foundation14_units_test.m

group foundation14bytecount "../Foundation/NSDimension.m ../Foundation/NSUnit.m ../Foundation/NSUnitConverter.m ../Foundation/NSUnitConverterLinear.m ../Foundation/NSUnitConverterReciprocal.m ../Foundation/NSMeasurement.m ../Foundation/NSUnitInformationStorage.m ../Foundation/NSUnitLength.m ../Foundation/NSByteCountFormatter+Measurement13.m" foundation14_bytecount_test.m

group foundation14httpresponse "../Foundation/NSHTTPURLResponse+HeaderField13.m" foundation14_httpresponse_test.m

group foundation14collections "../Foundation/NSCoder+Collections14.m ../Foundation/NSKeyedUnarchiver+Collections14.m" foundation14_collections_test.m

group foundation14queue "../Foundation/NSOperationQueue+Barrier13.m" foundation14_queue_test.m

group foundation14websocket "../Foundation/NSURLSessionWebSocket13.m" foundation14_websocket_test.m

group foundation14directoryenumerator "../Foundation/NSDirectoryEnumerator+PostOrder13.m" foundation14_directoryenumerator_test.m

group foundation14cookie "../Foundation/NSHTTPCookie+SameSite13.m" foundation14_cookie_test.m

group foundation14networkaccess "../Foundation/NSURLRequest+NetworkAccess13.m ../Foundation/NSURLSessionConfiguration+NetworkAccess13.m" foundation14_networkaccess_test.m

group foundation14resourcekeys "../Foundation/NSURLResourceKeys14.m" foundation14_resourcekeys_test.m

group foundation14useractivity "../Foundation/NSUserActivity.m ../Foundation/NSUserActivity+TargetContent13.m" foundation14_useractivity_test.m

group foundation14urlcache "../Foundation/NSURLCache+DirectoryURL13.m" foundation14_urlcache_test.m
group traits17 "UITraitCollection.m UITraitCollection+UserInterfaceStyle.m UITraitCollection+Appearance13.m UITraitCollection+Appearance14.m UITraitCollection+Traits10.m UITraitCollection+ForceTouch.m UITrait17.m UITraitList18.m UITrait26.m UITraitCollection+TraitStore.m UITraitCollection+Traits17.m UITraitOverrides17.m" traits17_test.m
group textkit2 "NSTextRange15.m NSTextSelection15.m NSTextElement15.m NSTextElement16.m NSTextSelectionNavigation15.m" textkit2_test.m
group content15 "NSTextContentManager15.m NSTextContentStorage15.m NSTextListElement16.m NSTextElement15.m NSTextElement16.m CharonTextLocation.m" content15_test.m


# the spring curve: UIKit's own parameters, our solver, and a real CASpringAnimation
xcrun clang $target -fobjc-arc -Wall -w -I"$harness" "$here/spring_uikit.m" $frameworks -o "$build/spring_uikit"
xcrun clang $target $flags -w -c "$sources/UIView+SpringAnimation.m" -o "$build/plain/spring.o"
xcrun clang $target -fobjc-arc -Wall -I"$harness" "$here/spring_ours.m" "$harness/check.m" "$build/plain/spring.o" $frameworks -o "$build/spring_ours"
xcrun clang -fobjc-arc -Wall -I"$harness" "$here/spring_sample.m" "$harness/check.m" -framework AppKit -framework QuartzCore -o "$build/spring_sample"
"$build/spring_uikit" > "$build/spring_uikit.txt"
if "$build/spring_ours" "$build/spring_uikit.txt" "$build/spring_samples.txt" > "$build/spring_ours.log" 2>&1; then result=0; else result=$?; fi
grep -v '^ok ' "$build/spring_ours.log" || true
echo "spring_ours: exit=$result log=$build/spring_ours.log"
[ "$result" = 0 ] || status=1
if "$build/spring_sample" < "$build/spring_samples.txt" > "$build/spring_sample.log" 2>&1; then result=0; else result=$?; fi
grep -v '^ok ' "$build/spring_sample.log" || true
echo "spring_sample: exit=$result log=$build/spring_sample.log"
[ "$result" = 0 ] || status=1
exit $status
