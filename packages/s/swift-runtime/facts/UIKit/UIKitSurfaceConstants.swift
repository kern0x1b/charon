// The UIKit types and cases of the SDK 26.2 Swift surface that the port's UIKit overlay does
// not carry, from the surface's own checklist (`coordination/corpus/ledger/UIKit.tsv`).
//
// Two shapes, and which one a type takes is not a judgement: it is what the typecheck says. Where
// the lifted headers declare the enclosing Objective-C class, the overlay carries a namespace type
// of its own and a `typealias` on the class, so `UIButton.Configuration.CornerStyle.capsule`
// resolves as the SDK's own overlay makes it resolve. Where the headers declare no such class at
// all - the enumeration is native Swift in UIKitCore and has no Objective-C spelling - the
// namespace is declared outright.
//
// The case names and their payloads are the SDK's own, read from
// `UIKit.framework/Modules/UIKit.swiftmodule/arm64e-apple-ios.swiftinterface`. Only the cases this
// checklist names are declared: a type's `==`, its `hash(into:)`, its `init(rawValue:)` and the
// types its payloads point at are other rows of the surface.

import CoreGraphics
import Foundation
import UIKit

public enum CharonUIButton {
    public enum Configuration {
        public enum CornerStyle {
            case capsule
            case dynamic
            case fixed
            case large
            case medium
            case small
        }
        public enum Indicator {
            case automatic
            case none
            case popup
        }
        public enum MacIdiomStyle {
            case automatic
            case bordered
            case borderless
            case borderlessTinted
        }
        public enum Size {
            case large
            case medium
            case mini
            case small
        }
        public enum TitleAlignment {
            case automatic
            case center
            case leading
            case trailing
        }
    }
}

public enum CharonUICellAccessory {
    public enum AccessoryType {
        case checkmark
        case customView(CharonUIView)
        case delete
        case detail
        case disclosureIndicator
        case insert
        case label
        case multiselect
        case outlineDisclosure
        case popUpMenu
        case reorder
    }
    public enum DisplayedState {
        case always
        case whenEditing
        case whenNotEditing
    }
    public enum LayoutDimension {
        case actual
        case custom(CGFloat)
        case standard
    }
    public enum OutlineDisclosureOptions {
        public enum Style {
            case automatic
            case cell
            case header
        }
    }
    public enum Placement {
        case leading(displayed: CharonUICellAccessory.DisplayedState = .always, at: CharonUICellAccessory.Placement.Position = { $0.count })
        case trailing(displayed: CharonUICellAccessory.DisplayedState = .always, at: CharonUICellAccessory.Placement.Position = { _ in 0 })
    }
}

public enum CharonUICellConfigurationState {
    public enum DragState {
        case dragging
        case lifting
        case none
    }
    public enum DropState {
        case none
        case notTargeted
        case targeted
    }
}

public enum CharonUICollectionLayoutListConfiguration {
    public enum Appearance {
        case grouped
        case insetGrouped
        case plain
        case sidebar
        case sidebarPlain
    }
    public enum FooterMode {
        case none
        case supplementary
    }
    public enum HeaderMode {
        case firstItemInSection
        case none
        case supplementary
    }
}

@available(iOS 17.0, *)
public enum CharonUIContentUnavailableConfiguration {
    public enum Alignment {
        case center
        case natural
    }
}

public enum CharonUIListContentConfiguration {
    public enum TextProperties {
        public enum TextAlignment {
            case center
            case justified
            case natural
        }
        public enum TextTransform {
            case capitalized
            case lowercase
            case none
            case uppercase
        }
    }
}

public enum CharonUIListSeparatorConfiguration {
    public enum Visibility {
        case automatic
        case hidden
        case visible
    }
}

