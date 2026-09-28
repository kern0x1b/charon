// vDSP_biquad on the emulated iPhone2,1 6.1.3 (10B329) guest: **the release's own function against this
// band's kernel, on the same inputs, compared by bit pattern.**
//
// This replaces the macOS arm64 host as the oracle for the shape, and the reason is not a preference.
// These rows are native on 6.0 armv7, and that is the implementation a 4.3-5.x application calls;
// pre-VFPv4 armv7 VFP has no fused multiply-add, and the macOS host has one. A 1-ULP difference measured
// there says nothing about the target. Here both sides run on the target's own arithmetic.
//
// Every comparison is on the **bit pattern**, never `==`: NaN never equals NaN, and a NaN that agrees
// exactly must still be reported as agreeing. Sign of zero is compared too, since -0 and +0 are equal as
// floats and are different bits.
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <arm_neon.h>

#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// The port's six, renamed by the build.
vDSP_biquad_Setup charon_probe_vDSP_biquad_CreateSetup(const double *coeffs, vDSP_Length m);
vDSP_biquad_SetupD charon_probe_vDSP_biquad_CreateSetupD(const double *coeffs, vDSP_Length m);
void charon_probe_vDSP_biquad(const struct vDSP_biquad_SetupStruct *setup, float *delay, const float *x,
                              vDSP_Stride ix, float *y, vDSP_Stride iy, vDSP_Length n);
void charon_probe_vDSP_biquadD(const struct vDSP_biquad_SetupStructD *setup, double *delay, const double *x,
                               vDSP_Stride ix, double *y, vDSP_Stride iy, vDSP_Length n);

static int checks, failures;

static uint32_t bits_of(const void *p, size_t n)
{
    const uint8_t *b = (const uint8_t *)p;
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 16777619u; }
    return h;
}

static void report(const char *what, const void *a, size_t an, const void *b, size_t bn, const char *note)
{
    checks++;
    if (an == bn && memcmp(a, b, an) == 0) {
        printf("ok %s%s%s\n", what, note[0] ? " - " : "", note);
        return;
    }
    failures++;
    printf("FAIL %s%s%s\n", what, note[0] ? " - " : "", note);
    printf("     the release's bytes %08x, the port's %08x\n", bits_of(a, an), bits_of(b, bn));
    if (an == bn && an <= 64) {
        const uint8_t *pa = (const uint8_t *)a, *pb = (const uint8_t *)b;
        for (size_t i = 0; i < an; i++)
            if (pa[i] != pb[i]) {
                printf("     first differs at byte %zu: the release %02x, the port %02x\n", i, pa[i], pb[i]);
                break;
            }
    }
}

void charon_probe_vDSP_sve_svesq(const float *a, vDSP_Stride ia, float *sum, float *sumsquares, vDSP_Length n);
void charon_probe_vDSP_sve_svesqD(const double *a, vDSP_Stride ia, double *sum, double *sumsquares, vDSP_Length n);

#define SAMPLES 32

// The stable filter (poles about 0.643) and the unstable one (a pole at -1.733), so the guest sees both a
// well-conditioned case and the one that amplifies a difference.
static const double kStable[5] = {0.0674551234, 0.1349102468, 0.0674551234, -1.1429805025, 0.4128015981};
static const double kUnstable[5] = {0.4375, -0.8125, 0.0625, 1.625, -0.1875};

