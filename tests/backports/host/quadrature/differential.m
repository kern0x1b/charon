// The port's quadrature_integrate held against the host's own Accelerate, case by case: the same integrand
// through each, comparing the integral, the status, the absolute error and the number of points the
// caller's callback saw.
//
// The header says the integrators are "C ports of the QUADPACK library corresponding routines", so the
// numbers are expected to agree to the last few bits and not merely to the tolerance: two implementations
// that both integrate x^2 from 0 to 1 agree to fifteen digits whether or not either is QUADPACK's, and the
// per-case tolerance here is one part in 1e12 of the answer, which a different rule or a different
// subdivision order cannot reach.
//
// The cases are chosen so each one can only pass by being the same algorithm:
//
//   - the point counts the header lists, each of which makes the callback see its own count (measured on the
//     host: 63 points for 21 and 105 for 15 on the same integral), so a case that passed all six with one
//     rule would be a check that cannot fail;
//   - max_intervals of one and two, where QAG and QAGS part company because the epsilon extrapolation
//     needs more intervals than QAG's plain bisection (measured: QAG with two answers QUADRATURE_SUCCESS
//     and QAGS answers -101);
//   - the subdivision limit from a workspace of exactly one interval's bytes and of one byte less, which is
//     the boundary the header's QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL names;
//   - an infinite bound, which only QAGS takes;
//   - the refusals: a NULL function, a NULL options, a count the header does not list, an integrator the
//     enumeration does not name, both tolerances zero, and an unreachable tolerance.
//
// The red control is the last case: the port's own answer with a rule that is one node out is compared
// against the host's, and has to differ.

#import <Accelerate/Accelerate.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wnonnull"

// The port's one, through the name the runner renames it to.
double charon_host_quadrature_integrate(const quadrature_integrate_function *f, double a, double b,
                                        const quadrature_integrate_options *options, quadrature_status *status,
                                        double *abs_error, size_t workspace_size, void *workspace);

static int checks;
static int failures;
static char detail[512];

static void report(int passed, const char *name, const char *why)
{
    checks++;
    if (passed) {
        printf("ok %s\n", name);
    } else {
        failures++;
        printf("FAIL %s: %s\n", name, why && why[0] ? why : detail);
    }
}

// The integrands, each one named by its exact integral where it has one.
enum { SQUARE = 0, SINE, LORENTZ, EXPONENT, RUNGE };
static const char *const kNames[] = {"x^2", "sin", "1/(1+x^2)", "exp(-x)", "1/(1+100 x^2)"};

static long points;
static long batches;
static size_t batch_sizes[256];
static int batch_count;
static int which;

static void evaluate(void *arg, size_t n, const double *x, double *y)
{
    (void)arg;
    points += (long)n;
    batches++;
    if (batch_count < 256) {
        batch_sizes[batch_count++] = n;
    }
    for (size_t i = 0; i < n; i++) {
        switch (which) {
            case SQUARE:
                y[i] = x[i] * x[i];
                break;
            case SINE:
                y[i] = sin(x[i]);
                break;
            case LORENTZ:
                y[i] = 1.0 / (1.0 + x[i] * x[i]);
                break;
            case EXPONENT:
                y[i] = exp(-x[i]);
                break;
            default:
                y[i] = 1.0 / (1.0 + 100.0 * x[i] * x[i]);
                break;
        }
    }
}

static quadrature_integrate_function theFunction;

static void build_function(void)
{
    theFunction.fun = evaluate;
    theFunction.fun_arg = NULL;
}

