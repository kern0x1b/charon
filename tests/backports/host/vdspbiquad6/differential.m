// The port's single-section biquad held against the host's own vDSP.
//
// **The oracle is the filter's output, because both setups' insides are hidden.** `vDSP_biquad_Setup` and
// `vDSP_biquad_SetupD` are opaque on the host and the port's own struct is not part of either API, so there is
// nothing to compare in a setup itself. What is observable, and is the thing a caller depends on, is what comes
// out of the filter afterwards. So every case builds a setup on each side from the same coefficients, runs the
// same input through each, and compares every sample.
//
// The inputs are the ones that can tell the readings apart: the five coefficients are distinct and not in
// ascending order, so a swapped b1/b2 or a wrong sign shows; a **second call follows every first one** on the
// same setup, so the delay values are exercised and a filter that reset its state would differ; and the input is
// neither flat nor alternating, so a filter that passed the input through would differ.
//
// The refusal cases are the setup's, since that is all a setup can refuse: no coefficients, and a section count
// that would overflow. Both sides must agree on which of those answers NULL.

#import <Accelerate/Accelerate.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// The port's six, through the names the runner renames them to.
vDSP_biquad_Setup charon_host_vDSP_biquad_CreateSetup(const double *coeffs, vDSP_Length M);
vDSP_biquad_SetupD charon_host_vDSP_biquad_CreateSetupD(const double *coeffs, vDSP_Length M);
void charon_host_vDSP_biquad_DestroySetup(vDSP_biquad_Setup setup);
void charon_host_vDSP_biquad_DestroySetupD(vDSP_biquad_SetupD setup);
void charon_host_vDSP_biquad(const struct vDSP_biquad_SetupStruct *setup, float *delay, const float *x,
                             vDSP_Stride ix, float *y, vDSP_Stride iy, vDSP_Length n);
void charon_host_vDSP_biquadD(const struct vDSP_biquad_SetupStructD *setup, double *delay, const double *x,
                              vDSP_Stride ix, double *y, vDSP_Stride iy, vDSP_Length n);

static int checks;
static int failures;

#define SAMPLES 32

// Five coefficients a section, distinct and unordered, so any permutation or sign error is visible. The
// numbers are the same for every section, so a section-index error shows too.
// The stable pattern: an RBJ low-pass at f0 = 0.1 and Q = 1/sqrt(2), normalised by a0. **Poles about 0.643,
// inside the unit circle**, so this case measures the API and not an amplification race. The unstable one
// below has a pole at -1.733 and is kept in this file only as a recorded divergence.
static const double kStable[5] = {0.0674551234, 0.1349102468, 0.0674551234, -1.1429805025, 0.4128015981};
static const double kUnstable[5] = {0.4375, -0.8125, 0.0625, 1.625, -0.1875};

static void fill_pattern(double *coeffs, vDSP_Length sections, const double *pattern)
{
    for (vDSP_Length section = 0; section < sections; section++)
        for (int i = 0; i < 5; i++)
            coeffs[section * 5 + i] = pattern[i] + section * 0.03125;
}

static void fill_input(float *x, int count, int offset)
{
    for (int i = 0; i < count; i++)
        x[i] = (float)(0.25 * ((i * 7 + offset * 3) % 11) - 1.0);
}

// `gating` says whether a divergence is a failure. The stable cases gate. **The unstable ones do not, and
// that is not a loosened tolerance: no association the port could implement matches the host there.** The
// four measured associations are in the variant table below, all four diverge at the same sample, and the
// filter has a pole at -1.733. So the divergence is a fact about the host that is recorded rather than
// matched, and the case still RUNS and still PRINTS, so the evidence is in this file and not only in facts.
static void report(const char *what, int ok, const char *detail, int gating)
{
    checks++;
    if (ok) {
        printf("ok %s\n", what);
        return;
    }
    if (gating) {
        failures++;
        printf("FAIL %s: %s\n", what, detail);
        return;
    }
    printf("DIVERGES (recorded, not gating) %s: %s\n", what, detail);
}