public enum CharonUIPointerEffect {
    case automatic(_: UITargetedPreview)
    case highlight(_: UITargetedPreview)
    case hover(_: UITargetedPreview, preferredTintMode: CharonUIPointerEffect.TintMode = .overlay, prefersShadow: Bool = false, prefersScaledContent: Bool = true)
    case lift(_: UITargetedPreview)
    public enum TintMode {
        case none
        case overlay
        case underlay
    }
}

public enum CharonUIPointerShape {
    case horizontalBeam(length: CGFloat)
    case path(_: UIBezierPath)
    case roundedRect(_: CGRect, radius: CGFloat = CharonUIPointerShape.defaultCornerRadius)
    case verticalBeam(length: CGFloat)
}

public enum CharonUITabBarController {
    public enum Sidebar {
        public enum ScrollTarget {
            case footer
            case header
            case tab(UITab)
        }
    }
}

@available(iOS 18.0, *)
public enum CharonUITabSidebarItem {
    public enum Content {
        case action(UIAction)
        case tab(UITab)
    }
}

public enum CharonUITextFormattingViewController {
    public enum ChangeValue {
        case bold(Bool)
        case decreaseFontSize
        case decreaseIndentation
        case font(UIFont)
        case fontSize(Double)
        case formattingStyle(String)
        case highlight(CharonUITextFormattingViewController.Highlight)
        case increaseFontSize
        case increaseIndentation
        case italic(Bool)
        case lineHeightPointSize(Double)
        case strikethrough(Bool)
        case textAlignment(CharonUITextFormattingViewController.TextAlignment)
        case textColor(UIColor)
        case textList(CharonUITextFormattingViewController.TextList)
        case undefined
        case underline(Bool)
    }
}

@available(iOS 17.0, *)
public enum CharonUITextItem {
    public enum Content {
        case link(URL)
        case tag(String)
        case textAttachment(NSTextAttachment)
    }
    public enum MenuConfiguration {
        public enum Preview {
            case `default`
            case view(CharonUIView)
        }
    }
}

public enum CharonUIView {
    public enum LayoutRegion {
        public enum AdaptivityAxis {
            case horizontal
            case vertical
        }
    }
}


extension UIButton {
    public typealias Configuration = CharonUIButton.Configuration
}
extension CharonUIButton.Configuration {
    public typealias CornerStyle = CharonUIButton.Configuration.CornerStyle
}
extension CharonUIButton.Configuration {
    public typealias Indicator = CharonUIButton.Configuration.Indicator
}
extension CharonUIButton.Configuration {
    public typealias MacIdiomStyle = CharonUIButton.Configuration.MacIdiomStyle
}
extension CharonUIButton.Configuration {
    public typealias Size = CharonUIButton.Configuration.Size
}
extension CharonUIButton.Configuration {
    public typealias TitleAlignment = CharonUIButton.Configuration.TitleAlignment
}
extension UITabBarController {
    public typealias Sidebar = CharonUITabBarController.Sidebar
}
extension CharonUITabBarController.Sidebar {
    public typealias ScrollTarget = CharonUITabBarController.Sidebar.ScrollTarget
}
@available(iOS 18.0, *)
extension UITabSidebarItem {
    public typealias Content = CharonUITabSidebarItem.Content
}
extension UITextFormattingViewController {
    public typealias ChangeValue = CharonUITextFormattingViewController.ChangeValue
}
@available(iOS 17.0, *)
extension UITextItem {
    public typealias Content = CharonUITextItem.Content
}
@available(iOS 17.0, *)
extension UITextItem {
    public typealias MenuConfiguration = CharonUITextItem.MenuConfiguration
}
extension CharonUITextItem.MenuConfiguration {
    public typealias Preview = CharonUITextItem.MenuConfiguration.Preview
}
extension UIView {
    public typealias LayoutRegion = CharonUIView.LayoutRegion
}
extension CharonUIView.LayoutRegion {
    public typealias AdaptivityAxis = CharonUIView.LayoutRegion.AdaptivityAxis
}
