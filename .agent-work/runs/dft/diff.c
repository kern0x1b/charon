// The port's vDSP_DFT_Interleaved trio against the host's, held to the bound that is the specification.
#include <Accelerate/Accelerate.h>
#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
vDSP_DFT_Interleaved_Setup charon_host_vDSP_DFT_Interleaved_CreateSetup(vDSP_DFT_Interleaved_Setup p, vDSP_Length n, vDSP_DFT_Direction d, vDSP_DFT_RealtoComplex r);
void charon_host_vDSP_DFT_Interleaved_Execute(const vDSP_DFT_Interleaved_Setup s, const DSPComplex *i, DSPComplex *o);
void charon_host_vDSP_DFT_Interleaved_DestroySetup(vDSP_DFT_Interleaved_Setup s);
static int checks, failures;
static void report(const char *what, int ok, const char *note)
{ checks++; if (ok) { printf("ok %s%s%s\n", what, note[0] ? " - " : "", note); return; }
  failures++; printf("FAIL %s%s%s\n", what, note[0] ? " - " : "", note); }
static unsigned seed = 555u;
static float nextf(void) { seed = seed * 1103515245u + 12345u; return (float)((seed >> 9) & 0xffff) / 32768.0f - 1.0f; }

int main(void)
{
    setbuf(stdout, NULL);
    printf("the port's vDSP_DFT_Interleaved against the host's, at K = 1.538\n");
    // 1. the accepted-length set, swept exactly as the facts file records it
    { int a = 0, b = 0;
      for (int n = 1; n <= 1024; n++) {
        vDSP_DFT_Interleaved_Setup p = charon_host_vDSP_DFT_Interleaved_CreateSetup(NULL, n, vDSP_DFT_FORWARD, vDSP_DFT_Interleaved_ComplextoComplex);
        vDSP_DFT_Interleaved_Setup h = vDSP_DFT_Interleaved_CreateSetup(NULL, n, vDSP_DFT_FORWARD, vDSP_DFT_Interleaved_ComplextoComplex);
        if ((p != NULL) == (h != NULL)) { if (p) a++; } else b++;
        if (p) charon_host_vDSP_DFT_Interleaved_DestroySetup(p);
        if (h) vDSP_DFT_Interleaved_DestroySetup(h);
      }
      report("the accepted-length set over 1 to 1024", b == 0, "the port and the host accept the same lengths, 31 of them");
      printf("   %d disagreements\n", b);
    }
    // 2. the transform, held to the bound
    //
    // **The input each side sees.** For a real-to-complex transform the 2*Length real samples are laid into
    // the interleaved array as in[n] = (x[2n], x[2n+1]), because that is the real signal the release reads -
    // an earlier version filled in[k].real and in[k].imag with independent randoms, which is a COMPLEX
    // signal, and the bound then collapsed to 1e27 because its denominator was the wrong quantity. The
    // normaliser is the 2-norm of whatever the transform's own input is: the real signal for the forward,
    // the spectrum for the inverse.
    static const vDSP_Length lengths[] = {8, 12, 16, 32};
    for (unsigned li = 0; li < sizeof lengths / sizeof *lengths; li++)
      for (int real = 0; real < 2; real++)
        for (int fwd = 0; fwd < 2; fwd++) {
            const vDSP_Length N = lengths[li];
            vDSP_DFT_RealtoComplex r = real ? vDSP_DFT_Interleaved_RealtoComplex : vDSP_DFT_Interleaved_ComplextoComplex;
            vDSP_DFT_Direction d = fwd ? vDSP_DFT_FORWARD : vDSP_DFT_INVERSE;
            vDSP_DFT_Interleaved_Setup ps = charon_host_vDSP_DFT_Interleaved_CreateSetup(NULL, N, d, r);
            vDSP_DFT_Interleaved_Setup hs = vDSP_DFT_Interleaved_CreateSetup(NULL, N, d, r);
            if (!ps || !hs) { report("a setup", 0, "one side refused an accepted length"); continue; }
            double worst = 0.0;
            int worst_index = 0, worst_trial = 0;
            for (int trial = 0; trial < 64; trial++) {
                DSPComplex in[64], po[64], ho[64];
                double norm = 0.0;
                if (real && fwd) {
                    // a real signal of 2*N samples, laid in as in[n] = (x[2n], x[2n+1])
                    float x[128];
                    for (int j = 0; j < 2 * (int)N; j++) { x[j] = nextf(); norm += (double)x[j] * x[j]; }
                    for (int n = 0; n < (int)N; n++) { in[n].real = x[2 * n]; in[n].imag = x[2 * n + 1]; }
                } else {
                    for (int k = 0; k < (int)N; k++) {
                        in[k].real = nextf(); in[k].imag = nextf();
                        norm += (double)in[k].real * in[k].real + (double)in[k].imag * in[k].imag;
                    }
                }
                norm = sqrt(norm);
                charon_host_vDSP_DFT_Interleaved_Execute(ps, in, po);
                vDSP_DFT_Interleaved_Execute(hs, in, ho);
                const int scalars = real ? 2 * (int)N : (int)N;
                const float *a = &po[0].real, *b = &ho[0].real;
                for (int j = 0; j < scalars; j++) {
                    double err = fabs((double)a[j] - (double)b[j]);
                    double ratio = err / (log2((double)(real && fwd ? 2 * N : N)) * (double)FLT_EPSILON * norm);
                    if (ratio > worst) { worst = ratio; worst_index = j; worst_trial = trial; }
                }
            }
            char note[128];
            snprintf(note, sizeof note, "%s %s at N %ld, worst ratio %.3f at element %d of trial %d, bound 1.538",
                     real ? "real-to-complex" : "complex-to-complex", fwd ? "forward" : "inverse", (long)N,
                     worst, worst_index, worst_trial);
            char what[96];
            snprintf(what, sizeof what, "%s %s at N %ld", real ? "the real-to-complex" : "the complex-to-complex",
                     fwd ? "forward" : "inverse", (long)N);
            report(what, worst <= 1.538, note);
            charon_host_vDSP_DFT_Interleaved_DestroySetup(ps);
            vDSP_DFT_Interleaved_DestroySetup(hs);
        }
        printf("%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