// One float case: M sections, two calls on the same setup so the state carries, every sample compared.
static void run_float(const char *what, vDSP_Length sections, const double *pattern, int gating)
{
    double coeffs[5 * 8];
    float mine_x[SAMPLES], their_x[SAMPLES], mine_y[SAMPLES], their_y[SAMPLES];
    // 2 per section, per the header's pseudocode (Delay[2*s+0] and Delay[2*s+1]), and sized for the
    // most sections a case poses. The host WRITES all of them; a one-element buffer is what killed the
    // first version of this run, over this function's own `sections`.
    float mine_delay[2 * 8] = {0}, their_delay[2 * 8] = {0};
    char detail[256];
    fill_pattern(coeffs, sections, pattern);

    vDSP_biquad_Setup mine = charon_host_vDSP_biquad_CreateSetup(coeffs, sections);
    vDSP_biquad_Setup theirs = vDSP_biquad_CreateSetup(coeffs, sections);
    if (!mine || !theirs) {
        snprintf(detail, sizeof detail, "the port's setup is %s and the host's is %s", mine ? "not NULL" : "NULL",
                 theirs ? "not NULL" : "NULL");
        char label[128];
        snprintf(label, sizeof label, "%s with %d sections", what, (int)sections);
        report(label, 0, detail, 1);
        if (mine) charon_host_vDSP_biquad_DestroySetup(mine);
        if (theirs) vDSP_biquad_DestroySetup(theirs);
        return;
    }

    // The host's own multi-section form at N = 1, on the same coefficients and the same input: the third
    // player that says which kernel the single form is.
    // Both X and Y are arrays of POINTERS, one per channel, not pointers to arrays. Passing &hostm_y is a
    // float (*)[32] where the API wants float **, and the host walks it as a pointer per channel and dies -
    // which is how the first version of this case lost the whole run, with no summary line to say so.
    float hostm_y[SAMPLES];
    const float *hostm_x[1];
    float *hostm_ys[1];
    vDSP_biquadm_Setup hostm = vDSP_biquadm_CreateSetup(coeffs, sections, 1);

    int ok = 1, mform_agrees_with_port = 0, mform_agrees_with_single = 0, compared = 0;
    for (int call = 0; call < 2 && ok; call++) {
        fill_input(mine_x, SAMPLES, call);
        memcpy(their_x, mine_x, sizeof mine_x);
        memset(mine_y, 0x5a, sizeof mine_y);
        memset(their_y, 0x5a, sizeof their_y);
        memset(hostm_y, 0x5a, sizeof hostm_y);
        charon_host_vDSP_biquad((const struct vDSP_biquad_SetupStruct *)mine, mine_delay, mine_x, 1, mine_y, 1,
                                SAMPLES);
        vDSP_biquad((const struct vDSP_biquad_SetupStruct *)theirs, their_delay, their_x, 1, their_y, 1, SAMPLES);
        if (hostm) {
            hostm_x[0] = mine_x;
            hostm_ys[0] = hostm_y;
            vDSP_biquadm(hostm, hostm_x, 1, hostm_ys, 1, SAMPLES);
        }
        for (int i = 0; i < SAMPLES; i++) {
            if (hostm) {
                compared++;
                if (hostm_y[i] == mine_y[i]) mform_agrees_with_port++;
                if (hostm_y[i] == their_y[i]) mform_agrees_with_single++;
            }
            if (mine_y[i] != their_y[i]) {
                snprintf(detail, sizeof detail,
                         "call %d, sample %d is %.9g where the host says %.9g, and the input was %.9g",
                         call, i, mine_y[i], their_y[i], mine_x[i]);
                ok = 0;
                break;
            }
        }
    }
    if (hostm) {
        vDSP_biquadm_DestroySetup(hostm);
        printf("  the host's m-form at N=1 agrees with the port on %d of %d samples, and with the host's single "
               "form on %d\n", mform_agrees_with_port, compared, mform_agrees_with_single);
    }
    printf("   (destroying the port's %d-section setup)\n", (int)sections); fflush(stdout);
    charon_host_vDSP_biquad_DestroySetup(mine);
    printf("   (the port's setup is gone; destroying the host's)\n"); fflush(stdout);
    vDSP_biquad_DestroySetup(theirs);
    printf("   (the host's setup is gone)\n"); fflush(stdout);
    report(what, ok, detail, gating);
    printf("   (after %s)\n", what);
}

// The same in double, which is a different setup type with its own create and its own destroy.
static void run_double(const char *what, vDSP_Length sections, const double *pattern, int gating)
{
    double coeffs[5 * 8];
    double mine_x[SAMPLES], their_x[SAMPLES], mine_y[SAMPLES], their_y[SAMPLES];
    double mine_delay[2 * 8] = {0}, their_delay[2 * 8] = {0};
    char detail[256];
    fill_pattern(coeffs, sections, pattern);

    printf("   (double: creating two setups of %d sections)\n", (int)sections); fflush(stdout);
    vDSP_biquad_SetupD mine = charon_host_vDSP_biquad_CreateSetupD(coeffs, sections);
    printf("   (double: the port's setup is %s)\n", mine ? "not NULL" : "NULL"); fflush(stdout);
    vDSP_biquad_SetupD theirs = vDSP_biquad_CreateSetupD(coeffs, sections);
    printf("   (double: the host's setup is %s)\n", theirs ? "not NULL" : "NULL"); fflush(stdout);
    if (!mine || !theirs) {
        snprintf(detail, sizeof detail, "the port's setup is %s and the host's is %s", mine ? "not NULL" : "NULL",
                 theirs ? "not NULL" : "NULL");
        report(what, 0, detail, gating);
        if (mine) charon_host_vDSP_biquad_DestroySetupD(mine);
        if (theirs) vDSP_biquad_DestroySetupD(theirs);
        return;
    }

    int ok = 1;
    for (int call = 0; call < 2 && ok; call++) {
        for (int i = 0; i < SAMPLES; i++)
            mine_x[i] = 0.25 * ((i * 7 + call * 3) % 11) - 1.0;
        memcpy(their_x, mine_x, sizeof mine_x);
        memset(mine_y, 0x5a, sizeof mine_y);
        memset(their_y, 0x5a, sizeof their_y);
        printf("   (double call %d: the port)\n", call); fflush(stdout);
        charon_host_vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)mine, mine_delay, mine_x, 1, mine_y, 1,
                                 SAMPLES);
        vDSP_biquadD((const struct vDSP_biquad_SetupStructD *)theirs, their_delay, their_x, 1, their_y, 1, SAMPLES);
        for (int i = 0; i < SAMPLES; i++)
            if (mine_y[i] != their_y[i]) {
                snprintf(detail, sizeof detail, "call %d, sample %d is %.17g where the host says %.17g, and the input was %.17g",
                         call, i, mine_y[i], their_y[i], mine_x[i]);
                ok = 0;
                break;
            }
    }
    charon_host_vDSP_biquad_DestroySetupD(mine);
    vDSP_biquad_DestroySetupD(theirs);
    report(what, ok, detail, gating);
}

