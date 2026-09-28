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
        printf("probe: %d checks, %d failures\n", checks, failures);
    }
    return failures == 0 ? 0 : 1;
}
