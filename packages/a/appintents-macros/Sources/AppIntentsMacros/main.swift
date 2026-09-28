// AppIntentsMacros: the plugin that expands the macros Apple's own AppIntentsMacros expands, built
// for the host against the toolchain's own swift-syntax (SwiftSyntax, SwiftSyntaxBuilder,
// SwiftSyntaxMacros, SwiftCompilerPluginMessageHandling) so no copy of it is vendored here.
//
// The contract each macro implements is the framework's own @attached declaration, printed in
// `arm64e-apple-macos.swiftinterface`:
//
//   @attached(peer, names: prefixed($), prefixed(_))
//   @attached(accessor, names: named(get), named(set))
//   public macro ComputedProperty() = #externalMacro(module: "AppIntentsMacros",
//                                                    type: "EntityPropertyMacro")
//
// Every expected expansion is in tests/Expansions.swift, hand-checked against that declaration.
// Apple's own plugin is not on this machine to diff against -- the toolchain ships only
// libObservationMacros and libSwiftMacros -- so the reference is the interface, and
// packages/a/appintents/facts/AppIntents/Macros.md says so.

import SwiftCompilerPluginMessageHandling
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// What `#ComputedProperty()`'s two roles are given: the property's name and its type, read from
/// the declaration the attribute is on. Anything but a named property is refused rather than
/// guessed at, so a misuse is an error at the use and not a wrong expansion.
private func namedProperty(_ declaration: some DeclSyntaxProtocol, _ role: String) throws
    -> (name: String, type: String) {
    guard let property = declaration.as(VariableDeclSyntax.self),
          let binding = property.bindings.first,
          let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmed
    else {
        throw MacroExpansionErrorMessage("#ComputedProperty's \(role) is only on a property with a name")
    }
    let type = binding.typeAnnotation?.type.trimmedDescription ?? "Any"
    return (name.text, type)
}

/// The peer of `#ComputedProperty()`: the storage the accessors read and write, and the `$`
/// projection the framework's own declaration names alongside it. The storage takes the property's
/// own initialiser when it wrote one, and is an implicitly-unwrapped optional when it did not, so a
/// property the framework has not given a value for reads as none instead of trapping.
public struct ComputedPropertyPeerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let property = try namedProperty(declaration, "peer")
        let storage = "_" + property.name
        let projection = "$" + property.name
        let accessor = bindingAccessor(declaration)

        return [
            """
            private var \(raw: storage): \(raw: property.type)\(raw: accessor)
            """,
            """
            var \(raw: projection): \(raw: property.type) {
                get { return \(raw: storage) }
                set { \(raw: storage) = newValue }
            }
            """,
        ]
    }
}

/// The accessors of `#ComputedProperty()`: `get` and `set`, and nothing else, which is what the
/// framework's declaration names. Both go through the storage the peer role added.
public struct ComputedPropertyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let property = try namedProperty(declaration, "accessor")
        let storage = "_" + property.name
        return [
            "get { return \(raw: storage) }",
            "set { \(raw: storage) = newValue }",
        ]
    }
}

/// The initialiser a property wrote, as it is written, so the storage it is copied to has the same
/// starting value. Nothing is invented when the property had none.
private func bindingAccessor(_ declaration: some DeclSyntaxProtocol) -> String {
    guard let binding = declaration.as(VariableDeclSyntax.self)?.bindings.first,
          let value = binding.initializer?.value else { return "?" }
    return " = \(value.trimmedDescription)"
}

// The entry point is NOT here yet, and the reason is measured, not guessed: this toolchain's
// `SwiftSyntaxMacros` exports the macro protocols (AccessorMacro, PeerMacro, MemberAttributeMacro,
// MemberMacro, ExtensionMacro, FreestandingMacro, Macro) and *not* `CompilerPlugin`, and
// `SwiftCompilerPluginMessageHandling`'s public interface declares nothing at all -- its
// CompilerPluginMessageListener is behind @_spi(PluginMessage). So a `-load-plugin-executable` cannot
// be written against the 6.4 module set alone; it needs swift-syntax as a package, which is the
// route the coordinator named. What compiles today is every macro role below.
let providingMacros: [any Macro.Type] = [
    ComputedPropertyPeerMacro.self,
    ComputedPropertyMacro.self,
]
