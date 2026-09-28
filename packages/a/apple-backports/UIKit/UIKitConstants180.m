// The UIKit constants first exported by iOS 18.0
// (facts/UIKit/UIKitConstants180.md).
//
// One object carries one release: every symbol here is first exported by the oldest
// held release that has it, so a band from 18.0 on re-exports the release's own and the
// bands below keep this one.
//
// Every value below was read out of a real dyld shared cache, /System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore,
// never from a header and never from a host framework.

#import <UIKit/UIKit.h>

const NSAttributedStringKey NSAdaptiveImageGlyphAttributeName = @"CTAdaptiveImageProvider";
const NSAttributedStringDocumentAttributeKey NSDefaultFontExcludedDocumentAttribute = @"NoDefaultFonts";
const NSAttributedStringKey NSTextHighlightColorSchemeAttributeName = @"NSTextHighlightColorScheme";
// A typedef this SDK may not have: NSTextHighlightColorScheme, NSTextHighlightStyle, UIAccessibilityPriority, UICollectionLayoutSectionOrthogonalScrollingDecelerationRate. Each is spelled with the type the
// typedef stands for on an SDK that has it, and with that type on one that does not, so the
// file compiles against every SDK this package is built with. The floors are the SDK's own
// API_AVAILABLE on each typedef.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
// A typedef this SDK may not have: NSTextHighlightColorScheme, NSTextHighlightStyle, UIAccessibilityPriority, UICollectionLayoutSectionOrthogonalScrollingDecelerationRate, UIDocumentCreationIntent, UITextFormattingViewControllerChangeType, UITextFormattingViewControllerComponentKey, UITextFormattingViewControllerHighlight. Each is spelled with the type the
// typedef stands for on an SDK that has it, and with that type on one that does not, so
// the file compiles against every SDK this package is built with - the 16.4 and the 26.2
// it is built with both. The floors are the SDK's own API_AVAILABLE on each typedef.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
// A typedef this SDK may not have: NSTextHighlightColorScheme, NSTextHighlightStyle, UIAccessibilityPriority, UICollectionLayoutSectionOrthogonalScrollingDecelerationRate, UIDocumentCreationIntent, UITextFormattingViewControllerChangeType, UITextFormattingViewControllerComponentKey, UITextFormattingViewControllerHighlight, UITextFormattingViewControllerTextAlignment, UITextFormattingViewControllerTextList. Each is spelled
// with the type the typedef stands for on an SDK that has it, and with that type on one that
// does not, so the file compiles against every SDK this package is built with - the 16.4 and
// the 26.2. The floors are the SDK's own API_AVAILABLE on each typedef.
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightColorScheme NSTextHighlightColorSchemeBlue = @"NSTextHighlightColorSchemeBlue";
#else
NSString *const NSTextHighlightColorSchemeBlue = @"NSTextHighlightColorSchemeBlue";
#endif
#else
NSString *const NSTextHighlightColorSchemeBlue = @"NSTextHighlightColorSchemeBlue";
#endif
#else
NSString *const NSTextHighlightColorSchemeBlue = @"NSTextHighlightColorSchemeBlue";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightColorScheme NSTextHighlightColorSchemeDefault = @"NSTextHighlightColorSchemeDefault";
#else
NSString *const NSTextHighlightColorSchemeDefault = @"NSTextHighlightColorSchemeDefault";
#endif
#else
NSString *const NSTextHighlightColorSchemeDefault = @"NSTextHighlightColorSchemeDefault";
#endif
#else
NSString *const NSTextHighlightColorSchemeDefault = @"NSTextHighlightColorSchemeDefault";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightColorScheme NSTextHighlightColorSchemeMint = @"NSTextHighlightColorSchemeMint";
#else
NSString *const NSTextHighlightColorSchemeMint = @"NSTextHighlightColorSchemeMint";
#endif
#else
NSString *const NSTextHighlightColorSchemeMint = @"NSTextHighlightColorSchemeMint";
#endif
#else
NSString *const NSTextHighlightColorSchemeMint = @"NSTextHighlightColorSchemeMint";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightColorScheme NSTextHighlightColorSchemeOrange = @"NSTextHighlightColorSchemeOrange";
#else
NSString *const NSTextHighlightColorSchemeOrange = @"NSTextHighlightColorSchemeOrange";
#endif
#else
NSString *const NSTextHighlightColorSchemeOrange = @"NSTextHighlightColorSchemeOrange";
#endif
#else
NSString *const NSTextHighlightColorSchemeOrange = @"NSTextHighlightColorSchemeOrange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightColorScheme NSTextHighlightColorSchemePink = @"NSTextHighlightColorSchemePink";
#else
NSString *const NSTextHighlightColorSchemePink = @"NSTextHighlightColorSchemePink";
#endif
#else
NSString *const NSTextHighlightColorSchemePink = @"NSTextHighlightColorSchemePink";
#endif
#else
NSString *const NSTextHighlightColorSchemePink = @"NSTextHighlightColorSchemePink";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightColorScheme NSTextHighlightColorSchemePurple = @"NSTextHighlightColorSchemePurple";
#else
NSString *const NSTextHighlightColorSchemePurple = @"NSTextHighlightColorSchemePurple";
#endif
#else
NSString *const NSTextHighlightColorSchemePurple = @"NSTextHighlightColorSchemePurple";
#endif
#else
NSString *const NSTextHighlightColorSchemePurple = @"NSTextHighlightColorSchemePurple";
#endif
const NSAttributedStringKey NSTextHighlightStyleAttributeName = @"NSTextHighlightStyle";
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const NSTextHighlightStyle NSTextHighlightStyleDefault = @"NSTextHighlightStyleDefault";
#else
NSString *const NSTextHighlightStyleDefault = @"NSTextHighlightStyleDefault";
#endif
#else
NSString *const NSTextHighlightStyleDefault = @"NSTextHighlightStyleDefault";
#endif
#else
NSString *const NSTextHighlightStyleDefault = @"NSTextHighlightStyleDefault";
#endif
const NSAttributedStringDocumentReadingOptionKey NSTextKit1ListMarkerFormatDocumentOption = @"TextKit1ListMarkerFormat";
NSString *const UIAccessibilityCustomActionCategoryEdit = @"UIAccessibilityCustomActionCategoryEdit";
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
const UIAccessibilityPriority UIAccessibilityPriorityDefault = @"UIAccessibilityPriorityDefault";
#else
NSString *const UIAccessibilityPriorityDefault = @"UIAccessibilityPriorityDefault";
#endif
#else
NSString *const UIAccessibilityPriorityDefault = @"UIAccessibilityPriorityDefault";
#endif
#else
NSString *const UIAccessibilityPriorityDefault = @"UIAccessibilityPriorityDefault";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
const UIAccessibilityPriority UIAccessibilityPriorityHigh = @"UIAccessibilityPriorityHigh";
#else
NSString *const UIAccessibilityPriorityHigh = @"UIAccessibilityPriorityHigh";
#endif
#else
NSString *const UIAccessibilityPriorityHigh = @"UIAccessibilityPriorityHigh";
#endif
#else
NSString *const UIAccessibilityPriorityHigh = @"UIAccessibilityPriorityHigh";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
const UIAccessibilityPriority UIAccessibilityPriorityLow = @"UIAccessibilityPriorityLow";
#else
NSString *const UIAccessibilityPriorityLow = @"UIAccessibilityPriorityLow";
#endif
#else
NSString *const UIAccessibilityPriorityLow = @"UIAccessibilityPriorityLow";
#endif
#else
NSString *const UIAccessibilityPriorityLow = @"UIAccessibilityPriorityLow";
#endif
const NSAttributedStringKey UIAccessibilitySpeechAttributeAnnouncementPriority = @"UIAccessibilitySpeechAttributeAnnouncementPriority";
const UIAccessibilityTraits UIAccessibilityTraitSupportsZoom = 70368744177664;
const UIAccessibilityTraits UIAccessibilityTraitToggleButton = 9007199254740992;
const UIActivityItemsConfigurationInteraction UIActivityItemsConfigurationInteractionCopy = @"copy";
const UIActivityItemsConfigurationMetadataKey UIActivityItemsConfigurationMetadataKeyCollaborationModeRestrictions = @"collaborationModeRestrictions";
const UIActivityItemsConfigurationMetadataKey UIActivityItemsConfigurationMetadataKeyShareRecipients = @"shareRecipients";
const UIActivityType UIActivityTypeAddToHomeScreen = @"com.apple.UIKit.activity.AddToHomeScreen";
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
const UICollectionLayoutSectionOrthogonalScrollingDecelerationRate UICollectionLayoutSectionOrthogonalScrollingDecelerationRateAutomatic = -1.0;
#else
NSString *const UICollectionLayoutSectionOrthogonalScrollingDecelerationRateAutomatic = -1.0;
#endif
#else
NSString *const UICollectionLayoutSectionOrthogonalScrollingDecelerationRateAutomatic = -1.0;
#endif
#else
const CGFloat UICollectionLayoutSectionOrthogonalScrollingDecelerationRateAutomatic = -1.0;
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
const UICollectionLayoutSectionOrthogonalScrollingDecelerationRate UICollectionLayoutSectionOrthogonalScrollingDecelerationRateFast = 0.99;
#else
NSString *const UICollectionLayoutSectionOrthogonalScrollingDecelerationRateFast = 0.99;
#endif
#else
NSString *const UICollectionLayoutSectionOrthogonalScrollingDecelerationRateFast = 0.99;
#endif
#else
const CGFloat UICollectionLayoutSectionOrthogonalScrollingDecelerationRateFast = 0.99;
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000
const UICollectionLayoutSectionOrthogonalScrollingDecelerationRate UICollectionLayoutSectionOrthogonalScrollingDecelerationRateNormal = 0.998;
#else
NSString *const UICollectionLayoutSectionOrthogonalScrollingDecelerationRateNormal = 0.998;
#endif
#else
NSString *const UICollectionLayoutSectionOrthogonalScrollingDecelerationRateNormal = 0.998;
#endif
#else
const CGFloat UICollectionLayoutSectionOrthogonalScrollingDecelerationRateNormal = 0.998;
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UIDocumentCreationIntent UIDocumentCreationIntentDefault = @"UIDocumentCreationIntentDefault";
#else
NSString *const UIDocumentCreationIntentDefault = @"UIDocumentCreationIntentDefault";
#endif
#else
NSString *const UIDocumentCreationIntentDefault = @"UIDocumentCreationIntentDefault";
#endif
const UIFontTextStyle UIFontTextStyleExtraLargeTitle = @"UICTFontTextStyleExtraLargeTitle";
const UIFontTextStyle UIFontTextStyleExtraLargeTitle2 = @"UICTFontTextStyleExtraLargeTitle2";
const UIMenuIdentifier UIMenuAutoFill = @"com.apple.menu.autofill";
const NSNotificationName UISceneSystemProtectionDidChangeNotification = @"UISceneSystemProtectionDidChangeNotification";
const UITextContentType UITextContentTypeBirthdate = @"bday";
const UITextContentType UITextContentTypeBirthdateDay = @"bday-day";
const UITextContentType UITextContentTypeBirthdateMonth = @"bday-month";
const UITextContentType UITextContentTypeBirthdateYear = @"bday-year";
const UITextContentType UITextContentTypeCellularEID = @"esim-eid";
const UITextContentType UITextContentTypeCellularIMEI = @"esim-imei";
const UITextContentType UITextContentTypeCreditCardExpiration = @"cc-exp";
const UITextContentType UITextContentTypeCreditCardExpirationMonth = @"cc-exp-month";
const UITextContentType UITextContentTypeCreditCardExpirationYear = @"cc-exp-year";
const UITextContentType UITextContentTypeCreditCardFamilyName = @"cc-family-name";
const UITextContentType UITextContentTypeCreditCardGivenName = @"cc-given-name";
const UITextContentType UITextContentTypeCreditCardMiddleName = @"cc-additional-name";
const UITextContentType UITextContentTypeCreditCardName = @"cc-name";
const UITextContentType UITextContentTypeCreditCardSecurityCode = @"cc-csc";
const UITextContentType UITextContentTypeCreditCardType = @"cc-type";
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerDecreaseFontSizeChangeType = @"UITextFormattingViewControllerDecreaseFontSizeChange";
#else
NSString *const UITextFormattingViewControllerDecreaseFontSizeChangeType = @"UITextFormattingViewControllerDecreaseFontSizeChange";
#endif
#else
NSString *const UITextFormattingViewControllerDecreaseFontSizeChangeType = @"UITextFormattingViewControllerDecreaseFontSizeChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerDecreaseIndentationChangeType = @"UITextFormattingViewControllerDecreaseIndentationChange";
#else
NSString *const UITextFormattingViewControllerDecreaseIndentationChangeType = @"UITextFormattingViewControllerDecreaseIndentationChange";
#endif
#else
NSString *const UITextFormattingViewControllerDecreaseIndentationChangeType = @"UITextFormattingViewControllerDecreaseIndentationChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerFontAttributesComponentKey = @"UITextFormattingViewControllerFontAttributesComponent";
#else
NSString *const UITextFormattingViewControllerFontAttributesComponentKey = @"UITextFormattingViewControllerFontAttributesComponent";
#endif
#else
NSString *const UITextFormattingViewControllerFontAttributesComponentKey = @"UITextFormattingViewControllerFontAttributesComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerFontChangeType = @"UITextFormattingViewControllerFontChange";
#else
NSString *const UITextFormattingViewControllerFontChangeType = @"UITextFormattingViewControllerFontChange";
#endif
#else
NSString *const UITextFormattingViewControllerFontChangeType = @"UITextFormattingViewControllerFontChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerFontPickerComponentKey = @"UITextFormattingViewControllerFontPickerComponent";
#else
NSString *const UITextFormattingViewControllerFontPickerComponentKey = @"UITextFormattingViewControllerFontPickerComponent";
#endif
#else
NSString *const UITextFormattingViewControllerFontPickerComponentKey = @"UITextFormattingViewControllerFontPickerComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerFontPointSizeComponentKey = @"UITextFormattingViewControllerFontPointSizeComponent";
#else
NSString *const UITextFormattingViewControllerFontPointSizeComponentKey = @"UITextFormattingViewControllerFontPointSizeComponent";
#endif
#else
NSString *const UITextFormattingViewControllerFontPointSizeComponentKey = @"UITextFormattingViewControllerFontPointSizeComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerFontSizeChangeType = @"UITextFormattingViewControllerFontSizeChange";
#else
NSString *const UITextFormattingViewControllerFontSizeChangeType = @"UITextFormattingViewControllerFontSizeChange";
#endif
#else
NSString *const UITextFormattingViewControllerFontSizeChangeType = @"UITextFormattingViewControllerFontSizeChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerFontSizeComponentKey = @"UITextFormattingViewControllerFontSizeComponent";
#else
NSString *const UITextFormattingViewControllerFontSizeComponentKey = @"UITextFormattingViewControllerFontSizeComponent";
#endif
#else
NSString *const UITextFormattingViewControllerFontSizeComponentKey = @"UITextFormattingViewControllerFontSizeComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerFormattingStyleChangeType = @"UITextFormattingViewControllerFormattingStyleChange";
#else
NSString *const UITextFormattingViewControllerFormattingStyleChangeType = @"UITextFormattingViewControllerFormattingStyleChange";
#endif
#else
NSString *const UITextFormattingViewControllerFormattingStyleChangeType = @"UITextFormattingViewControllerFormattingStyleChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerFormattingStylesComponentKey = @"UITextFormattingViewControllerFormattingStylesComponent";
#else
NSString *const UITextFormattingViewControllerFormattingStylesComponentKey = @"UITextFormattingViewControllerFormattingStylesComponent";
#endif
#else
NSString *const UITextFormattingViewControllerFormattingStylesComponentKey = @"UITextFormattingViewControllerFormattingStylesComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerHighlight UITextFormattingViewControllerHighlightBlue = @"UITextFormattingViewControllerHighlightBlue";
#else
NSString *const UITextFormattingViewControllerHighlightBlue = @"UITextFormattingViewControllerHighlightBlue";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightBlue = @"UITextFormattingViewControllerHighlightBlue";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerHighlightChangeType = @"UITextFormattingViewControllerHighlightChange";
#else
NSString *const UITextFormattingViewControllerHighlightChangeType = @"UITextFormattingViewControllerHighlightChange";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightChangeType = @"UITextFormattingViewControllerHighlightChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerHighlightComponentKey = @"UITextFormattingViewControllerHighlightComponent";
#else
NSString *const UITextFormattingViewControllerHighlightComponentKey = @"UITextFormattingViewControllerHighlightComponent";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightComponentKey = @"UITextFormattingViewControllerHighlightComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerHighlight UITextFormattingViewControllerHighlightDefault = @"UITextFormattingViewControllerHighlightDefault";
#else
NSString *const UITextFormattingViewControllerHighlightDefault = @"UITextFormattingViewControllerHighlightDefault";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightDefault = @"UITextFormattingViewControllerHighlightDefault";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerHighlight UITextFormattingViewControllerHighlightMint = @"UITextFormattingViewControllerHighlightMint";
#else
NSString *const UITextFormattingViewControllerHighlightMint = @"UITextFormattingViewControllerHighlightMint";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightMint = @"UITextFormattingViewControllerHighlightMint";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerHighlight UITextFormattingViewControllerHighlightOrange = @"UITextFormattingViewControllerHighlightOrange";
#else
NSString *const UITextFormattingViewControllerHighlightOrange = @"UITextFormattingViewControllerHighlightOrange";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightOrange = @"UITextFormattingViewControllerHighlightOrange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerHighlightPickerComponentKey = @"UITextFormattingViewControllerHighlightPickerComponent";
#else
NSString *const UITextFormattingViewControllerHighlightPickerComponentKey = @"UITextFormattingViewControllerHighlightPickerComponent";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightPickerComponentKey = @"UITextFormattingViewControllerHighlightPickerComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerHighlight UITextFormattingViewControllerHighlightPink = @"UITextFormattingViewControllerHighlightPink";
#else
NSString *const UITextFormattingViewControllerHighlightPink = @"UITextFormattingViewControllerHighlightPink";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightPink = @"UITextFormattingViewControllerHighlightPink";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerHighlight UITextFormattingViewControllerHighlightPurple = @"UITextFormattingViewControllerHighlightPurple";
#else
NSString *const UITextFormattingViewControllerHighlightPurple = @"UITextFormattingViewControllerHighlightPurple";
#endif
#else
NSString *const UITextFormattingViewControllerHighlightPurple = @"UITextFormattingViewControllerHighlightPurple";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerIncreaseFontSizeChangeType = @"UITextFormattingViewControllerIncreaseFontSizeChange";
#else
NSString *const UITextFormattingViewControllerIncreaseFontSizeChangeType = @"UITextFormattingViewControllerIncreaseFontSizeChange";
#endif
#else
NSString *const UITextFormattingViewControllerIncreaseFontSizeChangeType = @"UITextFormattingViewControllerIncreaseFontSizeChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerIncreaseIndentationChangeType = @"UITextFormattingViewControllerIncreaseIndentationChange";
#else
NSString *const UITextFormattingViewControllerIncreaseIndentationChangeType = @"UITextFormattingViewControllerIncreaseIndentationChange";
#endif
#else
NSString *const UITextFormattingViewControllerIncreaseIndentationChangeType = @"UITextFormattingViewControllerIncreaseIndentationChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerLineHeightComponentKey = @"UITextFormattingViewControllerLineHeightComponent";
#else
NSString *const UITextFormattingViewControllerLineHeightComponentKey = @"UITextFormattingViewControllerLineHeightComponent";
#endif
#else
NSString *const UITextFormattingViewControllerLineHeightComponentKey = @"UITextFormattingViewControllerLineHeightComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerLineHeightPointSizeChangeType = @"UITextFormattingViewControllerLineHeightPointSizeChange";
#else
NSString *const UITextFormattingViewControllerLineHeightPointSizeChangeType = @"UITextFormattingViewControllerLineHeightPointSizeChange";
#endif
#else
NSString *const UITextFormattingViewControllerLineHeightPointSizeChangeType = @"UITextFormattingViewControllerLineHeightPointSizeChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerListStylesComponentKey = @"UITextFormattingViewControllerListStylesComponent";
#else
NSString *const UITextFormattingViewControllerListStylesComponentKey = @"UITextFormattingViewControllerListStylesComponent";
#endif
#else
NSString *const UITextFormattingViewControllerListStylesComponentKey = @"UITextFormattingViewControllerListStylesComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerRemoveBoldChangeType = @"UITextFormattingViewControllerRemoveBoldChange";
#else
NSString *const UITextFormattingViewControllerRemoveBoldChangeType = @"UITextFormattingViewControllerRemoveBoldChange";
#endif
#else
NSString *const UITextFormattingViewControllerRemoveBoldChangeType = @"UITextFormattingViewControllerRemoveBoldChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerRemoveItalicChangeType = @"UITextFormattingViewControllerRemoveItalicChange";
#else
NSString *const UITextFormattingViewControllerRemoveItalicChangeType = @"UITextFormattingViewControllerRemoveItalicChange";
#endif
#else
NSString *const UITextFormattingViewControllerRemoveItalicChangeType = @"UITextFormattingViewControllerRemoveItalicChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerRemoveStrikethroughChangeType = @"UITextFormattingViewControllerRemoveStrikethroughChange";
#else
NSString *const UITextFormattingViewControllerRemoveStrikethroughChangeType = @"UITextFormattingViewControllerRemoveStrikethroughChange";
#endif
#else
NSString *const UITextFormattingViewControllerRemoveStrikethroughChangeType = @"UITextFormattingViewControllerRemoveStrikethroughChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerRemoveUnderlineChangeType = @"UITextFormattingViewControllerRemoveUnderlineChange";
#else
NSString *const UITextFormattingViewControllerRemoveUnderlineChangeType = @"UITextFormattingViewControllerRemoveUnderlineChange";
#endif
#else
NSString *const UITextFormattingViewControllerRemoveUnderlineChangeType = @"UITextFormattingViewControllerRemoveUnderlineChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerSetBoldChangeType = @"UITextFormattingViewControllerSetBoldChange";
#else
NSString *const UITextFormattingViewControllerSetBoldChangeType = @"UITextFormattingViewControllerSetBoldChange";
#endif
#else
NSString *const UITextFormattingViewControllerSetBoldChangeType = @"UITextFormattingViewControllerSetBoldChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerSetItalicChangeType = @"UITextFormattingViewControllerSetItalicChange";
#else
NSString *const UITextFormattingViewControllerSetItalicChangeType = @"UITextFormattingViewControllerSetItalicChange";
#endif
#else
NSString *const UITextFormattingViewControllerSetItalicChangeType = @"UITextFormattingViewControllerSetItalicChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerSetStrikethroughChangeType = @"UITextFormattingViewControllerSetStrikethroughChange";
#else
NSString *const UITextFormattingViewControllerSetStrikethroughChangeType = @"UITextFormattingViewControllerSetStrikethroughChange";
#endif
#else
NSString *const UITextFormattingViewControllerSetStrikethroughChangeType = @"UITextFormattingViewControllerSetStrikethroughChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerSetUnderlineChangeType = @"UITextFormattingViewControllerSetUnderlineChange";
#else
NSString *const UITextFormattingViewControllerSetUnderlineChangeType = @"UITextFormattingViewControllerSetUnderlineChange";
#endif
#else
NSString *const UITextFormattingViewControllerSetUnderlineChangeType = @"UITextFormattingViewControllerSetUnderlineChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerTextAlignmentAndJustificationComponentKey = @"UITextFormattingViewControllerTextAlignmentAndJustificationComponent";
#else
NSString *const UITextFormattingViewControllerTextAlignmentAndJustificationComponentKey = @"UITextFormattingViewControllerTextAlignmentAndJustificationComponent";
#endif
#else
NSString *const UITextFormattingViewControllerTextAlignmentAndJustificationComponentKey = @"UITextFormattingViewControllerTextAlignmentAndJustificationComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextAlignment UITextFormattingViewControllerTextAlignmentCenter = @"UITextFormattingViewControllerTextAlignmentCenter";
#else
NSString *const UITextFormattingViewControllerTextAlignmentCenter = @"UITextFormattingViewControllerTextAlignmentCenter";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerTextAlignmentChangeType = @"UITextFormattingViewControllerTextAlignmentChange";
#else
NSString *const UITextFormattingViewControllerTextAlignmentChangeType = @"UITextFormattingViewControllerTextAlignmentChange";
#endif
#else
NSString *const UITextFormattingViewControllerTextAlignmentChangeType = @"UITextFormattingViewControllerTextAlignmentChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerTextAlignmentComponentKey = @"UITextFormattingViewControllerTextAlignmentComponent";
#else
NSString *const UITextFormattingViewControllerTextAlignmentComponentKey = @"UITextFormattingViewControllerTextAlignmentComponent";
#endif
#else
NSString *const UITextFormattingViewControllerTextAlignmentComponentKey = @"UITextFormattingViewControllerTextAlignmentComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextAlignment UITextFormattingViewControllerTextAlignmentJustified = @"UITextFormattingViewControllerTextAlignmentJustified";
#else
NSString *const UITextFormattingViewControllerTextAlignmentJustified = @"UITextFormattingViewControllerTextAlignmentJustified";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextAlignment UITextFormattingViewControllerTextAlignmentLeft = @"UITextFormattingViewControllerTextAlignmentLeft";
#else
NSString *const UITextFormattingViewControllerTextAlignmentLeft = @"UITextFormattingViewControllerTextAlignmentLeft";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextAlignment UITextFormattingViewControllerTextAlignmentNatural = @"UITextFormattingViewControllerTextAlignmentNatural";
#else
NSString *const UITextFormattingViewControllerTextAlignmentNatural = @"UITextFormattingViewControllerTextAlignmentNatural";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextAlignment UITextFormattingViewControllerTextAlignmentRight = @"UITextFormattingViewControllerTextAlignmentRight";
#else
NSString *const UITextFormattingViewControllerTextAlignmentRight = @"UITextFormattingViewControllerTextAlignmentRight";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerTextColorChangeType = @"UITextFormattingViewControllerTextColorChange";
#else
NSString *const UITextFormattingViewControllerTextColorChangeType = @"UITextFormattingViewControllerTextColorChange";
#endif
#else
NSString *const UITextFormattingViewControllerTextColorChangeType = @"UITextFormattingViewControllerTextColorChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerTextColorComponentKey = @"UITextFormattingViewControllerTextColorComponent";
#else
NSString *const UITextFormattingViewControllerTextColorComponentKey = @"UITextFormattingViewControllerTextColorComponent";
#endif
#else
NSString *const UITextFormattingViewControllerTextColorComponentKey = @"UITextFormattingViewControllerTextColorComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerComponentKey UITextFormattingViewControllerTextIndentationComponentKey = @"UITextFormattingViewControllerTextIndentationComponent";
#else
NSString *const UITextFormattingViewControllerTextIndentationComponentKey = @"UITextFormattingViewControllerTextIndentationComponent";
#endif
#else
NSString *const UITextFormattingViewControllerTextIndentationComponentKey = @"UITextFormattingViewControllerTextIndentationComponent";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerTextListChangeType = @"UITextFormattingViewControllerTextListChange";
#else
NSString *const UITextFormattingViewControllerTextListChangeType = @"UITextFormattingViewControllerTextListChange";
#endif
#else
NSString *const UITextFormattingViewControllerTextListChangeType = @"UITextFormattingViewControllerTextListChange";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextList UITextFormattingViewControllerTextListDecimal = @"UITextFormattingViewControllerTextListDecimal";
#else
NSString *const UITextFormattingViewControllerTextListDecimal = @"UITextFormattingViewControllerTextListDecimal";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextList UITextFormattingViewControllerTextListDisc = @"UITextFormattingViewControllerTextListDisc";
#else
NSString *const UITextFormattingViewControllerTextListDisc = @"UITextFormattingViewControllerTextListDisc";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextList UITextFormattingViewControllerTextListHyphen = @"UITextFormattingViewControllerTextListHyphen";
#else
NSString *const UITextFormattingViewControllerTextListHyphen = @"UITextFormattingViewControllerTextListHyphen";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerTextList UITextFormattingViewControllerTextListOther = @"UITextFormattingViewControllerTextListOther";
#else
NSString *const UITextFormattingViewControllerTextListOther = @"UITextFormattingViewControllerTextListOther";
#endif
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 180000
const UITextFormattingViewControllerChangeType UITextFormattingViewControllerUndefinedChangeType = @"UITextFormattingViewControllerUndefinedChange";
#else
NSString *const UITextFormattingViewControllerUndefinedChangeType = @"UITextFormattingViewControllerUndefinedChange";
#endif
#else
NSString *const UITextFormattingViewControllerUndefinedChangeType = @"UITextFormattingViewControllerUndefinedChange";
#endif
const NSAttributedStringKey UITextItemTagAttributeName = @"UITextItemTagAttribute";