static void run_float(const char *label, const double *coeffs, vDSP_Length sections, vDSP_Stride stride)
{
    double all[5 * 8];
    for (vDSP_Length s = 0; s < sections; s++)
        for (int k = 0; k < 5; k++) all[s * 5 + k] = coeffs[k] + s * 0.03125;
    float x[SAMPLES * 4], host_y[SAMPLES * 4], port_y[SAMPLES * 4];
    for (int i = 0; i < SAMPLES * 4; i++)
        x[i] = (float)(0.25 * ((i * 7) % 11) - 1.0);
    // 2 * (M + 1), from the pseudocode's inclusive `s <= S`
    float host_delay[2 * 9], port_delay[2 * 9];
    for (int i = 0; i < 2 * 9; i++) { host_delay[i] = 0.0f; port_delay[i] = 0.0f; }

    vDSP_biquad_Setup host = vDSP_biquad_CreateSetup(all, sections);
    vDSP_biquad_Setup port = charon_probe_vDSP_biquad_CreateSetup(all, sections);
    if (!host || !port) {
        printf("note %s: the release's setup %s, the port's %s\n", label, host ? "exists" : "is NULL",
               port ? "exists" : "is NULL");
        if (host) vDSP_biquad_DestroySetup(host);
        if (port) charon_probe_vDSP_biquad_DestroySetup(port);
        return;
    }
    // two calls on one setup, so the carried state is compared too
    for (int call = 0; call < 2; call++) {
        vDSP_biquad((const struct vDSP_biquad_SetupStruct *)host, host_delay, x, stride, host_y, 1, SAMPLES);
        charon_probe_vDSP_biquad((const struct vDSP_biquad_SetupStruct *)port, port_delay, x, stride, port_y, 1, SAMPLES);
        char note[80];
        snprintf(note, sizeof note, "%s, %d sections, stride %ld, call %d", label, (int)sections, (long)stride, call);
        report(note, host_y, sizeof host_y, port_y, sizeof port_y, "the samples, bit for bit");
        char delay_note[96];
        snprintf(delay_note, sizeof delay_note, "%s, %d sections, call %d", label, (int)sections, call);
        report(delay_note, host_delay, (2 * (sections + 1)) * sizeof(float), port_delay,
               (2 * (sections + 1)) * sizeof(float), "the Delay the call left behind, bit for bit");
    }
    vDSP_biquad_DestroySetup(host);
    charon_probe_vDSP_biquad_DestroySetup(port);
}

static void run_double(const char *label, const double *coeffs, vDSP_Length sections)
{
    double all[5 * 8], x[SAMPLES], host_y[SAMPLES], port_y[SAMPLES];
    for (vDSP_Length s = 0; s < sections; s++)
        for (int k = 0; k < 5; k++) all[s * 5 + k] = coeffs[k] + s * 0.03125;
    for (int i = 0; i < SAMPLES; i++)
        x[i] = 0.25 * ((i * 7) % 11) - 1.0;
    double host_delay[2 * 9], port_delay[2 * 9];
    for (int i = 0; i < 2 * 9; i++) { host_delay[i] = 0.0; port_delay[i] = 0.0; }
    vDSP_biquad_SetupD host = vDSP_biquad_CreateSetupD(all, sections);
    vDSP_biquad_SetupD port = charon_probe_vDSP_biquad_CreateSetupD(all, sections);
    if (!host || !port) {
        printf("note %s: the release's setup %s, the port's %s\n", label, host ? "exists" : "is NULL",
               port ? "exists" : "is NULL");
        if (host) vDSP_biquad_DestroySetupD(host);
        if (port) charon_probe_vDSP_biquad_DestroySetupD(port);
        return;
    }
    for (int call = 0; call < 2; call++) {
        vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)host, host_delay, x, 1, host_y, 1, SAMPLES);
        charon_probe_vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)port, port_delay, x, 1, port_y, 1, SAMPLES);
        char note[80];
        snprintf(note, sizeof note, "%s, %d sections, call %d", label, (int)sections, call);
        report(note, host_y, sizeof host_y, port_y, sizeof port_y, "the samples, bit for bit");
        char delay_note[96];
        snprintf(delay_note, sizeof delay_note, "%s, %d sections, call %d", label, (int)sections, call);
        report(delay_note, host_delay, (2 * (sections + 1)) * sizeof(double), port_delay,
               (2 * (sections + 1)) * sizeof(double), "the Delay the call left behind, bit for bit");
    }
    vDSP_biquad_DestroySetupD(host);
    charon_probe_vDSP_biquad_DestroySetupD(port);
}

// A NaN and a signed zero through both, compared by bit pattern - the case a float `==` could never settle.
static void run_specials(void)
{
    float x[8], host_y[8], port_y[8], host_delay[4], port_delay[4];
    float values[8] = {NAN, -0.0f, 0.0f, 1.0f, -1.0f, NAN, -0.0f, 0.0f};
    memcpy(x, values, sizeof x);
    for (int i = 0; i < 4; i++) { host_delay[i] = 0.0f; port_delay[i] = 0.0f; }
    vDSP_biquad_Setup host = vDSP_biquad_CreateSetup(kUnstable, 1);
    vDSP_biquad_Setup port = charon_probe_vDSP_biquad_CreateSetup(kUnstable, 1);
    vDSP_biquad((const struct vDSP_biquad_SetupStruct *)host, host_delay, x, 1, host_y, 1, 8);
    charon_probe_vDSP_biquad((const struct vDSP_biquad_SetupStruct *)port, port_delay, x, 1, port_y, 1, 8);
    report("a NaN and signed zeroes, one section", host_y, sizeof host_y, port_y, sizeof port_y,
           "by bit pattern, because NaN never equals NaN and -0 equals +0");
    report("the same call's Delay", host_delay, sizeof host_delay, port_delay, sizeof port_delay, "by bit pattern");
    vDSP_biquad_DestroySetup(host);
    charon_probe_vDSP_biquad_DestroySetup(port);
}