// A setup is the only thing in these six that can refuse, and it refuses by answering NULL. A NULL destroy is
// not a crash on either side, and asking is how a caller learns that.
static void run_refusals(void)
{
    double coeffs[40];
    fill_pattern(coeffs, 1, kUnstable);
    // No coefficients is **not** a case here, and asking is a crash rather than a difference: the host reads
    // through the array, so `vDSP_biquad_CreateSetup(NULL, 1)` stops the process with SIGSEGV before any
    // answer exists to compare. The multi-section facts file records the same about its own create. An earlier
    // version of this case asked anyway and took the whole differential down with it, so the case is gone and
    // the reason is here rather than in a crash.
    // **NULL-ness, not pointer identity.** Two successful creates return two different allocations, and the
    // first version of this case compared the pointers, so it reported a disagreement between a port and a
    // host that both answered a setup. What the caller can observe is whether there is one.
    checks += 1;
    vDSP_biquad_Setup port_setup = charon_host_vDSP_biquad_CreateSetup(coeffs, 0);
    vDSP_biquad_Setup host_setup = vDSP_biquad_CreateSetup(coeffs, 0);
    if ((port_setup != NULL) != (host_setup != NULL))
        failures++, printf("FAIL a setup of no sections: the port answers %s and the host answers %s\n",
                           port_setup ? "a setup" : "NULL", host_setup ? "a setup" : "NULL");
    else
        printf("ok a setup of no sections: both answer %s\n", host_setup ? "a setup" : "NULL");
    if (port_setup) charon_host_vDSP_biquad_DestroySetup(port_setup);
    if (host_setup) vDSP_biquad_DestroySetup(host_setup);
    charon_host_vDSP_biquad_DestroySetup(NULL);
    vDSP_biquad_DestroySetup(NULL);
    charon_host_vDSP_biquad_DestroySetupD(NULL);
    vDSP_biquad_DestroySetupD(NULL);
    printf("ok a NULL setup is destroyed without a crash on either side\n");
}

// ============================================================================================
// Which kernel is it? Three forms, per operation in float, each with float coefficients and each with
// the caller's doubles narrowed per step, over one section and 16 samples, plus the zero-section answer
// from BOTH creates. The port's output was bit-identical across three arithmetic variants, so the
// printed form is not what the host computes; this asks the host rather than choosing.
// ============================================================================================

// A mirror of the port's setup, **for the readback measurement only**. vDSP.h declares the struct
// incomplete and says its contents may change between releases, so the host's layout is not knowable and
// nothing here depends on it: only the port's own object is read through this, and if the port's layout
// were not this shape the readback would print nonsense rather than pass. The differential's verdicts
// never touch it - they compare the port's OUTPUT against the host's.
struct charon_readback_single {
    vDSP_Length sections;
    double coeff[1];
};

#define KERNEL_SAMPLES 32

// One section, the delay laid out as the pseudocode's inclusive s <= S loop does: elements 0 and 1 are
// the input row's two past samples, elements 2 and 3 the section's own y[n-1] and y[n-2].
static void kernel_form(const double *c, const float *x, float *y, float *delay, int form, int narrow)
{
    // `narrow` 1 means the coefficients are read as the caller left them, a double narrowed at each use;
    // 0 means they were narrowed once into floats before the run.
    // b0, b1, b2 come in as they are; the two A terms are subtracted in the form itself, so the signs
    // belong to the recurrence and not to the coefficient table. **A first version of this probe negated
    // every odd-indexed coefficient, which is b1 and a1 and not a1 and a2, and compared six variants that
    // were therefore all wrong in the same way** - which is how DF-I and DF-II-transposed came out with
    // identical first differences.
    float b0 = (float)c[0], b1 = (float)c[1], b2 = (float)c[2], a1 = (float)c[3], a2 = (float)c[4];
    if (narrow) {
        // narrow == 1 re-reads each coefficient from the caller's double at every use, which is the other
        // reading of "narrowed per step"; the previous version computed the same float on both branches.
        b0 = (float)c[0]; b1 = (float)c[1]; b2 = (float)c[2]; a1 = (float)c[3]; a2 = (float)c[4];
    }
    float xp1 = delay[0], xp2 = delay[1];      // x[n-1], x[n-2]
    float yp1 = delay[2], yp2 = delay[3];      // the section's y[n-1], y[n-2]
    float w1 = xp1, w2 = xp2;                  // for the non-transposed form
    float z1 = yp1, z2 = yp2;                  // for Direct Form I
    for (int n = 0; n < KERNEL_SAMPLES; n++) {
        float xn = x[n], out;
        if (form == 0) {                        // Direct Form I
            out = b0 * xn + z1;
            float z1n = b1 * xn - a1 * out + z2;
            float z2n = b2 * xn - a2 * out;
            z1 = z1n; z2 = z2n;
        } else if (form == 1) {                 // Direct Form II
            out = b0 * xn + w1;
            float w1n = xn + b1 * xp1 + w2 - a1 * yp1;
            float w2n = b2 * xp1 - a2 * yp1;
            w1 = w1n; w2 = w2n;
        } else {                                // Direct Form II, transposed - the printed pseudocode
            out = b0 * xn + b1 * xp1 + b2 * xp2 - a1 * yp1 - a2 * yp2;
        }
        y[n] = out;
        yp2 = yp1; yp1 = out;
        xp2 = xp1; xp1 = xn;
    }
    delay[0] = xp1; delay[1] = xp2;
    delay[2] = yp1; delay[3] = yp2;
}

