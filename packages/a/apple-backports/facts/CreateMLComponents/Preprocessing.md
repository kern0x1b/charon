# The preprocessing wrappers

## What a pipeline is, and the one thing it adds

A pipeline is not a new algorithm. `PreprocessingEstimator(scaler, forest)` **is** a scaler and a
forest. What it adds is one thing: the fitted preprocessor travels **with** the fitted model, so a
prediction goes through the very scaler the fit used. Without that, a caller who standardises by the
training mean and predicts on new data has to remember to standardise again, and the first time
someone forgets it the model's numbers are wrong and nothing reports it.

So the type is a pair plus a composition, the fit is two fits, and `fitted(on:)` is the convenience
that runs both — because a caller who wants to look at the intermediate has `preprocessed(from:)`.

## The one semantic that is genuinely different: a supervised pipeline's target

**The preprocessor is fitted over the features only, and the target column is put back untouched.**

Scaling a target is a different model and not this one. A tree's thresholds and a logistic
regression's coefficients are both in the *target's own units*; a target that was standardised and not
put back is a column the caller never wrote, and every coefficient then reads in units of the
target's standard deviation rather than of the target. The first version transformed the whole table,
and the test caught it: the estimator's mean came back `0.0` where the table's mean is 17. **The
arithmetic was right and the column was the wrong one.** The test now checks both halves — the features
standardised, and the mean 17 in the target's own units.

## And the one that is the whole of `Updatable`

An update preprocessed the input **by the preprocessor the fit produced** and moved the inner
estimator, and did **not** refit the preprocessor. Refitting it would change the features the
estimator was fitted on, which is a different model rather than an update.

The test compares the preprocessor's statistics **before and after** an update, byte for byte,
because "did not throw" would not catch a refit. `makeTransformer()` is the **unfitted** pipeline and
its preprocessor has no statistics yet — pinned too, because a wrapper that fitted the preprocessor
there would be a pipeline whose features move under the very first update.

## The four names, and what `Updatable` changes

`Preprocessing{Estimator, SupervisedEstimator, UpdatableEstimator, UpdatableSupervisedEstimator}` is
the same shape over four axes, differing only in which estimator protocol the inner one answers to and
whether it can be updated.

The framework also has `PreprocessingTabularEstimator` and
`PreprocessingUpdatableTabularEstimator`; **those are absent here** and are next, because the tabular
protocols are written over `DataFrame` and the `DataFrame` work is not done. Declaring them over
`ColumnarTable` under the framework's names would be a row saying something the type does not do.

## The estimator protocols, and what is deliberately not in them

`TabularEstimator`, `Estimator`, `SupervisedEstimator`, `UpdatableEstimator` and
`UpdatableSupervisedEstimator`, over `ColumnarTable` and `RowMatrix` — the table and the design
matrix this package has. The framework writes them over `DataFrame`; the shape is the same.

`TemporalSequence`, `TabularSequence` and the shaped-array `Input`/`Output` associated types are
**not** here: they need the `DataFrame` and `MLShapedArray` work that is next, and a protocol naming a
type this package does not have would be a declaration nothing can conform to — which is the thing a
row is not allowed to be.

`SupervisedEstimator` here does **not** refine `Estimator`. The framework's does, and refining here
would force every supervised type to answer an unsupervised fit as well, which no type in this package
does.

## The two shapes this compiler made me change, and why each is recorded

- **`preprocessed(from:)` answers the table, not a pair of `(preprocessor, table)`.** An unlabelled
  two-tuple return is a shape this compiler handles badly, and a named method says more anyway: the
  fitted preprocessor is `Transformer.preprocessor`.
- **The pipeline's generic parameter is `Base`, not `Estimator`.** The parameter and the protocol have
  the same name, so `Estimator: Estimator` resolves the constraint to the parameter and the type is
  rejected as *"constrained to non-protocol, non-class type"*. The framework's own declarations have
  the same pair; a caller cannot see the difference and a reader diffing this against the header can.

## What the test is

`tests/backports/host/createml/preprocessing/` — **17 checks, 0 failures.** A pipeline adds no
arithmetic, so the checks are about the two things it does change: the preprocessor's statistics
travel with the model and its arithmetic is the port's own scaler's, which the transformers suite
already holds to the closed form; and an update moves the inner estimator and leaves the
preprocessor's statistics as the fit left them.

Two estimators the test supplies, because a pipeline needs something to wrap: a mean-of-the-target one,
and a counter that records whether the column it read was the preprocessed one — which is how a caller
can see that the pipeline fed the estimator what it meant to.