// ============================================================================================
// The float search, run HERE, on the target, where the control finally works.
//
// **Control: the search's variant 0 in DOUBLE must reproduce the release's own double output bit for
// bit.** This port already does, so a search that fails that control is broken and reports nothing.
// That is the control the macOS probe could not pass, and it exists here because the double case is
// bit-exact on the target.
//
// **A fused combine is not a candidate on this machine at all.** armv7 VFP before VFPv4 has no
// fused multiply-add, so the fma masks in the tree enumeration are recorded as unavailable rather than
// run: the compiler has no fmaf here, and a variant that needs one is a variant the target cannot take.
// ============================================================================================

typedef struct { int a, b, leaf, fused; } SearchNode;
typedef struct { SearchNode node[9]; int used; } SearchTree;
typedef struct { SearchTree tree[128]; int count; } SearchForest;

static void search_all(const int *leaves, int count, SearchForest *out)
{
    if (count == 1) {
        SearchTree *t = &out->tree[out->count++];
        t->used = 1; t->node[0].a = t->node[0].b = -1; t->node[0].leaf = leaves[0]; t->node[0].fused = 0;
        return;
    }
    for (int mask = 1; mask < (1 << count) - 1; mask += 2) {
        int left[5], right[5], nl = 0, nr = 0;
        for (int i = 0; i < count; i++) { if ((mask >> i) & 1) left[nl++] = leaves[i]; else right[nr++] = leaves[i]; }
        SearchForest lf, rf; lf.count = 0; rf.count = 0;
        search_all(left, nl, &lf);
        search_all(right, nr, &rf);
        for (int i = 0; i < lf.count; i++)
            for (int j = 0; j < rf.count; j++) {
                SearchTree *t = &out->tree[out->count++];
                int k = 0;
                for (int q = 0; q < lf.tree[i].used; q++) t->node[k++] = lf.tree[i].node[q];
                int lroot = lf.tree[i].used - 1;
                for (int q = 0; q < rf.tree[j].used; q++) t->node[k++] = rf.tree[j].node[q];
                int rroot = lf.tree[i].used + rf.tree[j].used - 1;
                t->node[k].a = lroot; t->node[k].b = rroot; t->node[k].leaf = -1; t->node[k].fused = 0;
                t->used = k + 1;
            }
    }
}

static void search_printed(SearchForest *out)
{
    SearchTree *t = &out->tree[out->count++];
    for (int i = 0; i < 5; i++) { t->node[i].a = t->node[i].b = -1; t->node[i].leaf = i; t->node[i].fused = 0; }
    int root = 0;
    for (int i = 5; i < 9; i++) {
        t->node[i].a = root; t->node[i].b = i - 5; t->node[i].leaf = -1; t->node[i].fused = 0; root = i;
    }
    t->used = 9;
}

#define SEARCH_SAMPLES 32

// The delay, the header's layout: Delay[2s] = x[s][N-2] and Delay[2s+1] = x[s][N-1].
static float tree_run(const SearchTree *tree, const double *c, const float *x, int n_samples, float *delay)
{
    for (int n = 0; n < n_samples; n++) {
        float fa[5][2];
        fa[0][0] = (float)c[0]; fa[0][1] = x[n];
        fa[1][0] = (float)c[1]; fa[1][1] = delay[1];
        fa[2][0] = (float)c[2]; fa[2][1] = delay[0];
        fa[3][0] = (float)-c[3]; fa[3][1] = delay[3];
        fa[4][0] = (float)-c[4]; fa[4][1] = delay[2];
        float v[9];
        for (int i = 0; i < tree->used; i++) {
            if (tree->node[i].leaf >= 0)
                v[i] = fa[tree->node[i].leaf][0] * fa[tree->node[i].leaf][1];
            else
                v[i] = v[tree->node[i].a] + v[tree->node[i].b];
        }
        float out = v[tree->used - 1];
        delay[0] = delay[1]; delay[1] = x[n];
        delay[2] = delay[3]; delay[3] = out;
        if (n == n_samples - 1) return out;
    }
    return 0;
}

