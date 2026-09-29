// The three `IntentItemSection.Builder` rows the corpus ledger carries, measured the way
// `IntentPerson`'s were: a call site in the framework's spelling, typechecked against this module.
// The digester prints a `@resultBuilder` type with no members at all, so a reference is the only
// reading available, and it is enough: it proves the type and each member exist with that name and
// that signature.
import Foundation
import AppIntents

// The type itself.
_ = IntentItemSection<String>.Builder.self

// Its two members the ledger names, each referenced rather than called: a reference to an overload
// is enough to prove the name and the signature, and it needs no value of the type constructed.
let empty: () -> [IntentItemSection<String>] = IntentItemSection<String>.Builder.buildBlock
let variadic: (IntentItemSection<String>...) -> [IntentItemSection<String>] = IntentItemSection<String>.Builder.buildBlock
print(type(of: empty), type(of: variadic))
