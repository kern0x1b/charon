# What each macro expands to

The framework's macros attach a conformance to the type they are written on. A port on these releases
writes that conformance out, because the plugin that expands them (`AppIntentsMacros`, a swift-syntax
executable the framework builds) is not on the release and has no interface in the 26.2 SDK either.

| the macro | what it attaches |
| --- | --- |
| `AppEntity(schema:)` | `AppEntity` and `AssistantSchemaEntity` to the type, with `__assistantSchemaEntity` |
| `AssistantEntity(schema:)` | the same, for an entity the assistant offers on its own |
| `AppIntent(schema:)` | `AppIntent` and `AssistantSchemaIntent` to the type |
| `AssistantIntent(schema:)` | the same, for an intent the assistant offers on its own |
| `AppEnum(schema:)` | `AppEnum` and `AssistantSchemaEnum` to the type |
| `AssistantEnum(schema:)` | the same, for an enum the assistant offers on its own |
| `ComputedProperty(title:)` and the other five spellings | a peer `EntityProperty` the framework computes when it is asked for, under the title and indexing key the macro names |
| `DeferredProperty(title:)` and `DeferredProperty()` | a peer `EntityProperty` the app's entity is asked for only when a caller needs it |
| `UnionValue()` | `_IntentValueRepresentable` to the type, with the value types it stands for |

The conformances the macros attach are in the module as protocols, so a type that writes one out gets
the same requirements the macro would have given it, and the `AssistantSchema*` protocols are the ones
that add `isAssistantOnly`.