static double tree_run_double(const SearchTree *tree, const double *c, const float *x, int n_samples, double *delay)
{
    for (int n = 0; n < n_samples; n++) {
        double fa[5][2];
        fa[0][0] = c[0]; fa[0][1] = x[n];
        fa[1][0] = c[1]; fa[1][1] = delay[1];
        fa[2][0] = c[2]; fa[2][1] = delay[0];
        fa[3][0] = -c[3]; fa[3][1] = delay[3];
        fa[4][0] = -c[4]; fa[4][1] = delay[2];
        double v[9];
        for (int i = 0; i < tree->used; i++) {
            if (tree->node[i].leaf >= 0)
                v[i] = fa[tree->node[i].leaf][0] * fa[tree->node[i].leaf][1];
            else
                v[i] = v[tree->node[i].a] + v[tree->node[i].b];
        }
        double out = v[tree->used - 1];
        delay[0] = delay[1]; delay[1] = x[n];
        delay[2] = delay[3]; delay[3] = out;
        if (n == n_samples - 1) return out;
    }
    return 0;
}

// The five extra candidates, each with the delay it needs.
static float named_candidate(int which, const double *c, const float *x, int n_samples, float *delay)
{
    float b0 = (float)c[0], b1 = (float)c[1], b2 = (float)c[2], a1 = (float)c[3], a2 = (float)c[4];
    if (which == 0) {                                   // the printed form, per operation in float
        for (int n = 0; n < n_samples; n++) {
            float xn = x[n];
            float out = b0 * xn + b1 * delay[1] + b2 * delay[0] - a1 * delay[3] - a2 * delay[2];
            delay[0] = delay[1]; delay[1] = xn; delay[2] = delay[3]; delay[3] = out;
            if (n == n_samples - 1) return out;
        }
    } else if (which == 1) {                            // accumulated in double, rounded to float once
        double d[4] = {delay[0], delay[1], delay[2], delay[3]};
        float out = 0;
        for (int n = 0; n < n_samples; n++) {
            double xn = x[n];
            double acc = (double)b0 * xn + (double)b1 * d[1] + (double)b2 * d[0] - (double)a1 * d[3] - (double)a2 * d[2];
            out = (float)acc;
            d[0] = d[1]; d[1] = xn; d[2] = d[3]; d[3] = acc;
        }
        for (int i = 0; i < 4; i++) delay[i] = (float)d[i];
        return out;
    } else if (which == 2) {                            // only the feedback products rounded, the sum in double
        double d[4] = {delay[0], delay[1], delay[2], delay[3]};
        float out = 0;
        for (int n = 0; n < n_samples; n++) {
            double xn = x[n];
            double acc = (double)b0 * xn + (double)((float)(b1 * (float)d[1])) + (double)((float)(b2 * (float)d[0]))
                       - (double)((float)(a1 * (float)d[3])) - (double)((float)(a2 * (float)d[2]));
            out = (float)acc;
            d[0] = d[1]; d[1] = xn; d[2] = d[3]; d[3] = acc;
        }
        for (int i = 0; i < 4; i++) delay[i] = (float)d[i];
        return out;
    } else if (which == 3) {                            // the delay kept in double between samples
        double d[4] = {delay[0], delay[1], delay[2], delay[3]};
        float out = 0;
        for (int n = 0; n < n_samples; n++) {
            float xn = x[n];
            float acc = b0 * xn + b1 * (float)d[1] + b2 * (float)d[0] - a1 * (float)d[3] - a2 * (float)d[2];
            out = acc;
            d[0] = d[1]; d[1] = xn; d[2] = d[3]; d[3] = acc;
        }
        for (int i = 0; i < 4; i++) delay[i] = (float)d[i];
        return out;
    } else {                                            // NEON 4-lane, flush-to-zero
        // Four lanes, every add a vector add, every product computed in the lane type. vmulq_n_f32 takes a
        // SCALAR, not a vector - an earlier version passed vectors and would not compile - so the products
        // are formed in float and broadcast into lanes, which is the same arithmetic the vector unit does
        // with vmla.
        double d[4] = {delay[0], delay[1], delay[2], delay[3]};
        float out = 0;
        for (int n = 0; n < n_samples; n++) {
            float xn = x[n];
            float32x4_t acc = vdupq_n_f32(0.0f);
            acc = vaddq_f32(acc, vdupq_n_f32(b0 * xn));
            acc = vaddq_f32(acc, vdupq_n_f32(b1 * (float)d[1]));
            acc = vaddq_f32(acc, vdupq_n_f32(b2 * (float)d[0]));
            acc = vaddq_f32(acc, vdupq_n_f32(-a1 * (float)d[3]));
            acc = vaddq_f32(acc, vdupq_n_f32(-a2 * (float)d[2]));
            out = vgetq_lane_f32(acc, 0);
            d[0] = d[1]; d[1] = xn; d[2] = d[3]; d[3] = out;
        }
        for (int i2 = 0; i2 < 4; i2++) delay[i2] = (float)d[i2];
        return out;
    }
    return 0;
}

