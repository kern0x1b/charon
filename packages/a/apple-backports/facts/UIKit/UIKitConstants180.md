# The UIKit constants first exported by iOS 18.0

`UIKit/UIKitConstants180.m`. 96 constants, one object, and every value read out of a real dyld
shared cache rather than taken from a header or from a host framework.

The reader is `tools/corpus/cache-value.lua` over this repository's own cache reader
(`modules/apple/dyld.lua`). It is checked before any value is taken: on each cache of
the ladder, eight constants whose value is their own name are read back, and a cache
that reproduces none of the ones it holds contributes nothing. On this ladder every
cache reproduced all eighteen of the checked strings it holds, and no constant's
value differed between caches.

| constant | the release it was read from | the value |
| --- | --- | --- |
| `NSAdaptiveImageGlyphAttributeName` | 18.0 | `@"CTAdaptiveImageProvider"` |
| `NSDefaultFontExcludedDocumentAttribute` | 18.0 | `@"NoDefaultFonts"` |
| `NSTextHighlightColorSchemeAttributeName` | 18.0 | `@"NSTextHighlightColorScheme"` |
| `NSTextHighlightColorSchemeBlue` | 18.0 | `@"NSTextHighlightColorSchemeBlue"` |
| `NSTextHighlightColorSchemeDefault` | 18.0 | `@"NSTextHighlightColorSchemeDefault"` |
| `NSTextHighlightColorSchemeMint` | 18.0 | `@"NSTextHighlightColorSchemeMint"` |
| `NSTextHighlightColorSchemeOrange` | 18.0 | `@"NSTextHighlightColorSchemeOrange"` |
| `NSTextHighlightColorSchemePink` | 18.0 | `@"NSTextHighlightColorSchemePink"` |
| `NSTextHighlightColorSchemePurple` | 18.0 | `@"NSTextHighlightColorSchemePurple"` |
| `NSTextHighlightStyleAttributeName` | 18.0 | `@"NSTextHighlightStyle"` |
| `NSTextHighlightStyleDefault` | 18.0 | `@"NSTextHighlightStyleDefault"` |
| `NSTextKit1ListMarkerFormatDocumentOption` | 18.0 | `@"TextKit1ListMarkerFormat"` |
| `UIAccessibilityCustomActionCategoryEdit` | 18.0 | `@"UIAccessibilityCustomActionCategoryEdit"` |
| `UIAccessibilityPriorityDefault` | 18.0 | `@"UIAccessibilityPriorityDefault"` |
| `UIAccessibilityPriorityHigh` | 18.0 | `@"UIAccessibilityPriorityHigh"` |
| `UIAccessibilityPriorityLow` | 18.0 | `@"UIAccessibilityPriorityLow"` |
| `UIAccessibilitySpeechAttributeAnnouncementPriority` | 18.0 | `@"UIAccessibilitySpeechAttributeAnnouncementPriority"` |
| `UIAccessibilityTraitSupportsZoom` | 18.0 | `70368744177664` |
| `UIAccessibilityTraitToggleButton` | 18.0 | `9007199254740992` |
| `UIActivityItemsConfigurationInteractionCopy` | 18.0 | `@"copy"` |
| `UIActivityItemsConfigurationMetadataKeyCollaborationModeRestrictions` | 18.0 | `@"collaborationModeRestrictions"` |
| `UIActivityItemsConfigurationMetadataKeyShareRecipients` | 18.0 | `@"shareRecipients"` |
| `UIActivityTypeAddToHomeScreen` | 18.0 | `@"com.apple.UIKit.activity.AddToHomeScreen"` |
| `UICollectionLayoutSectionOrthogonalScrollingDecelerationRateAutomatic` | 18.0 | `-1.0` |
| `UICollectionLayoutSectionOrthogonalScrollingDecelerationRateFast` | 18.0 | `0.99` |
| `UICollectionLayoutSectionOrthogonalScrollingDecelerationRateNormal` | 18.0 | `0.998` |
| `UIDocumentCreationIntentDefault` | 18.0 | `@"UIDocumentCreationIntentDefault"` |
| `UIFontTextStyleExtraLargeTitle` | 18.0 | `@"UICTFontTextStyleExtraLargeTitle"` |
| `UIFontTextStyleExtraLargeTitle2` | 18.0 | `@"UICTFontTextStyleExtraLargeTitle2"` |
| `UIMenuAutoFill` | 18.0 | `@"com.apple.menu.autofill"` |
| `UISceneSystemProtectionDidChangeNotification` | 18.0 | `@"UISceneSystemProtectionDidChangeNotification"` |
| `UITextContentTypeBirthdate` | 18.0 | `@"bday"` |
| `UITextContentTypeBirthdateDay` | 18.0 | `@"bday-day"` |
| `UITextContentTypeBirthdateMonth` | 18.0 | `@"bday-month"` |
| `UITextContentTypeBirthdateYear` | 18.0 | `@"bday-year"` |
| `UITextContentTypeCellularEID` | 18.0 | `@"esim-eid"` |
| `UITextContentTypeCellularIMEI` | 18.0 | `@"esim-imei"` |
| `UITextContentTypeCreditCardExpiration` | 18.0 | `@"cc-exp"` |
| `UITextContentTypeCreditCardExpirationMonth` | 18.0 | `@"cc-exp-month"` |
| `UITextContentTypeCreditCardExpirationYear` | 18.0 | `@"cc-exp-year"` |
| `UITextContentTypeCreditCardFamilyName` | 18.0 | `@"cc-family-name"` |
| `UITextContentTypeCreditCardGivenName` | 18.0 | `@"cc-given-name"` |
| `UITextContentTypeCreditCardMiddleName` | 18.0 | `@"cc-additional-name"` |
| `UITextContentTypeCreditCardName` | 18.0 | `@"cc-name"` |
| `UITextContentTypeCreditCardSecurityCode` | 18.0 | `@"cc-csc"` |
| `UITextContentTypeCreditCardType` | 18.0 | `@"cc-type"` |
| `UITextFormattingViewControllerDecreaseFontSizeChangeType` | 18.0 | `@"UITextFormattingViewControllerDecreaseFontSizeChange"` |
| `UITextFormattingViewControllerDecreaseIndentationChangeType` | 18.0 | `@"UITextFormattingViewControllerDecreaseIndentationChange"` |
| `UITextFormattingViewControllerFontAttributesComponentKey` | 18.0 | `@"UITextFormattingViewControllerFontAttributesComponent"` |
| `UITextFormattingViewControllerFontChangeType` | 18.0 | `@"UITextFormattingViewControllerFontChange"` |
| `UITextFormattingViewControllerFontPickerComponentKey` | 18.0 | `@"UITextFormattingViewControllerFontPickerComponent"` |
| `UITextFormattingViewControllerFontPointSizeComponentKey` | 18.0 | `@"UITextFormattingViewControllerFontPointSizeComponent"` |
| `UITextFormattingViewControllerFontSizeChangeType` | 18.0 | `@"UITextFormattingViewControllerFontSizeChange"` |
| `UITextFormattingViewControllerFontSizeComponentKey` | 18.0 | `@"UITextFormattingViewControllerFontSizeComponent"` |
| `UITextFormattingViewControllerFormattingStyleChangeType` | 18.0 | `@"UITextFormattingViewControllerFormattingStyleChange"` |
| `UITextFormattingViewControllerFormattingStylesComponentKey` | 18.0 | `@"UITextFormattingViewControllerFormattingStylesComponent"` |
| `UITextFormattingViewControllerHighlightBlue` | 18.0 | `@"UITextFormattingViewControllerHighlightBlue"` |
| `UITextFormattingViewControllerHighlightChangeType` | 18.0 | `@"UITextFormattingViewControllerHighlightChange"` |
| `UITextFormattingViewControllerHighlightComponentKey` | 18.0 | `@"UITextFormattingViewControllerHighlightComponent"` |
| `UITextFormattingViewControllerHighlightDefault` | 18.0 | `@"UITextFormattingViewControllerHighlightDefault"` |
| `UITextFormattingViewControllerHighlightMint` | 18.0 | `@"UITextFormattingViewControllerHighlightMint"` |
| `UITextFormattingViewControllerHighlightOrange` | 18.0 | `@"UITextFormattingViewControllerHighlightOrange"` |
| `UITextFormattingViewControllerHighlightPickerComponentKey` | 18.0 | `@"UITextFormattingViewControllerHighlightPickerComponent"` |
| `UITextFormattingViewControllerHighlightPink` | 18.0 | `@"UITextFormattingViewControllerHighlightPink"` |
| `UITextFormattingViewControllerHighlightPurple` | 18.0 | `@"UITextFormattingViewControllerHighlightPurple"` |
| `UITextFormattingViewControllerIncreaseFontSizeChangeType` | 18.0 | `@"UITextFormattingViewControllerIncreaseFontSizeChange"` |
| `UITextFormattingViewControllerIncreaseIndentationChangeType` | 18.0 | `@"UITextFormattingViewControllerIncreaseIndentationChange"` |
| `UITextFormattingViewControllerLineHeightComponentKey` | 18.0 | `@"UITextFormattingViewControllerLineHeightComponent"` |
| `UITextFormattingViewControllerLineHeightPointSizeChangeType` | 18.0 | `@"UITextFormattingViewControllerLineHeightPointSizeChange"` |
| `UITextFormattingViewControllerListStylesComponentKey` | 18.0 | `@"UITextFormattingViewControllerListStylesComponent"` |
| `UITextFormattingViewControllerRemoveBoldChangeType` | 18.0 | `@"UITextFormattingViewControllerRemoveBoldChange"` |
| `UITextFormattingViewControllerRemoveItalicChangeType` | 18.0 | `@"UITextFormattingViewControllerRemoveItalicChange"` |
| `UITextFormattingViewControllerRemoveStrikethroughChangeType` | 18.0 | `@"UITextFormattingViewControllerRemoveStrikethroughChange"` |
| `UITextFormattingViewControllerRemoveUnderlineChangeType` | 18.0 | `@"UITextFormattingViewControllerRemoveUnderlineChange"` |
| `UITextFormattingViewControllerSetBoldChangeType` | 18.0 | `@"UITextFormattingViewControllerSetBoldChange"` |
| `UITextFormattingViewControllerSetItalicChangeType` | 18.0 | `@"UITextFormattingViewControllerSetItalicChange"` |
| `UITextFormattingViewControllerSetStrikethroughChangeType` | 18.0 | `@"UITextFormattingViewControllerSetStrikethroughChange"` |
| `UITextFormattingViewControllerSetUnderlineChangeType` | 18.0 | `@"UITextFormattingViewControllerSetUnderlineChange"` |
| `UITextFormattingViewControllerTextAlignmentAndJustificationComponentKey` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentAndJustificationComponent"` |
| `UITextFormattingViewControllerTextAlignmentCenter` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentCenter"` |
| `UITextFormattingViewControllerTextAlignmentChangeType` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentChange"` |
| `UITextFormattingViewControllerTextAlignmentComponentKey` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentComponent"` |
| `UITextFormattingViewControllerTextAlignmentJustified` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentJustified"` |
| `UITextFormattingViewControllerTextAlignmentLeft` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentLeft"` |
| `UITextFormattingViewControllerTextAlignmentNatural` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentNatural"` |
| `UITextFormattingViewControllerTextAlignmentRight` | 18.0 | `@"UITextFormattingViewControllerTextAlignmentRight"` |
| `UITextFormattingViewControllerTextColorChangeType` | 18.0 | `@"UITextFormattingViewControllerTextColorChange"` |
| `UITextFormattingViewControllerTextColorComponentKey` | 18.0 | `@"UITextFormattingViewControllerTextColorComponent"` |
| `UITextFormattingViewControllerTextIndentationComponentKey` | 18.0 | `@"UITextFormattingViewControllerTextIndentationComponent"` |
| `UITextFormattingViewControllerTextListChangeType` | 18.0 | `@"UITextFormattingViewControllerTextListChange"` |
| `UITextFormattingViewControllerTextListDecimal` | 18.0 | `@"UITextFormattingViewControllerTextListDecimal"` |
| `UITextFormattingViewControllerTextListDisc` | 18.0 | `@"UITextFormattingViewControllerTextListDisc"` |
| `UITextFormattingViewControllerTextListHyphen` | 18.0 | `@"UITextFormattingViewControllerTextListHyphen"` |
| `UITextFormattingViewControllerTextListOther` | 18.0 | `@"UITextFormattingViewControllerTextListOther"` |
| `UITextFormattingViewControllerUndefinedChangeType` | 18.0 | `@"UITextFormattingViewControllerUndefinedChange"` |
| `UITextItemTagAttributeName` | 18.0 | `@"UITextItemTagAttribute"` |

## The release each object carries

A band links one object per release and an object carries the API that arrived in
one release: an object that defines a symbol the band already has together with one
it does not is refused at link time (`modules/apple/backports.lua`, `band()`). The
release above is the first *held* release that exports every symbol in the file,
measured symbol by symbol over `~/.charon/dyld`, so the file is kept by every band below that
release and reexported by the release's own from that one on.
