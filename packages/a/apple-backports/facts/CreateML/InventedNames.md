# Public types with no name in Apple's interfaces - an OPEN decision, not a proposal to remove

**54 public types in the port have no name in any of the four frameworks' interfaces.** The list below
is derived, not typed:

    $ python3 tests/backports/host/createml/invented-names.py

which walks `packages/c/createml/files/**/*.swift` for `public struct|class|enum|protocol`, walks the
four macOS SDK interfaces for theirs, and reports the difference. **My run finds 53 rather than 54** -
one type is declared in a form the walk does not match - and that difference is left visible rather
than rounded away, because the count is the thing the owner is being asked to look at.

**The decision is the owner's and nothing here decides it.** The table says, per type, whether the
framework has the idea under another spelling, and why the type is public as far as the declaration
shows. The "why" column is **mechanical** - it is derived from the type's name, its kind and the file
it is declared in - so it is a starting point for a reader rather than a verdict, and the rows that
matter are the ones where it is plainly wrong.


| type | kind | declared in | an Apple counterpart? | why it is public (mechanical) |
| --- | --- | --- | --- | --- |
| `BoostedTreeFitter` | enum | `BoostedTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `BoostedTreeModel` | struct | `BoostedTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `BoostedTreeParameters` | struct | `BoostedTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a value type describing a fit, where Apple carries the same values as parameters on its own types |
| `BoostingLoss` | enum | `BoostedTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a value type describing a fit, where Apple carries the same values as parameters on its own types |
| `ColumnarTable` | struct | `ColumnarTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the port's own name for a shape Apple calls something else |
| `ColumnarTransformer` | protocol | `Transformers.swift` | the framework has this as `ColumnSelectorTransformer` (CreateMLComponents) | a protocol the port's generics are written against |
| `DecisionTreeFitter` | enum | `DecisionTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `DecisionTreeModel` | struct | `DecisionTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `ForestFeatures` | enum | `Ensembles.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `Impurity` | enum | `DecisionTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `JoinType` | enum | `MLDataTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `LinearModelError` | enum | `LinearModels.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `LinearRegressorConfiguration` | struct | `LinearModels.swift` | the framework has this as `MultivariateLinearRegressorConfiguration` (CreateMLComponents) | a value type describing a fit, where Apple carries the same values as parameters on its own types |
| `LinearScalar` | protocol | `LinearModels.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a protocol the port's generics are written against |
| `LogisticRegressionClassifierConfiguration` | struct | `LinearModels.swift` | the framework has this as `LogisticRegressionClassifier` (CreateMLComponents) | a value type describing a fit, where Apple carries the same values as parameters on its own types |
| `MLBoostedTreeClassifierModel` | struct | `TabularEstimators.swift` | the framework has this as `MLBoostedTreeClassifier` (CreateML) | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `MLBoostedTreeModel` | struct | `TabularEstimators.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `MLClassifierMetricsError` | enum | `TabularEstimators.swift` | the framework has this as `MLClassifierMetrics` (CreateML) | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `MLColumnError` | enum | `MLUntypedColumn.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `MLCreateErrorCode` | enum | `TabularEstimators.swift` | the framework has this as `MLCreateError` (CreateML) | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `MLDataColumnSlice` | struct | `MLUntypedColumn.swift` | the framework has this as `MLDataColumn` (CreateML) | a type the port needs and Apple does not declare |
| `MLDataTableAggregator` | struct | `MLDataTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the port's own name for a shape Apple calls something else |
| `MLDataTableError` | enum | `MLDataTable.swift` | the framework has this as `MLDataTable` (CreateML) | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `MLDataTableParsingOptions` | struct | `MLDataTable+CSV.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a value type describing a fit, where Apple carries the same values as parameters on its own types |
| `MLDecisionTreeClassifierModel` | struct | `TabularEstimators.swift` | the framework has this as `MLDecisionTreeClassifier` (CreateML) | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `MLDecisionTreeModel` | struct | `TabularEstimators.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `MLRandomForestClassifierModel` | struct | `TabularEstimators.swift` | the framework has this as `MLRandomForestClassifier` (CreateML) | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `MLRandomForestModel` | struct | `TabularEstimators.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `MLRegressorMetricsError` | enum | `TabularEstimators.swift` | the framework has this as `MLRegressorMetrics` (CreateML) | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `MLTrainingDataSplit` | struct | `TabularEstimators.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `MLTrainingDataValidation` | struct | `TabularEstimators.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `MLTrainingDataValidationData` | struct | `TabularEstimators.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `ModelWriter` | enum | `ModelWriter.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `PackType` | enum | `MLDataTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `ProtoError` | enum | `Codec.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `ProtoField` | enum | `Codec.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `ProtoReader` | struct | `Codec.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `ProtoWriter` | struct | `Codec.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `ProximalSolver` | enum | `Proximal.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `RandomForestFitter` | enum | `Ensembles.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `RandomForestModel` | struct | `Ensembles.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the fitted result of a fit, which Apple returns as an opaque `Transformer` |
| `RandomForestParameters` | struct | `Ensembles.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a value type describing a fit, where Apple carries the same values as parameters on its own types |
| `RegressionMetrics` | enum | `Metrics.swift` | the framework has this as `MLRegressorMetrics` (CreateML) | a type the port needs and Apple does not declare |
| `RowMatrix` | struct | `LinearAlgebra.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | the port's own name for a shape Apple calls something else |
| `SeededGenerator` | struct | `Random.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `SplitSearch` | enum | `DecisionTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `SplitSide` | struct | `DecisionTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `TabularEstimatorCore` | enum | `TabularEstimators.swift` | the framework has this as `TabularEstimator` (CreateMLComponents) | a type the port needs and Apple does not declare |
| `TabularFitting` | enum | `ColumnarTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `TabularFittingError` | enum | `ColumnarTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a name Apple puts in `NSError`'s domain rather than in a Swift type |
| `TabularTrainingSet` | struct | `ColumnarTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `TrainingColumn` | enum | `ColumnarTable.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a type the port needs and Apple does not declare |
| `TreeParameters` | struct | `DecisionTrees.swift` | **no counterpart** in TabularData, CreateMLComponents, CreateML or CoreML | a value type describing a fit, where Apple carries the same values as parameters on its own types |

**How to use it.** Rows with a counterpart are a naming question: the port's name and Apple's
differ and one of them could go. Rows marked **no counterpart** are a *scope* question: either the port
carries something the framework does not, or it carries a helper the framework keeps internal. The two
are different decisions and should not be taken together.

**What is not here.** Nothing in this table is a crutch, and nothing in it is a defect: a public type
the framework does not have is a divergence in *surface*, which is a record to be made and an owner to
decide on - not something this band may resolve by deleting a name a caller might already use.