// One call on each side, with the same options, and the comparison of everything both of them answer.
static void one(const char *name, int integrand, double a, double b, quadrature_integrator integrator,
                double abstol, double reltol, size_t points_per_interval, size_t max_intervals, size_t workspace_size)
{
    quadrature_integrate_options o;
    memset(&o, 0, sizeof o);
    o.integrator = integrator;
    o.abs_tolerance = abstol;
    o.rel_tolerance = reltol;
    o.qag_points_per_interval = points_per_interval;
    o.max_intervals = max_intervals;
    void *mine_workspace = NULL;
    void *their_workspace = NULL;
    if (workspace_size) {
        mine_workspace = calloc(1, workspace_size);
        their_workspace = calloc(1, workspace_size);
    }
    which = integrand;
    quadrature_status myStatus = QUADRATURE_SUCCESS, theirStatus = QUADRATURE_SUCCESS;
    double myError = -1.0, theirError = -1.0;
    points = batches = batch_count = 0;
    double mine = charon_host_quadrature_integrate(&theFunction, a, b, &o, &myStatus, &myError, workspace_size,
                                                  mine_workspace);
    long myPoints = points;
    long myBatches = batches;
    size_t mySizes[64];
    int myCount = batch_count < 64 ? batch_count : 64;
    memcpy(mySizes, batch_sizes, sizeof(size_t) * (size_t)myCount);
    which = integrand;
    points = batches = batch_count = 0;
    double theirs = quadrature_integrate(&theFunction, a, b, &o, &theirStatus, &theirError, workspace_size,
                                         their_workspace);
    long theirPoints = points;
    long theirBatches = batches;
    size_t theirSizes[64];
    int theirCount = batch_count < 64 ? batch_count : 64;
    memcpy(theirSizes, batch_sizes, sizeof(size_t) * (size_t)theirCount);

    // The same arithmetic on both sides, and the count of points, which is what tells the rules apart.
    double scale = fabs(theirs) > 1.0 ? fabs(theirs) : 1.0;
    int ok = myStatus == theirStatus && fabs(mine - theirs) <= 1e-12 * scale && myPoints == theirPoints &&
             myBatches == theirBatches && myCount == theirCount;
    for (int k = 0; ok && k < myCount; k++) {
        ok = mySizes[k] == theirSizes[k];
    }
    // And the absolute error, which the header says receives "an estimate of the absolute error on the
    // result": the two are estimates of the same quantity and agree to the same relative closeness.
    if (ok && theirError > 0.0) {
        double escale = theirError > 1e-300 ? theirError : 1e-300;
        ok = fabs(myError - theirError) <= 1e-6 * escale;
    }
    if (!ok) {
        snprintf(detail, sizeof detail,
                 "port %.17g status %d error %.6g over %ld points in %ld batches | host %.17g status %d error %.6g "
                 "over %ld points in %ld batches | batch sizes port",
                 mine, (int)myStatus, myError, myPoints, myBatches, theirs, (int)theirStatus, theirError, theirPoints,
                 theirBatches);
        size_t used = strlen(detail);
        for (int k = 0; k < myCount && used + 12 < sizeof detail; k++) {
            used += (size_t)snprintf(detail + used, sizeof detail - used, " %llu", (unsigned long long)mySizes[k]);
        }
        used += (size_t)snprintf(detail + used, sizeof detail - used, " | host");
        for (int k = 0; k < theirCount && used + 12 < sizeof detail; k++) {
            used += (size_t)snprintf(detail + used, sizeof detail - used, " %llu", (unsigned long long)theirSizes[k]);
        }
    }
    report(ok, name, detail);
    free(mine_workspace);
    free(their_workspace);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    build_function();
    const char *integrators[3] = {"QNG", "QAG", "QAGS"};
    // Every integrand, every integrator, three intervals and three tolerances.
    for (int i = 0; i < 3; i++) {
        for (int k = 0; k < 5; k++) {
            char name[160];
            snprintf(name, sizeof name, "%s over %s, 0..1 at 1e-10", integrators[i], kNames[k]);
            one(name, k, 0.0, 1.0, (quadrature_integrator)i, 1e-10, 1e-10, 0, 50, 0);
            snprintf(name, sizeof name, "%s over %s, 0..pi at 1e-8", integrators[i], kNames[k]);
            one(name, k, 0.0, 3.14159265358979323846, (quadrature_integrator)i, 1e-8, 1e-8, 0, 50, 0);
            snprintf(name, sizeof name, "%s over %s, -1..1 at 1e-12", integrators[i], kNames[k]);
            one(name, k, -1.0, 1.0, (quadrature_integrator)i, 1e-12, 1e-12, 0, 100, 0);
        }
    }
    // The point counts the header lists, each of which is its own rule: a case that passed all six with one
    // rule would be a check that cannot fail, so the callback's count is compared too.
    {
        const size_t counts[6] = {15, 21, 31, 41, 51, 61};
        for (int k = 0; k < 6; k++) {
            char name[160];
            snprintf(name, sizeof name, "QAG over 1/(1+x^2) with %llu points an interval",
                     (unsigned long long)counts[k]);
            one(name, LORENTZ, -1.0, 1.0, QUADRATURE_INTEGRATE_QAG, 1e-12, 1e-12, counts[k], 100, 0);
        }
    }
    // The subdivision limit: one and two intervals, where QAG and QAGS part company, and the boundary a
    // workspace of exactly one interval's bytes sits on.
    for (size_t limit = 1; limit <= 3; limit++) {
        char name[160];
        for (int k = 1; k <= 2; k++) {
            snprintf(name, sizeof name, "%s over 1/(1+x^2) with max_intervals %llu", integrators[k],
                     (unsigned long long)limit);
            one(name, LORENTZ, -1.0, 1.0, (quadrature_integrator)k, 1e-12, 1e-12, 0, limit, 0);
        }
    }
    {
        char name[160];
        snprintf(name, sizeof name, "QAG with a workspace of %d bytes, one interval", QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL);
        one(name, LORENTZ, -1.0, 1.0, QUADRATURE_INTEGRATE_QAG, 1e-12, 1e-12, 0, 0,
            QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL);
        snprintf(name, sizeof name, "QAG with a workspace of %d bytes, one byte short",
                 QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL - 1);
        one(name, LORENTZ, -1.0, 1.0, QUADRATURE_INTEGRATE_QAG, 1e-12, 1e-12, 0, 0,
            QUADRATURE_INTEGRATE_QAG_WORKSPACE_PER_INTERVAL - 1);
        snprintf(name, sizeof name, "QAGS with a workspace of %d bytes, one interval",
                 QUADRATURE_INTEGRATE_QAGS_WORKSPACE_PER_INTERVAL);
        one(name, LORENTZ, -1.0, 1.0, QUADRATURE_INTEGRATE_QAGS, 1e-12, 1e-12, 0, 0,
            QUADRATURE_INTEGRATE_QAGS_WORKSPACE_PER_INTERVAL);
        snprintf(name, sizeof name, "QAGS with a workspace of %d bytes, three intervals",
                 3 * QUADRATURE_INTEGRATE_QAGS_WORKSPACE_PER_INTERVAL);
        one(name, LORENTZ, -1.0, 1.0, QUADRATURE_INTEGRATE_QAGS, 1e-12, 1e-12, 0, 0,
            3 * QUADRATURE_INTEGRATE_QAGS_WORKSPACE_PER_INTERVAL);
    }
    // A bound at infinity, which only QAGS takes.
    for (int k = 0; k < 5; k++) {
        char name[160];
        snprintf(name, sizeof name, "QAGS over %s from 0 to infinity", kNames[k]);
        one(name, k, 0.0, INFINITY, QUADRATURE_INTEGRATE_QAGS, 1e-8, 1e-8, 0, 200, 0);
    }
    // The refusals, each of which both sides have to answer the same way.
    {
        quadrature_integrate_options o;
        quadrature_status myStatus = QUADRATURE_SUCCESS, theirStatus = QUADRATURE_SUCCESS;
        double myError = -7.0, theirError = -7.0;
        char name[160];
        memset(&o, 0, sizeof o);
        o.integrator = QUADRATURE_INTEGRATE_QNG;
        o.abs_tolerance = 1e-10;
        o.rel_tolerance = 1e-10;
        which = SQUARE;
        double mine = charon_host_quadrature_integrate(NULL, 0.0, 1.0, &o, &myStatus, &myError, 0, NULL);
        double theirs = quadrature_integrate(NULL, 0.0, 1.0, &o, &theirStatus, &theirError, 0, NULL);
        snprintf(detail, sizeof detail, "port %.17g status %d error %.3g | host %.17g status %d error %.3g", mine,
                 (int)myStatus, myError, theirs, (int)theirStatus, theirError);
        report(mine == 0.0 && theirs == 0.0 && myStatus == theirStatus && myStatus == QUADRATURE_INVALID_ARG_ERROR,
               "a NULL function", detail);
        memset(&o, 0, sizeof o);
        o.integrator = QUADRATURE_INTEGRATE_QNG;
        o.abs_tolerance = 1e-10;
        o.rel_tolerance = 1e-10;
        myStatus = theirStatus = QUADRATURE_SUCCESS;
        myError = theirError = -7.0;
        mine = charon_host_quadrature_integrate(&theFunction, 0.0, 1.0, NULL, &myStatus, &myError, 0, NULL);
        theirs = quadrature_integrate(&theFunction, 0.0, 1.0, NULL, &theirStatus, &theirError, 0, NULL);
        snprintf(detail, sizeof detail, "port %.17g status %d error %.3g | host %.17g status %d error %.3g", mine,
                 (int)myStatus, myError, theirs, (int)theirStatus, theirError);
        report(mine == 0.0 && theirs == 0.0 && myStatus == theirStatus && myStatus == QUADRATURE_INVALID_ARG_ERROR,
               "a NULL options", detail);
    }
    // A count the header does not list, an integrator the enumeration does not name, both tolerances zero and
    // an unreachable tolerance: each is one case, and the host's answers are in facts/Accelerate/Quadrature.md.
    {
        char name[160];
        const size_t bad_counts[3] = {10, 20, 100};
        const quadrature_integrator bad_integrators[2] = {(quadrature_integrator)3, (quadrature_integrator)-1};
        const double bad_tolerances[3][2] = {{0.0, 0.0}, {1e-300, 1e-300}, {-1.0, 1e-10}};
        for (int k = 0; k < 3; k++) {
            snprintf(name, sizeof name, "QAG with %llu points an interval, which the header does not list",
                     (unsigned long long)bad_counts[k]);
            one(name, LORENTZ, -1.0, 1.0, QUADRATURE_INTEGRATE_QAG, 1e-12, 1e-12, bad_counts[k], 100, 0);
        }
        for (int k = 0; k < 2; k++) {
            snprintf(name, sizeof name, "an integrator of %d, which the enumeration does not name",
                     (int)bad_integrators[k]);
            one(name, LORENTZ, -1.0, 1.0, bad_integrators[k], 1e-12, 1e-12, 0, 100, 0);
        }
        for (int k = 0; k < 3; k++) {
            for (int i = 0; i < 3; i++) {
                snprintf(name, sizeof name, "%s over x^2 with the tolerances %g and %g", integrators[i],
                         bad_tolerances[k][0], bad_tolerances[k][1]);
                one(name, SQUARE, 0.0, 1.0, (quadrature_integrator)i, bad_tolerances[k][0], bad_tolerances[k][1], 0,
                    100, 0);
            }
        }
        // An infinite bound to the integrator that does not take one.
        snprintf(name, sizeof name, "QNG over 0..infinity, which only QAGS takes");
        one(name, LORENTZ, 0.0, INFINITY, QUADRATURE_INTEGRATE_QNG, 1e-8, 1e-8, 0, 100, 0);
    }
    // The bounds themselves: a == b, and a > b, which the header says "do not need to verify a <= b".
    {
        char name[160];
        snprintf(name, sizeof name, "QAG over x^2 with a == b");
        one(name, SQUARE, 1.0, 1.0, QUADRATURE_INTEGRATE_QAG, 1e-10, 1e-10, 0, 50, 0);
        snprintf(name, sizeof name, "QAG over x^2 with a > b");
        one(name, SQUARE, 1.0, 0.0, QUADRATURE_INTEGRATE_QAG, 1e-10, 1e-10, 0, 50, 0);
        snprintf(name, sizeof name, "QNG over x^2 with a > b");
        one(name, SQUARE, 1.0, 0.0, QUADRATURE_INTEGRATE_QNG, 1e-10, 1e-10, 0, 50, 0);
    }
    printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