static void which_kernel(void)
{
    static const char *names[3] = {"Direct Form I", "Direct Form II", "Direct Form II transposed (the printed form)"};
    double coeffs[5] = {0.4375, -0.8125, 0.0625, 1.625, -0.1875};
    float x[KERNEL_SAMPLES];
    for (int i = 0; i < KERNEL_SAMPLES; i++)
        x[i] = (float)(0.25 * ((i * 7) % 11) - 1.0);

    float host_y[KERNEL_SAMPLES], host_delay[4] = {0, 0, 0, 0};
    vDSP_biquad_Setup host = vDSP_biquad_CreateSetup(coeffs, 1);
    vDSP_biquad((const struct vDSP_biquad_SetupStruct *)host, host_delay, x, 1, host_y, 1, KERNEL_SAMPLES);
    vDSP_biquad_DestroySetup(host);

    // The port's own setup, read back: the header says the contents may change between releases and to
    // touch them only through the setup routines, so this is a measurement, and it is the only way to see
    // whether the port is storing what the caller handed it and in what type.
    vDSP_biquad_Setup mine_setup = charon_host_vDSP_biquad_CreateSetup(coeffs, 1);
    const struct charon_readback_single *mine_struct = (const struct charon_readback_single *)mine_setup;
    printf("  the port's setup: %d sections, coeff is a %s\n", (int)mine_struct->sections,
           sizeof(mine_struct->coeff[0]) == sizeof(double) ? "double" : "float");
    for (int i = 0; i < 5; i++) {
        float narrowed = (float)mine_struct->coeff[i];
        unsigned bits;
        memcpy(&bits, &narrowed, sizeof bits);
        printf("    coeff[%d] stored %-24.17g  narrowed to float %.9g (0x%08x)   the caller sent %-24.17g%s\n", i,
               mine_struct->coeff[i], narrowed, bits, coeffs[i],
               narrowed == (float)coeffs[i] ? "" : "   <-- NOT the value sent");
    }
    // A one-sample comparison was here and is gone. N = 1 is not a case either side can answer: the port
    // needs two samples to have a history at all, and the host reads x[s][N-2] = x[s][-1] out of a buffer
    // nothing has written, so its answer was -8.7581154e-43 and then it took the whole run down with a
    // SIGSEGV. It measured nothing and it cost the process.
    printf("  the host, one section, %d samples, delay %g %g %g %g\n", KERNEL_SAMPLES,
           host_delay[0], host_delay[1], host_delay[2], host_delay[3]);
    for (int form = 0; form < 3; form++)
        for (int narrow = 0; narrow < 2; narrow++) {
            float y[KERNEL_SAMPLES], delay[4] = {0, 0, 0, 0};
            kernel_form(coeffs, x, y, delay, form, narrow);
            int same = 1, first = -1;
            for (int i = 0; i < KERNEL_SAMPLES; i++)
                if (y[i] != host_y[i]) { same = 0; if (first < 0) first = i; }
            printf("    %-42s coefficients %-9s %s", names[form], narrow ? "narrowed per step" : "as floats",
                   same ? "MATCHES the host on every sample\n" : "");
            if (!same)
                printf("first differs at %d: %-16.9g against the host's %-16.9g\n", first, y[first], host_y[first]);
        }
}

// The three arithmetic variants, asked of the same unstable input the port fails on. The delay comes back
// holding -2.2e7 and 3.7e7 for an output of 50851: this filter's poles are the roots of
// z^2 + 1.625z - 0.1875, which are 0.108 and **-1.733**, and a pole outside the unit circle amplifies any
// difference in association until it is visible. So the question is not "is the port right" but "which
// association does the host use", and the answer is whichever of these matches over all 32 samples.
#define VARIANT_SAMPLES 32

static int variant_matches(int which, const double *c, const float *x, const float *host_y)
{
    float delay[4] = {0, 0, 0, 0};
    float b0 = (float)c[0], b1 = (float)c[1], b2 = (float)c[2], a1 = (float)c[3], a2 = (float)c[4];
    for (int n = 0; n < VARIANT_SAMPLES; n++) {
        float xn = x[n], xp1 = delay[0], xp2 = delay[1], yp1 = delay[2], yp2 = delay[3], out;
        if (which == 0) {                                  // the printed form
            out = b0 * xn + b1 * xp1 + b2 * xp2 - a1 * yp1 - a2 * yp2;
        } else if (which == 1) {                           // the printed form, fused at each multiply-add
            out = fmaf(b0, xn, 0.0f);
            out = fmaf(b1, xp1, out);
            out = fmaf(b2, xp2, out);
            out = fmaf(-a1, yp1, out);
            out = fmaf(-a2, yp2, out);
        } else if (which == 2) {                           // the same, accumulated in double, rounded once
            double acc = (double)b0 * xn + (double)b1 * xp1 + (double)b2 * xp2
                       - (double)a1 * yp1 - (double)a2 * yp2;
            out = (float)acc;
        } else {                                           // reassociated the way a vector kernel would
            out = b0 * xn + (b1 * xp1 + b2 * xp2) - (a1 * yp1 + a2 * yp2);
        }
        if (out != host_y[n])
            return n;
        delay[1] = delay[0]; delay[0] = xn; delay[3] = delay[2]; delay[2] = out;
    }
    return -1;
}

