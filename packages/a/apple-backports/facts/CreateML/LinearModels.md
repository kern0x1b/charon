# The linear regressor and the logistic classifier

## What they are

`LinearRegressor<Scalar>`, `LogisticRegressionClassifier<Scalar, Label>`, and the two models they
produce. Both take a `MLShapedArray<Scalar>` — a shape, strides in elements, and the scalars — and
both are the **ridge** fit of `LinearAlgebra.swift`: a Gram matrix by the release's own
`cblas_dsyrk`, a Cholesky factor by the release's own `dpotrf_`, and the two triangular
substitutions in between. The feature matrix is row-major with strides `[columns, 1]`, which is the
order a fitted model's weights are already in, so a prediction is a dot product over the buffer the
fit produced and nothing is copied on the way out.

## What is not carried, and why it is not carried quietly

**The L1 penalty is refused, not ignored.** `LinearRegressor.Configuration` and
`LogisticRegressionClassifierConfiguration` both carry `l1Penalty`, and this port reads it and
**throws** `LinearModelError.l1PenaltyNotImplemented` when it is non-zero. A fit that quietly dropped
it would hand back a confident number about a model the caller did not ask for, and a caller who set
`l1Penalty: 0.5` would have no way to tell. The L1 objective has no closed form: it needs a
proximal step or a path following the L2 solution, and that is a body of its own. The L2 penalty is
the one that is fitted.

**The iteration schedule is read and not used.** `maximumIterations`, `stepSize` and
`convergenceThreshold` are carried as configuration, because the surface names them and a caller sets
them. This port solves the normal equations directly rather than descending, so for a design that is
not rank-deficient and a penalty that makes it definite, the direct solve returns the minimum the
iterative scheme converges *to* — the same answer, without the loop. The parameters are kept so a
caller's code compiles and its configuration round-trips; they do not change the fit. That is a real
difference from the host and is named here rather than left to be found by a caller who expects ten
iterations of a gradient descent.

**`optimizationStrategy`** (`.normal`, `.conjugateGradient`, `.batchGradientDescent`, `.lbfgs`) is
carried as a value and the four do not behave differently, because they are four *routes* to the same
minimum and this port takes one of them. A caller selecting `.lbfgs` gets the direct solve, which is
the minimum `.lbfgs` would reach. A caller selecting a strategy for its *iteration count* rather than
its answer gets the same answer with fewer iterations.

**The intercept is penalised.** The penalty goes on the whole diagonal, intercept included. That is
the simpler reading of "an L2 penalty on the fit" and the normal matrix is one matrix, so exempting
the intercept would be a special case nothing asked for. The consequence is that the closed form for
a single feature is the two-parameter ridge, not `x'x/(x'x+p)`; the test checks the property a caller
relies on — a penalty shrinks the slope, and a bigger one shrinks it further — rather than a formula
that assumes a free intercept.

## The classifier's layout, and the one bug the test found

`coefficients` is **class-major over features**: one intercept per class first, then class 0's weight
for every feature, then class 1's, and so on. A two-class model over one feature has three numbers
in it, and `featureCount` is therefore `(coefficients.count - 1) / classes`, not `count - 1` — which
was the first version and which called a one-feature model a two-feature one and refused every
prediction of it.

The design matrix carries an intercept column of ones in front, exactly as the regressor's does. It
did not at first, and the solution came back one entry shorter than the reads of it, so a prediction
read past the end of the vector: an out-of-bounds trap in a fit, found by a test that builds a
two-class model and predicts with it.

## `MLShapedArray`'s strides, and the bug the test found

The strides are in **elements**, and the outermost dimension's stride is the product of the ones
inside it. The first implementation walked the dimensions with
`stride(from: shape.count - 1, to: 0, by: -1)`, and that range **stops before it reaches zero**, so
the outermost dimension's stride was never written: every two-dimensional array came out with
strides `[1, 1]`, and a row read was the wrong element. The test builds a 2x3 array and reads
`[1, 2]`, and the number it got back was `4.0` where `6.0` is the element. A one-dimensional array
was unaffected, which is why it took an array with two dimensions to find.

## What the test is, and what it is not

`tests/backports/host/createml/linearmodels/` holds these models against the **closed form**: a table
made from the line `y = 3 + 2*x1 - 1.5*x2` has to fit back to `[3, 2, -1.5]`, and a model built from
those coefficients has to reproduce the table. That is a stronger claim than "agrees with another
implementation of the same thing", because it cannot be satisfied by two wrong implementations
agreeing — and the two bugs above would both have passed such a comparison, since a wrong stride and
a wrong feature count are self-consistent within one process.

**It is not a host differential.** The host's own `LinearRegressor.fitted(to:validateOn:)` is
`async throws` over a `DataFrame`, and the two `fitted(to:)` overloads — one over feature vectors and
one over `AnnotatedFeature` — are distinguished by an argument type the two overlays spell
differently, so bridging it is its own work. `differential.swift` carries the twelve defects this
surface's differential found; this file is a different claim, from the same tree, and says so at the
top.

`AnnotatedFeature` and `AnnotatedPrediction` are here because the two `fitted` overloads are told
apart by their argument type and a tuple is not one: with a tuple the compiler resolves the closure
before it knows which overload is meant, and picks the wrong one.
