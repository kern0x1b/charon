# Schema

The `Schema` type is the declarative model description for SwiftData. It holds:
- `entities`: the array of `Entity` describing each persistent model
- `version`: a `Version` struct with major/minor/patch components
- `encodingVersion`: an integer for the encoding format version

## Implementation

The schema is serializable to JSON (`Codable`) and can be saved to/loaded from a URL. The `init(_ types: [any PersistentModel.Type])` initializer builds the schema from an array of model types, extracting each type's `entityName` and its properties via the `@Model` macro's generated conformance to `PersistentModel`.

The `Schema` has a `managedObjectModel` computed property that constructs an `NSManagedObjectModel` by:
1. Creating an `NSEntityDescription` for each entity
2. Adding `NSAttributeDescription` for each attribute (mapping Swift types to Core Data attribute types)
3. Adding `NSRelationshipDescription` for each relationship (with destination entity, cardinality, and delete rule)
4. Setting the entity's properties and adding it to the model

This `NSManagedObjectModel` is then passed to `NSPersistentContainer` when creating the `ModelContainer`.

## Nested Types

### Version
Three-component version (`major`, `minor`, `patch`) with `Comparable` conformance. Encoded as a dotted string "major.minor.patch".

### Entity
Holds the full entity description:
- `name`: the entity name (from the model type's `entityName`)
- `superentityName`: nil in this implementation
- `properties`: array of `Property` (attributes + relationships)
- `relationships`: filtered from properties
- `attributes`: filtered from properties
- `indices`: array of `Index` (carried but not yet mapped to Core Data)
- `uniquenessConstraints`: array of string arrays (carried, mapped to `NSEntityDescription.uniquenessConstraints`)
- `inheritedProperties`: empty in this implementation
- `subentities`: empty in this implementation

### Property (protocol)
Abstract base for attributes and relationships. Carries `name`, `originalName`, `isOptional`, `isTransient`, `isAttribute`, `isRelationship`, `isUnique`.

### Attribute
Maps to `NSAttributeDescription`. The `valueType` string determines the `NSAttributeType`:
- String → stringAttributeType
- Int/Int64/Int32/Int16 → integer64AttributeType
- Double/Float → doubleAttributeType
- Bool → booleanAttributeType
- Date → dateAttributeType
- Data → binaryDataAttributeType
- UUID → UUIDAttributeType
- Decimal → decimalAttributeType

Options (`.unique`, `.spotlight`, `.preserveValueOnDeletion`, `.externalStorage`, `.ephemeral`, `.allowsCloudEncryption`, `.transformable`) are carried; only `.unique` has a direct Core Data mapping.

### Relationship
Maps to `NSRelationshipDescription`. Carries `destination` (entity name), `inverseName`, `inverseKeyPath`, `minimumModelCount`, `maximumModelCount`, `deleteRule`, `keypath`. The `deleteRule` maps to `NSDeleteRule` (nullify, cascade, deny, noAction).

### CompositeAttribute
Carried as a structure with child `properties` but not yet mapped to Core Data.

### Index
Carried with `name`, `originalName`, `isUnique`, `indices` (property names) but not yet creating a Core Data index.

### Unique
Carried with `constraints` (array of property name arrays) and mapped to `NSEntityDescription.uniquenessConstraints`.

### PropertyMetadata
Carried but not used in the Core Data mapping.

## Verification

Tested by:
1. Creating a schema from model types
2. Round-tripping through `save(to:)` and `load(from:)`
3. Building the `NSManagedObjectModel` and verifying entity/attribute/relationship counts match
4. Using the model in a `ModelContainer` and verifying the container loads stores correctly

## Divergences from macOS SwiftData

- `CompositeAttribute` is carried but not mapped to a Core Data composite property (Core Data has no direct equivalent)
- `Index` is carried but not used to create `NSFetchIndexDescription` (iOS 6 Core Data has no fetch indexes)
- `Schema.Index.Types` only carries the enum cases; no rtree/binary index creation
- The `@Model` macro is not in this package; conformance to `PersistentModel` must be provided by the macro or manually