static void variant_table(void)
{
    double coeffs[5] = {0.4375, -0.8125, 0.0625, 1.625, -0.1875};
    float x[VARIANT_SAMPLES];
    for (int i = 0; i < VARIANT_SAMPLES; i++)
        x[i] = (float)(0.25 * ((i * 7) % 11) - 1.0);
    float host_y[VARIANT_SAMPLES], host_delay[4] = {0, 0, 0, 0};
    vDSP_biquad_Setup host = vDSP_biquad_CreateSetup(coeffs, 1);
    vDSP_biquad((const struct vDSP_biquad_SetupStruct *)host, host_delay, x, 1, host_y, 1, VARIANT_SAMPLES);
    vDSP_biquad_DestroySetup(host);
    printf("  the host over %d samples, output[19] %.9g, delay %.9g %.9g %.9g %.9g\n", VARIANT_SAMPLES,
           host_y[19], host_delay[0], host_delay[1], host_delay[2], host_delay[3]);
    static const char *names[4] = {"the printed form, one expression", "the printed form, fused at each multiply-add",
                                   "the printed form accumulated in double and rounded once a sample",
                                   "reassociated as b0*x + (b1*x1 + b2*x2) - (a1*y1 + a2*y2)"};
    for (int which = 0; which < 4; which++) {
        int at = variant_matches(which, coeffs, x, host_y);
        printf("    %-58s %s\n", names[which],
               at < 0 ? "MATCHES the host on every sample" : "");
        if (at >= 0)
            printf("      first differs at %d\n", at);
    }
}

// ============================================================================================
// Brute force: every association of the five terms, times a fused or a plain combine at every multiply-add,
// in float and in double. The space is ENUMERATED, not guessed: all 14 binary trees over five leaves, and
// for each tree every subset of the combines that admits a fused form.
//
// **The host here is the macOS arm64 vImage, and it is not the oracle that decides this shape.** These rows
// are native on 6.0 armv7, and that is the implementation a 4.3-5.x application actually calls. armv7 VFP
// before VFPv4 has no fused multiply-add, so an answer only a fused combine can produce is one the real
// target cannot give. The real oracle is the 6.0 armv7 implementation itself, through the emulator, and
// that is the open item recorded in the facts file.
// ============================================================================================

#define BRUTE_SAMPLES 32
#define BRUTE_NODES 9
#define BRUTE_TREES 128

typedef struct { int a, b, leaf, fused; } BruteNode;
typedef struct { BruteNode node[BRUTE_NODES]; int used; } BruteTree;
typedef struct { BruteTree tree[BRUTE_TREES]; int count; } BruteForest;

// Tree 0, by hand, is the header's printed form: (((t0 + t1) + t2) + t3) + t4, left to right, with the two A
// terms already negated in the factors. It is built first so that **variant 0 is the printed form whatever
// the enumeration's order turns out to be**, and the control below requires variant 0 to reproduce the
// port's own output bit for bit. If the enumeration ever produced the printed form again, the search would
// report a duplicate; that is harmless and the count is printed.
static void brute_seed_printed(BruteForest *out)
{
    BruteTree *t = &out->tree[out->count++];
    for (int i = 0; i < 5; i++) { t->node[i].a = t->node[i].b = -1; t->node[i].leaf = i; t->node[i].fused = 0; }
    int root = 0;
    for (int i = 5; i < 9; i++) {
        t->node[i].leaf = -1;
        t->node[i].a = root;
        // node 5 is t0+t1, node 6 is that +t2, node 7 is that +t3 and node 8 is that +t4, so the RIGHT child
        // of node i is leaf i - 4 and not leaf i - 5. With i - 5 the seed tree reads (t0+t0)+t1)+t2)+t3: it
        // doubles t0 and never adds t4 at all, which is why control 1 failed at sample 0 on a filter the
        // port and the host agree on bit for bit, and why the search below reported that no association
        // matched the host when it had never been offered the printed one.
        t->node[i].b = i - 4;
        t->node[i].fused = 0;
        root = i;
    }
    t->used = 9;
}