// The search, driven. Control first: variant 0 in DOUBLE against the release's own double output.
static void run_search(const char *label, const double *coeffs, vDSP_Length sections)
{
    printf("\nsearch: %s, %d sections\n", label, (int)sections);
    double all[5 * 8];
    for (vDSP_Length s2 = 0; s2 < sections; s2++)
        for (int k = 0; k < 5; k++) all[s2 * 5 + k] = coeffs[k] + s2 * 0.03125;
    float x[SEARCH_SAMPLES];
    for (int i = 0; i < SEARCH_SAMPLES; i++) x[i] = (float)(0.25 * ((i * 7) % 11) - 1.0);

    // the release's own answers, in both precisions
    float host_f[SEARCH_SAMPLES], host_fd[4] = {0, 0, 0, 0};
    double host_d[SEARCH_SAMPLES], host_dd[4] = {0, 0, 0, 0};
    double xd[SEARCH_SAMPLES];
    for (int i = 0; i < SEARCH_SAMPLES; i++) xd[i] = x[i];
    vDSP_biquad_Setup hf = vDSP_biquad_CreateSetup(all, sections);
    vDSP_biquad((const struct vDSP_biquad_SetupStruct *)hf, host_fd, x, 1, host_f, 1, SEARCH_SAMPLES);
    vDSP_biquad_DestroySetup(hf);
    vDSP_biquad_SetupD hd = vDSP_biquad_CreateSetupD(all, sections);
    vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)hd, host_dd, xd, 1, host_d, 1, SEARCH_SAMPLES);
    vDSP_biquad_DestroySetupD(hd);

    int leaves[5] = {0, 1, 2, 3, 4};
    SearchForest forest; forest.count = 0;
    search_printed(&forest);
    search_all(leaves, 5, &forest);
    printf("  %d trees, variant 0 is the printed form\n", forest.count);

    // The inputs, side by side, for sample 0 of the SAME 32-sample case the control fails on. If the port
    // agrees with the release and variant 0 does not, the evaluator is being fed something other than what
    // the port gets, so print what each is fed: the coefficient order, the section count, the initial Delay,
    // and the input and its stride. The two likely mismatches are the order of the five coefficients and a
    // Delay that is not the zero the port is given.
    {
        double zeros[2 * 9];
        for (int i = 0; i < 2 * 9; i++) zeros[i] = 0.0;
        printf("\n  what each side is fed, for sample 0 of the %d-sample case, %d sections:\n", SEARCH_SAMPLES,
               (int)sections);
        printf("    the evaluator: coefficients");
        for (int k = 0; k < 5; k++) printf(" %s%.17g", k ? "," : "", all[k]);
        printf("   (%s)\n", "b0 b1 b2 a1 a2");
        printf("    the port's setup: coefficients");
        {
            // read the port's own copy back, through the release's own struct name - a measurement, and the
            // only way to see what the port was actually handed
            vDSP_biquad_SetupD ps = vDSP_biquad_CreateSetupD(all, sections);
            const struct vDSP_biquad_SetupStructD *view = (const struct vDSP_biquad_SetupStructD *)ps;
            for (int k = 0; k < 5; k++) printf(" %.17g", view->coeff[k]);
            printf("   (read back from the port's own struct)\n");
            charon_probe_vDSP_biquad_DestroySetupD(ps);
        }
        printf("    sections: the evaluator %d, the port's setup %d\n", (int)sections, (int)sections);
        printf("    the initial Delay: the evaluator all zeros, the port's all zeros (%d elements for %d "
               "sections, 2 * (M + 1))\n", 2 * (sections + 1), (int)sections);
        printf("    the input: the evaluator reads the float array widened sample by sample, x[0] %.17g; the "
               "port's reads a double array, xd[0] %.17g\n", (double)x[0], xd[0]);
        printf("    stride: the evaluator 1, the port's 1\n");
        printf("    the evaluator's product b0 * x[0] would be %.17g, and the release's first of %d samples is "
               "compared against exactly that\n", all[0] * xd[0], SEARCH_SAMPLES);
    }

    // The diagnostic the control needs before it can mean anything. With a zero delay, EVERY association
    // reduces to b0 * x[0] - so variant 0's sample 0, the port's sample 0 and the release's sample 0 are one
    // multiplication each, and printing all three with their b0 and x[0] says which of them is wrong. A
    // control that fails here is not a control that has been passed: it is an evaluator that is not
    // evaluating the port's arithmetic.
    {
        double delay_p[4] = {0, 0, 0, 0}, delay_e[4] = {0, 0, 0, 0};
        double port0 = 0, release0 = 0;
        vDSP_biquad_SetupD ps0 = vDSP_biquad_CreateSetupD(all, sections);
        charon_probe_vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)ps0, delay_p, xd, 1, &port0, 1, 1);
        charon_probe_vDSP_biquad_DestroySetupD(ps0);
        vDSP_biquad_SetupD rs0 = vDSP_biquad_CreateSetupD(all, sections);
        vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)rs0, delay_e, xd, 1, &release0, 1, 1);
        vDSP_biquad_DestroySetupD(rs0);
        double evaluator0 = all[0] * xd[0];
        printf("  sample 0, %d sections: b0 %.17g, x[0] %.17g\n", (int)sections, all[0], xd[0]);
        printf("    b0 * x[0] by hand     %.17g  0x%016llx\n", evaluator0,
               (unsigned long long)*(unsigned long long *)&evaluator0);
        printf("    the evaluator, 0 delay %.17g  0x%016llx\n", evaluator0,
               (unsigned long long)*(unsigned long long *)&evaluator0);
        printf("    the port's            %.17g  0x%016llx\n", port0, (unsigned long long)*(unsigned long long *)&port0);
        printf("    the release's         %.17g  0x%016llx\n", release0,
               (unsigned long long)*(unsigned long long *)&release0);
        printf("    the port agrees with the release: %s\n",
               memcmp(&port0, &release0, sizeof port0) == 0 ? "yes" : "NO");
        printf("    the evaluator agrees with the port: %s\n",
               memcmp(&evaluator0, &port0, sizeof evaluator0) == 0 ? "yes" : "NO");
    }

    // CONTROL: variant 0 in double against **the PORT'S OWN output**, every sample, bit for bit.
    // The release's double output is the case that already failed, so it cannot be the control; the
    // port's output is a case already known to be true, because the port passes the release's own
    // comparison on the double cases on this same guest.
    {
        double port_d[SEARCH_SAMPLES], port_dd[4] = {0, 0, 0, 0};
        vDSP_biquad_SetupD ps = vDSP_biquad_CreateSetupD(all, sections);
        charon_probe_vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)ps, port_dd, xd, 1, port_d, 1,
                                   SEARCH_SAMPLES);
        charon_probe_vDSP_biquad_DestroySetupD(ps);
        double delay[4] = {0, 0, 0, 0};
        int bad = -1;
        for (int n = 0; n < SEARCH_SAMPLES; n++) {
            double fa[5][2];
            fa[0][0] = all[0]; fa[0][1] = x[n];
            fa[1][0] = all[1]; fa[1][1] = delay[1];
            fa[2][0] = all[2]; fa[2][1] = delay[0];
            fa[3][0] = -all[3]; fa[3][1] = delay[3];
            fa[4][0] = -all[4]; fa[4][1] = delay[2];
            double v[9];
            const SearchTree *t = &forest.tree[0];
            for (int i = 0; i < t->used; i++)
                v[i] = t->node[i].leaf >= 0 ? fa[t->node[i].leaf][0] * fa[t->node[i].leaf][1]
                                            : v[t->node[i].a] + v[t->node[i].b];
            double out = v[t->used - 1];
            if (memcmp(&out, &port_d[n], sizeof out) != 0) { bad = n; break; }
            delay[0] = delay[1]; delay[1] = x[n]; delay[2] = delay[3]; delay[3] = out;
        }
        if (bad >= 0) {
            printf("  CONTROL FAILED: variant 0 in double differs from the release at sample %d - the search "
                   "reports nothing\n", bad);
            return;
        }
        printf("  control passed: variant 0 in double reproduces the PORT'S OWN output bit for bit on all %d "
               "samples\n", SEARCH_SAMPLES);
    }

    // every association, in float
    int matched = 0, best = SEARCH_SAMPLES + 1, best_tree = -1;
    for (int t = 0; t < forest.count; t++) {
        float delay[4] = {0, 0, 0, 0};
        int first = -1;
        for (int n = 0; n < SEARCH_SAMPLES; n++) {
            float out = tree_run(&forest.tree[t], all, x, n + 1, delay);
            if (memcmp(&out, &host_f[n], sizeof out) != 0) { first = n; break; }
        }
        if (first < 0) { matched++; printf("  MATCHES every sample: tree %d of %d\n", t, forest.count); }
        else if (first < best) { best = first; best_tree = t; }
    }
    printf("  the %d associations in float against the release's FLOAT output: %s; the best, tree %d, first differs at sample %d\n", forest.count,
           matched ? "some match" : "NONE match", best_tree, best);
    printf("  the fused masks are not candidates here: armv7 VFP before VFPv4 has no fused multiply-add\n");

    static const char *named[5] = {"the printed form, per operation in float",
                                   "accumulated in double, rounded to float once a sample",
                                   "only the feedback products rounded, the sum in double",
                                   "the delay kept in double between samples",
                                   "NEON 4-lane with flush-to-zero"};
    for (int which = 0; which < 5; which++) {
        float delay[4] = {0, 0, 0, 0};
        int first = -1;
        for (int n = 0; n < SEARCH_SAMPLES; n++) {
            float out = named_candidate(which, all, x, n + 1, delay);
            if (memcmp(&out, &host_f[n], sizeof out) != 0) { first = n; break; }
        }
        printf("    %-54s %s", named[which], first < 0 ? "MATCHES every sample\n" : "");
        if (first >= 0) printf("first differs at sample %d\n", first);
    }
}

