// The four `IntentItem.Builder` rows the corpus ledger carries, measured the way `IntentPerson`'s and
// `IntentItemSection.Builder`'s are: the digester prints a `@resultBuilder` type with no members at
// all, so each member is *referenced* in the framework's spelling, with a closure type that names the
// signature -- which disambiguates the two `buildBlock` overloads without constructing a value.
//
// NOT YET MEASURED: this typechecks against a *built* module, and the one in the store predates the
// `IntentItemSection.Builder` typealias. It is read and written; the typecheck waits for the next
// device compile, which the load has not allowed.
import Foundation
import AppIntents

// The type itself.
_ = IntentItem<String>.Builder.self

// Its four members, each named by its signature.
let empty: () -> [IntentItem<String>] = IntentItem<String>.Builder.buildBlock
let one: (IntentItem<String>) -> [IntentItem<String>] = IntentItem<String>.Builder.buildBlock
let expression: (IntentItem<String>) -> IntentItem<String> = IntentItem<String>.Builder.buildExpression
let array: ([IntentItem<String>]) -> [IntentItem<String>] = IntentItem<String>.Builder.buildArray
print(type(of: empty), type(of: one), type(of: expression), type(of: array))