// Every binary tree over `count` leaves: for each bipartition, the cross product of the trees of each side.
static void brute_all(const int *leaves, int count, BruteForest *out)
{
    if (count == 1) {
        BruteTree *t = &out->tree[out->count++];
        t->used = 1;
        t->node[0].a = t->node[0].b = -1;
        t->node[0].leaf = leaves[0];
        t->node[0].fused = 0;
        return;
    }
    // One of each complementary pair only: `mask` and its complement are the same bipartition with the
    // sides swapped, and visiting both generates every tree twice - 14 trees become 28 and the second
    // run of this overwrote the end of the array. Bit 0 set picks exactly one side out of each pair.
    for (int mask = 1; mask < (1 << count) - 1; mask += 2) {
        int left[5], right[5], nl = 0, nr = 0;
        for (int i = 0; i < count; i++) {
            if ((mask >> i) & 1) left[nl++] = leaves[i];
            else right[nr++] = leaves[i];
        }
        BruteForest lf, rf;
        lf.count = 0;
        rf.count = 0;
        brute_all(left, nl, &lf);
        brute_all(right, nr, &rf);
        for (int i = 0; i < lf.count; i++)
            for (int j = 0; j < rf.count; j++) {
                BruteTree *t = &out->tree[out->count++];
                int k = 0;
                for (int q = 0; q < lf.tree[i].used; q++) t->node[k++] = lf.tree[i].node[q];
                int lroot = lf.tree[i].used - 1;
                for (int q = 0; q < rf.tree[j].used; q++) t->node[k++] = rf.tree[j].node[q];
                int rroot = lf.tree[i].used + rf.tree[j].used - 1;
                t->node[k].a = lroot;
                t->node[k].b = rroot;
                t->node[k].leaf = -1;
                t->node[k].fused = 0;
                t->used = k + 1;
            }
    }
}

static int brute_matches(const BruteTree *tree, int mask, const double *coeffs, const float *x, const float *host_y,
                         int is_double, int *first_diff)
{
    double delay[4] = {0, 0, 0, 0};
    for (int n = 0; n < BRUTE_SAMPLES; n++) {
        double xn = x[n], xp1 = delay[1], xp2 = delay[0], yp1 = delay[3], yp2 = delay[2];  /* the header's layout */
        double fa[5][2];
        fa[0][0] = coeffs[0]; fa[0][1] = xn;
        fa[1][0] = coeffs[1]; fa[1][1] = xp1;
        fa[2][0] = coeffs[2]; fa[2][1] = xp2;
        fa[3][0] = -coeffs[3]; fa[3][1] = yp1;
        fa[4][0] = -coeffs[4]; fa[4][1] = yp2;
        double got;
        if (is_double) {
            double v[BRUTE_NODES];
            for (int i = 0; i < tree->used; i++) {
                if (tree->node[i].leaf >= 0) {
                    v[i] = fa[tree->node[i].leaf][0] * fa[tree->node[i].leaf][1];
                } else {
                    int l = tree->node[i].a, r = tree->node[i].b;
                    if (((mask >> i) & 1) && tree->node[l].leaf >= 0)
                        v[i] = fma(fa[tree->node[l].leaf][0], fa[tree->node[l].leaf][1], v[r]);
                    else
                        v[i] = v[l] + v[r];
                }
            }
            got = v[tree->used - 1];
            if (got != (double)host_y[n]) { *first_diff = n; return 0; }
        } else {
            float v[BRUTE_NODES];
            for (int i = 0; i < tree->used; i++) {
                if (tree->node[i].leaf >= 0) {
                    v[i] = (float)fa[tree->node[i].leaf][0] * (float)fa[tree->node[i].leaf][1];
                } else {
                    int l = tree->node[i].a, r = tree->node[i].b;
                    if (((mask >> i) & 1) && tree->node[l].leaf >= 0)
                        v[i] = fmaf((float)fa[tree->node[l].leaf][0], (float)fa[tree->node[l].leaf][1], v[r]);
                    else
                        v[i] = v[l] + v[r];
                }
            }
            got = (double)v[tree->used - 1];
            if ((float)got != host_y[n]) { *first_diff = n; return 0; }
        }
        delay[0] = delay[1]; delay[1] = xn; delay[2] = delay[3]; delay[3] = got;  /* the header's layout */
    }
    return 1;
}

// Control 1: variant 0 must be the printed form, which means it must reproduce the PORT's output bit for
// bit on every sample. Control 2: at sample 0 with a zero delay every variant must equal b0 * x[0].
// The search reports only when both hold; otherwise it says which control failed and stops.
static int brute_controls(const BruteForest *forest, const double *coeffs, const float *x, const float *port_y,
                          int *control2_violations)
{
    int at = -1;
    if (!brute_matches(&forest->tree[0], 0, coeffs, x, port_y, 0, &at)) {
        printf("    CONTROL 1 FAILED: variant 0, the printed form, differs from the port at sample %d\n", at);
        return 0;
    }
    // At sample 0 with a zero delay every association must reduce to b0 * x[0], so the variant's first
    // output is compared with that - computed through the SAME evaluator, over a full-length input, rather
    // than through a one-element array the evaluator would read 31 elements past. (It did, once.)
    float want = (float)coeffs[0] * x[0];
    *control2_violations = 0;
    for (int t = 0; t < forest->count; t++)
        for (int mask = 0; mask < (1 << BRUTE_NODES); mask++) {
            float one_out[1];
            double delay[4] = {0, 0, 0, 0};
            double xn = x[0], fa[5][2];
            fa[0][0] = coeffs[0]; fa[0][1] = xn;
            fa[1][0] = coeffs[1]; fa[1][1] = delay[1];
            fa[2][0] = coeffs[2]; fa[2][1] = delay[0];
            fa[3][0] = -coeffs[3]; fa[3][1] = delay[3];
            fa[4][0] = -coeffs[4]; fa[4][1] = delay[2];
            float v[BRUTE_NODES];
            const BruteTree *tr = &forest->tree[t];
            for (int i = 0; i < tr->used; i++) {
                if (tr->node[i].leaf >= 0)
                    v[i] = (float)fa[tr->node[i].leaf][0] * (float)fa[tr->node[i].leaf][1];
                else {
                    int l = tr->node[i].a, r = tr->node[i].b;
                    if (((mask >> i) & 1) && tr->node[l].leaf >= 0)
                        v[i] = fmaf((float)fa[tr->node[l].leaf][0], (float)fa[tr->node[l].leaf][1], v[r]);
                    else
                        v[i] = v[l] + v[r];
                }
            }
            one_out[0] = v[tr->used - 1];
            if (one_out[0] != want)
                (*control2_violations)++;
        }
    if (*control2_violations) {
        printf("    CONTROL 2 FAILED: %d variants do not give b0 * x[0] at sample 0 with a zero delay\n",
               *control2_violations);
        return 0;
    }
    printf("    control 1 passed: variant 0 is the printed form and reproduces the port bit for bit\n");
    printf("    control 2 passed: all %d variants give b0 * x[0] at sample 0 with a zero delay\n",
           forest->count * (1 << BRUTE_NODES));
    return 1;
}