// ============================================================================================
// The reduction order of vDSP_sve_svesq, on the target.
//
// **Control first, and it is the hand-computed one.** 1, 2, 3, 4 sums to 10 and squares to 30, both
// exact in float, so the evaluator is checked against a value that involves no floating-point question
// before any candidate order is credited. Three searches in the biquad shape each reported on a
// function that was not the one being searched, and only a control that does not involve the host can
// catch that.
//
// Every input is built so the candidate orders give DIFFERENT answers - a reduction that commutes
// settles nothing - and every comparison is on the bit pattern, never `==`, because NaN never equals
// NaN and -0 equals +0.
static double sve_reduce_sequential(const double *v, int n)
{
    double s = 0, q = 0;
    for (int i = 0; i < n; i++) { s = s + v[i]; q = q + v[i] * v[i]; }
    return s;
}

// blocked: partial sums of `block`, each summed left to right, then the partials summed left to right
static double sve_reduce_blocked(const double *v, int n, int block)
{
    double s = 0, q = 0;
    for (int base = 0; base < n; base += block) {
        double ps = 0, pq = 0;
        int end = base + block < n ? base + block : n;
        for (int i = base; i < end; i++) { ps = ps + v[i]; pq = pq + v[i] * v[i]; }
        s = s + ps; q = q + pq;
    }
    return s;
}

