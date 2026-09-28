// Check the split on N = 4 by hand, as the coordinator required: a direct-sum reference in the TEST, and the
// split applied to the port's verified complex forward, printed side by side for X_0 .. X_4.
#include <Accelerate/Accelerate.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define N 8
#define NS (2 * N)

static void cmul(double ar, double ai, double br, double bi, double *r, double *i)
{ *r = ar * br - ai * bi; *i = ar * bi + ai * br; }
static void cdiv2i(double ar, double ai, double *r, double *i)   /* (a) / 2i */
{ *r = ai / 2.0; *i = -ar / 2.0; }

int main(void)
{
    setbuf(stdout, NULL);
    double x[NS] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
    printf("N = %d, a real signal of %d samples: ", N, NS);
    for (int i = 0; i < NS; i++) printf("%g ", x[i]);
    printf("\n\n");

    // 1. the direct-sum reference, in the TEST: the naive DFT of the 8 real samples
    double Xr[NS], Xi[NS];
    for (int k = 0; k < NS; k++) {
        double re = 0, im = 0;
        for (int j = 0; j < NS; j++) {
            double a = -2.0 * M_PI * (double)k * (double)j / (double)NS;
            re += x[j] * cos(a); im += x[j] * sin(a);
        }
        Xr[k] = re; Xi[k] = im;
    }
    printf("X_0 .. X_8 by direct sum (the reference):\n");
    for (int k = 0; k <= N; k++) printf("  X_%d = %12.8f %+12.8fi\n", k, Xr[k], Xi[k]);

    // 2. pack z, run the release's complex forward of length N, split
    DSPComplex in[N], out[N];
    for (int n = 0; n < N; n++) { in[n].real = (float)x[2 * n]; in[n].imag = (float)x[2 * n + 1]; }
    vDSP_DFT_Interleaved_Setup s = vDSP_DFT_Interleaved_CreateSetup(NULL, N, vDSP_DFT_FORWARD, vDSP_DFT_Interleaved_ComplextoComplex);
    if (!s) { printf("no setup: N = %d is NOT in the accepted set\n", N); return 1; }
    vDSP_DFT_Interleaved_Execute(s, in, out);
    printf("\nthe complex forward of length N gives Z_0 .. Z_%d:\n", N - 1);
    for (int k = 0; k < N; k++) printf("  Z_%d = %12.8f %+12.8fi\n", k, out[k].real, out[k].imag);

    printf("\nX_0 .. X_8 from the split, and the direct sum beside it:\n");
    double Sr[N + 1], Si[N + 1];
    for (int k = 0; k < N; k++) {
        int m = (k == 0) ? 0 : N - k;                 /* Z_N is taken as Z_0 */
        double Zr = out[k].real, Zi = out[k].imag;
        double cr = out[m].real, ci = -out[m].imag;   /* conj Z_{N-k} */
        double er = (Zr + cr) / 2.0, ei = (Zi + ci) / 2.0;
        double or, oi;
        cdiv2i(Zr - cr, Zi - ci, &or, &oi);
        double w = -M_PI * (double)k / (double)N;     /* e^{-i*pi*k/N} */
        double pr, pi_;
        cmul(or, oi, cos(w), sin(w), &pr, &pi_);
        Sr[k] = er + pr; Si[k] = ei + pi_;
    }
    {   /* X_N = E_0 - O_0, which is real */
        double Zr = out[0].real, Zi = out[0].imag;
        double er = Zr, ei = 0.0;                      /* E_0 = (Z_0 + conj Z_0)/2 = Re Z_0 */
        double or, oi;
        cdiv2i(Zr - Zr, Zi + Zi, &or, &oi);           /* O_0 = (Z_0 - conj Z_0)/(2i) = Im Z_0 */
        Sr[N] = er - or; Si[N] = ei - oi;
    }
    int worst = 0; double worst_gap = 0;
    for (int k = 0; k <= N; k++) {
        double gap = fabs(Sr[k] - Xr[k]) + fabs(Si[k] - Xi[k]);
        if (gap > worst_gap) { worst_gap = gap; worst = k; }
        printf("  X_%d  split %12.8f %+12.8fi   direct %12.8f %+12.8fi   gap %.3e\n",
               k, Sr[k], Si[k], Xr[k], Xi[k], gap);
    }
    printf("\n  the largest gap is at X_%d, %.3e - the split %s the direct sum\n", worst, worst_gap,
           worst_gap < 1e-9 ? "IS" : "does NOT match");
    vDSP_DFT_Interleaved_DestroySetup(s);
    return 0;
}