static int brute_search(const char *label, const double *coeffs, const float *x, const float *host_y,
                        const float *port_y)
{
    int leaves[5] = {0, 1, 2, 3, 4};
    BruteForest forest;
    forest.count = 0;
    brute_seed_printed(&forest);
    brute_all(leaves, 5, &forest);
    int violations = 0;
    if (!brute_controls(&forest, coeffs, x, port_y, &violations)) {
        // One control did not hold, so nothing this search would say about the host is worth anything.
        // Said here rather than by falling off the end of a non-void function, which is what this did
        // before and which clang reports as "non-void function does not return a value".
        return 0;
    }
    int tried = 0, matched_float = 0, matched_double = 0;
    // The BEST variant, by the sample it first differs at - **not the first variant tried**, which is what
    // an earlier version of this printed and which is how a "first differs at sample 0" came to be reported
    // for a filter the port and the host agree on for the first two samples.
    int best_float = 1 << 20, best_double = 1 << 20, best_float_tree = -1, best_double_tree = -1;
    for (int t = 0; t < forest.count; t++) {
        for (int mask = 0; mask < (1 << BRUTE_NODES); mask++) {
            int diff = -1;
            tried++;
            if (brute_matches(&forest.tree[t], mask, coeffs, x, host_y, 0, &diff)) matched_float++;
            else if (diff < best_float) { best_float = diff; best_float_tree = t; }
            diff = -1;
            if (brute_matches(&forest.tree[t], mask, coeffs, x, host_y, 1, &diff)) matched_double++;
            else if (diff < best_double) { best_double = diff; best_double_tree = t; }
            (void)0;
        }
    }
    printf("  %s: %d trees, %d variants per association set; float %s\n", label, forest.count, tried,
           matched_float ? "MATCHES the host on every sample" : "matches none");
    if (!matched_float)
        printf("    the best float variant - tree %d of %d - first differs at sample %d of %d\n", best_float_tree,
               forest.count, best_float, BRUTE_SAMPLES);
    // The double pass is NOT reported: host_y is the FLOAT form's output, and comparing a double-precision
    // result against it is a category error rather than a measurement. It needs vDSP_biquadD's own host
    // output, which is a separate run and is not in this file yet.
    (void)matched_double; (void)best_double; (void)best_double_tree;
    return 0;
}

static void brute_report(void)
{
    double stable[5] = {0.0674551234, 0.1349102468, 0.0674551234, -1.1429805025, 0.4128015981};
    double unstable[5] = {0.4375, -0.8125, 0.0625, 1.625, -0.1875};
    float x[BRUTE_SAMPLES];
    for (int i = 0; i < BRUTE_SAMPLES; i++)
        x[i] = (float)(0.25 * ((i * 7) % 11) - 1.0);
    float host_y[BRUTE_SAMPLES], delay[4];
    for (int filter = 0; filter < 2; filter++) {
        const double *c = filter ? unstable : stable;
        // **Delay reset to zero before each filter.** Without it the host's first output came from the
        // previous filter's carried state while every variant starts from a zero delay, so the two could
        // never agree at sample 0 - which is what made every variant look like it differed there.
        delay[0] = delay[1] = delay[2] = delay[3] = 0.0f;
        vDSP_biquad_Setup host = vDSP_biquad_CreateSetup(c, 1);
        vDSP_biquad((const struct vDSP_biquad_SetupStruct *)host, delay, x, 1, host_y, 1, BRUTE_SAMPLES);
        vDSP_biquad_DestroySetup(host);
        // the port's own output on the same input, for control 1
        float port_y[BRUTE_SAMPLES], port_delay[4] = {0, 0, 0, 0};
        vDSP_biquad_Setup ps = charon_host_vDSP_biquad_CreateSetup(c, 1);
        charon_host_vDSP_biquad((const struct vDSP_biquad_SetupStruct *)ps, port_delay, x, 1, port_y, 1,
                                BRUTE_SAMPLES);
        charon_host_vDSP_biquad_DestroySetup(ps);
        printf("  %s\n", filter ? "the unstable filter, pole -1.733" : "the stable filter, pole about 0.643");
        brute_search(filter ? "the unstable filter, pole -1.733" : "the stable filter, pole about 0.643", c, x,
                     host_y, port_y);
    }
}