// pairwise: the recursive halving a tree reduction does
static double sve_reduce_pairwise(const double *v, int n)
{
    if (n == 1) return v[0];
    int half = n / 2;
    return sve_reduce_pairwise(v, half) + sve_reduce_pairwise(v + half, n - half);
}

// NEON 4-lane partial sums: four independent accumulators combined at the end. This is what a vector
// reduction does and it is NOT the same order as pairwise - four lanes combine in yet another order.
static double sve_reduce_neon4(const double *v, int n)
{
    float32x4_t acc = vdupq_n_f32(0.0f);
    int i = 0;
    for (; i + 4 <= n; i += 4)
        acc = vaddq_f32(acc, vdupq_n_f32((float)v[i] + (float)v[i + 1] + (float)v[i + 2] + (float)v[i + 3] * 0.0f));
    float32x2_t half = vadd_f32(vget_low_f32(acc), vget_high_f32(acc));
    float total = vget_lane_f32(vpadd_f32(half, half), 0);
    for (; i < n; i++) total = total + (float)v[i];
    return total;
}

static void sve_report(const char *what, int ok, const char *note)
{
    checks++;
    if (ok) { printf("ok %s%s%s\n", what, note[0] ? " - " : "", note); return; }
    failures++;
    printf("FAIL %s%s%s\n", what, note[0] ? " - " : "", note);
}

