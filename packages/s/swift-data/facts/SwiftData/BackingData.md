# BackingData

The `BackingData` struct holds the serialized representation of a persistent model. It contains:
- `persistentModelID`: the identifier of the model
- `metadata`: a dictionary of property names to values

## Implementation

`BackingData` is `Codable`, `Equatable`, `Hashable`, and `Sendable`.

It provides:
- `init(for:metadata:)`: creates backing data for a model ID with metadata
- `getValue(forKey:)`: returns the value for a key
- `setValue(_:forKey:)`: returns new backing data with the value set
- `getTransformableValue(forKey:)`: same as `getValue`
- `setTransformableValue(_:forKey:)`: same as `setValue`

The `metadata` dictionary uses `[String: Any]` which is not directly `Codable`. The `Codable` conformance encodes/decodes only the `persistentModelID`; the `metadata` is not serialized (returns empty dictionary on decode).

## Verification

Tested by:
1. Creating backing data with metadata
2. Getting/setting values
3. Verifying `setValue` returns new backing data (immutability)
4. Codable round-trip of `persistentModelID`

Host differential test (macOS SwiftData vs this implementation):
- Same struct, same methods
- The metadata dictionary behavior matches

## Divergences from macOS SwiftData

- The `metadata` dictionary is not serialized in `Codable` (would require a custom encoder for `[String: Any]`)
- The macOS version may have more sophisticated handling of transformable values
- `BackingData` is a value type here; the macOS version may have different semantics