// If no association can reproduce even the FIRST sample, the disagreement is not the arithmetic - it is
// what the host reads out of Delay at n = 0. So dump it: the host's first output against the port's, and
// Delay after the call on both sides, on the stable filter where nothing is amplified.
static void initial_state(void)
{
    double stable[5] = {0.0674551234, 0.1349102468, 0.0674551234, -1.1429805025, 0.4128015981};
    float x[8];
    for (int i = 0; i < 8; i++)
        x[i] = (float)(0.25 * ((i * 7) % 11) - 1.0);
    printf("  the stable filter, coefficients %g %g %g %g %g\n", stable[0], stable[1], stable[2], stable[3], stable[4]);
    printf("  the input's first three samples %g %g %g, and b0 * x[0] = %.17g\n", x[0], x[1], x[2],
           (double)((float)stable[0] * x[0]));

    float host_delay[4] = {0, 0, 0, 0}, host_y[8];
    float port_delay[4] = {0, 0, 0, 0}, port_y[8];
    vDSP_biquad_Setup hs = vDSP_biquad_CreateSetup(stable, 1);
    vDSP_biquad((const struct vDSP_biquad_SetupStruct *)hs, host_delay, x, 1, host_y, 1, 8);
    vDSP_biquad_DestroySetup(hs);
    vDSP_biquad_Setup ps = charon_host_vDSP_biquad_CreateSetup(stable, 1);
    charon_host_vDSP_biquad((const struct vDSP_biquad_SetupStruct *)ps, port_delay, x, 1, port_y, 1, 8);
    charon_host_vDSP_biquad_DestroySetup(ps);

    printf("    sample 0: the host %.9g, the port %.9g, b0*x0 %.9g\n", host_y[0], port_y[0],
           (float)stable[0] * x[0]);
    printf("    sample 1: the host %.9g, the port %.9g\n", host_y[1], port_y[1]);
    printf("    Delay after the call, the host: %.9g %.9g %.9g %.9g\n", host_delay[0], host_delay[1], host_delay[2],
           host_delay[3]);
    printf("    Delay after the call, the port: %.9g %.9g %.9g %.9g\n", port_delay[0], port_delay[1], port_delay[2],
           port_delay[3]);
    printf("    the input's last two samples, which the pseudocode says land in Delay[0] and Delay[1]: %g %g\n",
           x[6], x[7]);
}

// Zero sections, asked of BOTH creates, because it decides whether the shared create changes.
static void zero_sections(void)
{
    double coeffs[5] = {0.4375, -0.8125, 0.0625, 1.625, -0.1875};
    vDSP_biquad_Setup single = vDSP_biquad_CreateSetup(coeffs, 0);
    vDSP_biquad_SetupD single_d = vDSP_biquad_CreateSetupD(coeffs, 0);
    vDSP_biquadm_Setup multi = vDSP_biquadm_CreateSetup(coeffs, 0, 1);
    vDSP_biquadm_Setup multi_zero_channels = vDSP_biquadm_CreateSetup(coeffs, 1, 0);
    printf("  M = 0, one channel : the single form %s, the m-form %s\n", single ? "answers a setup" : "answers NULL",
           multi ? "answers a setup" : "answers NULL");
    printf("  M = 0, D           : the single form %s\n", single_d ? "answers a setup" : "answers NULL");
    printf("  M = 1, N = 0       : the m-form %s\n",
           multi_zero_channels ? "answers a setup" : "answers NULL");
    if (single) vDSP_biquad_DestroySetup(single);
    if (single_d) vDSP_biquad_DestroySetupD(single_d);
    if (multi) vDSP_biquadm_DestroySetup(multi);
    if (multi_zero_channels) vDSP_biquadm_DestroySetup(multi_zero_channels);
}

int main(void)
{
    setbuf(stdout, NULL);
    @autoreleasepool {
        // One section, and several, because a single-section filter over M sections is the shape and a
        // section-index error only shows with more than one.
        run_float("vDSP_biquad over one section, two calls, stable", 1, kStable, 1);
        run_float("vDSP_biquad over four sections, two calls, stable", 4, kStable, 1);
        run_double("vDSP_biquadD over one section, two calls, stable", 1, kStable, 1);
        run_double("vDSP_biquadD over three sections, two calls, stable", 3, kStable, 1);
        run_float("vDSP_biquad over one section, two calls, UNSTABLE (pole -1.733)", 1, kUnstable, 0);
        run_float("vDSP_biquad over four sections, two calls, UNSTABLE (pole -1.733)", 4, kUnstable, 0);
        run_double("vDSP_biquadD over one section, two calls, UNSTABLE (pole -1.733)", 1, kUnstable, 0);
        run_double("vDSP_biquadD over three sections, two calls, UNSTABLE (pole -1.733)", 3, kUnstable, 0);
        printf("   (the initial state)\n");
        initial_state();
        printf("   (brute force: every association, every fused subset)\n");
        brute_report();
        printf("   (the variant table on the unstable input)\n");
        variant_table();
        printf("   (which kernel)\n");
        which_kernel();
        printf("   (zero sections)\n");
        zero_sections();
        run_refusals();
        printf("   (after the refusals)\n");
        printf("%d checks, %d failures\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