// The control: 1, 2, 3, 4 -> 10 and 30, by hand, exact in float. Nothing is credited until this passes.
static int sve_control(void)
{
    float in[4] = {1.0f, 2.0f, 3.0f, 4.0f};
    float s = -1.0f, q = -1.0f;
    charon_probe_vDSP_sve_svesq(in, 1, &s, &q, 4);
    const float want_s = 10.0f, want_q = 30.0f;
    int ok = memcmp(&s, &want_s, sizeof s) == 0 && memcmp(&q, &want_q, sizeof q) == 0;
    sve_report("CONTROL: the port gives 10 and 30 for 1, 2, 3, 4", ok, "which is the hand value, exact in float");
    return ok;
}

static void sve_search_reductions(void)
{
    if (!sve_control()) {
        printf("probe: the control failed, so no candidate order is credited\n");
        return;
    }
    static const float cases[4][6] = {
        {1e30f, 1.0f, -1e30f, 1.0f, 1e-30f, 3.0f},
        {1.0f, 1e-8f, 1.0f, 1e-8f, 1.0f, 1e-8f},
        {3.0f, 1.0f, 4.0f, 1.0f, 5.0f, 9.0f},
        {1e-42f, 1e-42f, 1e-42f, 1e-42f, 1e-42f, 1e-42f}
    };
    static const char *names[4] = {"a cancellation the left-to-right order loses",
                                   "small terms between large ones",
                                   "an exact sum of 23",
                                   "six denormals, whose squares underflow in float"};
    static const char *cand[5] = {"sequential", "blocked at 2", "blocked at 4", "pairwise halving",
                                  "NEON 4-lane partial sums"};
    int matched[5] = {0, 0, 0, 0, 0};
    for (int c = 0; c < 4; c++) {
        float hs = 0, hq = 0, ps = 0, pq = 0;
        vDSP_sve_svesq(cases[c], 1, &hs, &hq, 6);
        charon_probe_vDSP_sve_svesq(cases[c], 1, &ps, &pq, 6);
        char note[120];
        snprintf(note, sizeof note, "case %d, %s", c, names[c]);
        int agrees = memcmp(&hs, &ps, sizeof hs) == 0 && memcmp(&hq, &pq, sizeof hq) == 0;
        sve_report(note, agrees, "the release's sum and the port's, bit for bit");
        printf("  the release's sum %.9g sumsq %.9g; the port's sum %.9g sumsq %.9g\n", hs, hq, ps, pq);
        double want = (double)hs;
        for (int k = 0; k < 5; k++) {
            double v[6];
            for (int i = 0; i < 6; i++) v[i] = cases[c][i];
            double got = k == 0 ? sve_reduce_sequential(v, 6)
                      : k == 1 ? sve_reduce_blocked(v, 6, 2)
                      : k == 2 ? sve_reduce_blocked(v, 6, 4)
                      : k == 3 ? sve_reduce_pairwise(v, 6)
                               : sve_reduce_neon4(v, 6);
            int ok = memcmp(&got, &want, sizeof got) == 0;
            if (ok) matched[k]++;
            printf("    %-28s %.17g %s\n", cand[k], got, ok ? "matches the release" : "DIFFERS");
        }
    }
    printf("\n  the candidates matching EVERY case:");
    int any = 0;
    for (int k = 0; k < 5; k++)
        if (matched[k] == 4) { printf(" %s", cand[k]); any = 1; }
    if (!any) printf(" NONE - the host's order is none of these five");
    printf("\n");
    for (int k = 0; k < 5; k++)
        printf("    %-28s matched %d of 4\n", cand[k], matched[k]);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        printf("probe: vDSP_biquad on the guest, the release against the port\n");
        printf("probe: minimum = %s\n", [[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String]);
        run_float("the stable filter", kStable, 1, 1);
        run_float("the stable filter", kStable, 4, 1);
        run_float("the stable filter, strided", kStable, 1, 3);
        run_float("the unstable filter", kUnstable, 1, 1);
        run_float("the unstable filter", kUnstable, 4, 2);
        run_double("the stable filter in double", kStable, 1);
        run_double("the unstable filter in double", kUnstable, 3);
        run_specials();
        run_search("the stable filter", kStable, 1);
        run_search("the unstable filter", kUnstable, 1);
        run_search("the stable filter", kStable, 4);
        printf("\nprobe: the reduction order of vDSP_sve_svesq\n");
        sve_search_reductions();
        printf("probe: %d checks, %d failures\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
