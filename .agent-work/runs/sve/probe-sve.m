// What vDSP_sve_svesq and vDSP_sve_svesqD actually compute, and in what order, asked of the host.
// The accumulation order is the question: a reduction over a variable N has no fixed association, so the
// variants are sequential, blocked at 2/4/8, and a double accumulator - with the SEQUENTIAL form as
// variant 0, and variant 0 required to reproduce the host before any variant is credited.
#include <Accelerate/Accelerate.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

static const float kDenormal = 1e-42f;          // below FLT_MIN, above zero
static const float kBig = 3.4e38f;

static void show(const char *label, float sum, float sumsq, vDSP_Length n)
{
    printf("  %-34s N %2ld  sum %-16.9g sumsq %-16.9g\n", label, (long)n, sum, sumsq);
}

// variant 0: sequential in the caller's type. 1..5: blocked. 6: a double accumulator.
static void variant(int which, const float *a, vDSP_Stride ia, vDSP_Length n, int is_double, double *out_sum, double *out_sq)
{
    if (is_double) {
        const double *d = (const double *)a;
        double s = 0, q = 0;
        if (which == 6) {
            for (vDSP_Length i = 0; i < n; i++) { s += d[i * ia]; q += d[i * ia] * d[i * ia]; }
        } else {
            vDSP_Length block = which == 0 ? 1 : (which == 1 ? 2 : (which == 2 ? 4 : 8));
            vDSP_Length i = 0;
            for (; i + block <= n; i += block) {
                double ps = 0, pq = 0;
                for (vDSP_Length k = 0; k < block; k++) { ps += d[(i + k) * ia]; pq += d[(i + k) * ia] * d[(i + k) * ia]; }
                s += ps; q += pq;
            }
            for (; i < n; i++) { s += d[i * ia]; q += d[i * ia] * d[i * ia]; }
        }
        *out_sum = s; *out_sq = q;
        return;
    }
    float s = 0, q = 0;
    if (which == 6) {
        double ds = 0, dq = 0;
        for (vDSP_Length i = 0; i < n; i++) { ds += a[i * ia]; dq += (double)a[i * ia] * a[i * ia]; }
        *out_sum = (float)ds; *out_sq = (float)dq;
        return;
    }
    vDSP_Length block = which == 0 ? 1 : (which == 1 ? 2 : (which == 2 ? 4 : 8));
    vDSP_Length i = 0;
    for (; i + block <= n; i += block) {
        float ps = 0, pq = 0;
        for (vDSP_Length k = 0; k < block; k++) { ps += a[(i + k) * ia]; pq += a[(i + k) * ia] * a[(i + k) * ia]; }
        s += ps; q += pq;
    }
    for (; i < n; i++) { s += a[i * ia]; q += a[i * ia] * a[i * ia]; }
    *out_sum = s; *out_sq = q;
}

static void compare(const char *label, const float *a, vDSP_Stride ia, vDSP_Length n, int is_double)
{
    float hs = 0, hq = 0;
    if (is_double) {
        double ds = 0, dq = 0;
        vDSP_sve_svesqD((const double *)a, ia, &ds, &dq, n);
        hs = (float)ds; hq = (float)dq;
    } else {
        vDSP_sve_svesq(a, ia, &hs, &hq, n);
    }
    static const char *const names[7] = {"sequential (variant 0)", "blocked at 2", "blocked at 4", "blocked at 8",
                                         "blocked at 16", "blocked at 32", "accumulated in double"};
    // The float form's answers are read back as floats. An earlier version printed them through a
    // *(double *)&hs, which reinterprets four bytes as eight and printed 5.5e-315 for a sum of 100 - the
    // comparisons were fine and only the reporting was nonsense.
    if (is_double) {
        double ds = 0, dq = 0;
        vDSP_sve_svesqD((const double *)a, ia, &ds, &dq, n);
        printf("  %s, N %ld: the host gives sum %.17g sumsq %.17g\n", label, (long)n, ds, dq);
        for (int v = 0; v < 7; v++) {
            double sum, q;
            variant(v, a, ia, n, 1, &sum, &q);
            printf("    %-24s sum %s  sumsq %s\n", names[v], sum == ds ? "matches" : "DIFFERS",
                   q == dq ? "matches" : "DIFFERS");
        }
        return;
    }
    printf("  %s, N %ld: the host gives sum %.9g sumsq %.9g\n", label, (long)n, hs, hq);
    if (is_double)
        return;
    for (int v = 0; v < 7; v++) {
        double s, q;
        variant(v, a, ia, n, 0, &s, &q);
        printf("    %-24s sum %s  sumsq %s\n", names[v], (float)s == hs ? "matches" : "DIFFERS",
               (float)q == hq ? "matches" : "DIFFERS");
    }
}

int main(void)
{
    setbuf(stdout, NULL);
    static float a[64];
    for (int i = 0; i < 64; i++) a[i] = (float)(0.5 + (i % 7) * 1.25);
    printf("  the input, 16 elements: ");
    for (int i = 0; i < 16; i++) printf("%g ", a[i]);
    printf("\n");
    compare("sequential data, stride 1", a, 1, 16, 0);
    compare("the same data, stride 3", a, 3, 16, 0);
    compare("a single element", a, 1, 1, 0);
    compare("no elements", a, 1, 0, 0);
    compare("a longer run, 64 elements", a, 1, 64, 0);

    printf("  the edge cases, each its own run so a NaN cannot hide a correct answer\n");
    float nan_one[4] = {1.0f, NAN, 3.0f, 4.0f};
    compare("a NaN in the middle", nan_one, 1, 4, 0);
    float signed_zero[4] = {0.0f, -0.0f, 0.0f, -0.0f};
    compare("signed zeroes", signed_zero, 1, 4, 0);
    float denorm[4] = {kDenormal, kDenormal, kDenormal, kDenormal};
    compare("four denormals", denorm, 1, 4, 0);
    float huge[4] = {kBig, kBig, kBig, kBig};
    compare("four at the top of the range", huge, 1, 4, 0);
    float mixed[6] = {1e30f, 1.0f, -1e30f, 1.0f, 1e-30f, 3.0f};
    compare("a range that overflows a naive sum of squares", mixed, 1, 6, 0);
    printf("  the sensitive case: 64 values that all cancel except a tail, where a blocked and a sequential sum differ\n");
    float cancelling[64];
    for (int i = 0; i < 64; i++) cancelling[i] = (i % 2) ? 1.0f : 1.0f + 1e-7f;
    compare("63 pairs of near-equal values", cancelling, 1, 64, 0);
    printf("  and the double form on the same data\n");
    double dcancelling[64];
    for (int i = 0; i < 64; i++) dcancelling[i] = (i % 2) ? 1.0 : 1.0 + 1e-16;
    compare("the same, in double", (float *)dcancelling, 1, 64, 1);
    return 0;
}
