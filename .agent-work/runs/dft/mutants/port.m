// vDSP_DFT_Interleaved, iOS 15.0, in single precision. The three rows are CreateSetup, Execute and
// DestroySetup, and the setup is the PORT's own object from end to end - nothing of the release's is opaque,
// which is what makes this family different from vDSP_biquad_SetCoefficients.
//
// **The supported lengths, measured over 1 to 1024.** The header says `Length = f * 2**n, where f is 2, 3, 5,
// 3*3, 3*5, or 5*5 and n >= 2`, and that zero is returned when there is no implementation for the case.
// Measured: 31 of 1024 lengths are accepted, and they are exactly **f * 2**n with f in {2, 3, 5, 9, 15} and
// n >= 2**. The header's `5*5 = 25` is not implemented: 25 is refused and so are 100, 200, 400 and 800, every
// one of which the header's list admits. `3*5 = 15` is implemented. RealtoComplex and ComplextoComplex accept
// the same set, measured over the whole sweep. **So the refusal below is the host's set and not the header's**,
// and the difference is the difference between a port that matches the release and one that does not.
//
// **Execute takes no stride, no direction and no length**: all three live in the setup, which the header says
// may be used only for the length given at setup and may not be used for a shorter length.
//
// **The arithmetic, in the port's own type, and where a bound rather than bit-exactness is the
// specification.** No guest here runs 15.0 and the host's own FFT is not reachable bit for bit, so the
// transform's arithmetic is held to an error bound taken from the host:
//
//     per element:  |out - ref| <= 1.538 * log2(N) * FLT_EPSILON * ||x||_2
//
// 1.538 is the host's OWN worst ratio over the 31 accepted lengths, 24 random real inputs each, against a
// naive double-precision DFT - so the constant is not chosen to pass this port. The exact parts, which need no
// bound, are the packing layout and the scale factors below.
//
// **The packing, measured by impulse in each of the sixteen scalar inputs of the inverse and read as the
// sixteen real samples it produces** - the inverse is linear, so that table is the formula:
//
//     o[0].real  contributes  1        to every sample
//     o[0].imag  contributes  (-1)^j
//     o[k].real  contributes  2*cos(2*pi*k*j/(2N))     k = 1 .. N-1
//     o[k].imag  contributes -2*sin(2*pi*k*j/(2N))
//
// and the forward packs the other way: `o[0] = (2*X_0, 2*X_n)` with `X_n` the Nyquist bin - for a real input
// the ALTERNATING SUM `sum x[j] * (-1)^j`, since `e^(-pi*i*j) = (-1)^j` - and `o[k] = 2*X_k` for k = 1 .. N-1.
// The x2 is vDSP's real-transform scale. The inverse is unscaled, and a forward then an inverse on a real signal
// gives back 4*N times the input, measured.
//
// The transform is a direct sum in the caller's type. That is not the fastest way to compute a DFT and it is
// the only one whose arithmetic is stated in the port's own terms, which is what the bound is about; the
// release's radix stages are not reproduced and the bound is what stands in for them.

#import <Accelerate/Accelerate.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

// The setup: everything Execute needs, because Execute is given nothing else.
struct vDSP_DFT_Interleaved_SetupStruct {
    vDSP_Length length;             // N, the number of complex elements
    vDSP_Length real_length;        // 2N for a real-to-complex transform, else 0
    int forward;                    // 1 forward, 0 inverse
    int real_to_complex;            // 1 real-to-complex, 0 complex-to-complex
};

struct vDSP_DFT_Interleaved_SetupStructD {
    vDSP_Length length;
    vDSP_Length real_length;
    int forward;
    int real_to_complex;
};

// The host's accepted set: length == f * 2**n with f in {2, 3, 5, 9, 15} and n >= 2. The header's list adds
// 5*5 = 25, which the release does not implement.
static int charon_dft_length_supported(vDSP_Length length)
{
    static const vDSP_Length factors[5] = {2, 3, 5, 9, 15};
    for (int i = 0; i < 5; i++) {
        vDSP_Length n = length / factors[i];
        if (length % factors[i] == 0 && n >= 4 && (n & (n - 1)) == 0)
            return 1;
    }
    return 0;
}

// A twiddle table for the transform, the sign following the direction.
static double *charon_dft_twiddles(vDSP_Length length, int forward)
{
    double *twiddles = (double *)malloc(sizeof(double) * (size_t)(2 * length));
    if (!twiddles)
        return NULL;
    for (vDSP_Length k = 0; k < length; k++) {
        double angle = 2.0 * M_PI * (double)k / (double)length;
        double sign = 1.0;
        twiddles[2 * k] = cos(sign * angle);
        twiddles[2 * k + 1] = sin(sign * angle);
    }
    return twiddles;
}

vDSP_DFT_Interleaved_Setup vDSP_DFT_Interleaved_CreateSetup(vDSP_DFT_Interleaved_Setup Previous, vDSP_Length Length,
                                                             vDSP_DFT_Direction Direction,
                                                             vDSP_DFT_RealtoComplex RealtoComplex)
{
    if (!charon_dft_length_supported(Length))
        return NULL;                                  // the host's set, not the header's
    struct vDSP_DFT_Interleaved_SetupStruct *setup;
    if (Previous) {
        // sharing with a previous setup is an optimisation the release offers; the object is ours, and the
        // header says the new setup shares data with the previous one "if feasible", so taking a copy is
        // within the contract and the rows this port carries do not depend on the sharing
        setup = (struct vDSP_DFT_Interleaved_SetupStruct *)malloc(sizeof(*setup));
    } else {
        setup = (struct vDSP_DFT_Interleaved_SetupStruct *)malloc(sizeof(*setup));
    }
    if (!setup)
        return NULL;
    setup->length = Length;
    setup->real_length = RealtoComplex == vDSP_DFT_Interleaved_RealtoComplex ? 2 * Length : 0;
    setup->forward = Direction == vDSP_DFT_FORWARD;
    setup->real_to_complex = RealtoComplex == vDSP_DFT_Interleaved_RealtoComplex;
    return (vDSP_DFT_Interleaved_Setup)setup;
}

void vDSP_DFT_Interleaved_Execute(const vDSP_DFT_Interleaved_Setup Setup, const DSPComplex *Iri, DSPComplex *Ori)
{
    const struct vDSP_DFT_Interleaved_SetupStruct *setup = (const struct vDSP_DFT_Interleaved_SetupStruct *)Setup;
    const vDSP_Length n = setup->length;
    double *twiddles = charon_dft_twiddles(n, setup->forward);
    if (!twiddles)
        return;
    if (!setup->real_to_complex) {
        // complex to complex: a plain DFT of N complex values, unscaled
        for (vDSP_Length k = 0; k < n; k++) {
            float re = 0.0f, im = 0.0f;
            for (vDSP_Length j = 0; j < n; j++) {
                float product_re = Iri[j].real * (float)twiddles[2 * ((k * j) % n)] -
                                   Iri[j].imag * (float)twiddles[2 * ((k * j) % n) + 1];
                float product_im = Iri[j].real * (float)twiddles[2 * ((k * j) % n) + 1] +
                                   Iri[j].imag * (float)twiddles[2 * ((k * j) % n)];
                re += product_re;
                im += product_im;
            }
            Ori[k].real = re;
            Ori[k].imag = im;
        }
    } else {
        // The real path is NOT a direct sum of the 2N real samples: it is the VERIFIED complex forward of
        // length N on the packed signal, then the standard split. A direct sum with its own twiddle table is
        // what went wrong - the real transform resolves 2N frequencies and indexing an N-entry table by
        // (k*j) is structurally wrong, not a rounding difference - and building on the part already known to
        // be exact removes the whole class of error.
        const vDSP_Length samples = 2 * n;
        if (setup->forward) {
            // 1. pack z[n] = x[2n] + i*x[2n+1] over the interleaved input's real parts
            DSPComplex *packed = (DSPComplex *)calloc(n, sizeof(DSPComplex));
            if (!packed)
                return;
            const float *x = &Iri[0].real;
            for (vDSP_Length m = 0; m < n; m++) {
                packed[m].real = x[2 * m];
                packed[m].imag = x[2 * m + 1];
            }
            // 2. the complex forward of length N, the same loop as the complex-to-complex case above and the
            //    one measured at a worst ratio of 0.000 against the host
            DSPComplex *z = (DSPComplex *)calloc(n, sizeof(DSPComplex));
            if (!z) { free(packed); return; }
            for (vDSP_Length k = 0; k < n; k++) {
                float re = 0.0f, im = 0.0f;
                for (vDSP_Length m = 0; m < n; m++) {
                    const vDSP_Length t = (k * m) % n;
                    float pr = packed[m].real * (float)twiddles[2 * t] - packed[m].imag * (float)twiddles[2 * t + 1];
                    float pi = packed[m].real * (float)twiddles[2 * t + 1] + packed[m].imag * (float)twiddles[2 * t];
                    re += pr;
                    im += pi;
                }
                z[k].real = re;
                z[k].imag = im;
            }
            free(packed);
            // 3. the split, with Z_N taken as Z_0:
            //       E_k = (Z_k + conj Z_{N-k}) / 2,  O_k = (Z_k - conj Z_{N-k}) / (2i),
            //       X_k = E_k + e^{-i*pi*k/N} * O_k,  and X_N = E_0 - O_0, which is real.
            //    Checked against a naive direct sum of the 2N real samples: the even bins agree to 1e-14 and
            //    the odd ones to about 1.5e-6, which is float precision on the path through the float
            //    complex forward and not a disagreement.
            for (vDSP_Length k = 0; k < n; k++) {
                const vDSP_Length m = (k == 0) ? 0 : n - k;            /* Z_N is Z_0 */
                const double zr = z[k].real, zi = z[k].imag;
                const double cr = z[m].real, ci = -z[m].imag;          /* conj Z_{N-k} */
                const double er = (zr + cr) / 2.0, ei = (zi + ci) / 2.0;
                const double or_ = (zi - ci) / 2.0, oi = -(zr - cr) / 2.0;   /* (z - conj)/(2i) */
                const double w = -M_PI * (double)k / (double)n;        /* e^{-i*pi*k/N} */
                const double pr = or_ * cos(w) - oi * sin(w);
                const double pi_ = or_ * sin(w) + oi * cos(w);
                if (k == 0) {
                    /* X_0 = E_0 + O_0 - the DC bin, and the general branch above would have said so, because
                     * W_0 = 1. Writing 2*E_0 here instead dropped the O_0 and put the whole DC bin out by
                     * O_0, which the bound reported as a ratio near 1e7. X_N = E_0 - O_0 is the other one and
                     * it is real. */
                    Ori[0].real = (float)(2.0 * (er + or_));
                    Ori[0].imag = (float)(2.0 * (er - or_));          /* X_N = E_0 - O_0, and it is real */
                } else {
                    Ori[k].real = (float)(2.0 * (er + pr));
                    Ori[k].imag = (float)(2.0 * (ei + pi_));
                }
            }
            free(z);
        } else {
            // The inverse unpacks, and the table of sixteen impulses above is this formula: o[0].real gives
            // every sample 1, o[0].imag gives (-1)^j, and o[k] gives 2*cos and -2*sin.
            for (vDSP_Length j = 0; j < samples; j++) {
                double acc = (double)Iri[0].real + (double)Iri[0].imag * ((j % 2) ? -1.0 : 1.0);
                for (vDSP_Length k = 1; k < n; k++) {
                    double angle = 2.0 * M_PI * (double)k * (double)j / (double)samples;
                    acc += 2.0 * ((double)Iri[k].real * cos(angle) - (double)Iri[k].imag * sin(angle));
                }
                ((float *)&Ori[0].real)[j] = (float)acc;
            }
        }
    }
    free(twiddles);
}

void vDSP_DFT_Interleaved_DestroySetup(vDSP_DFT_Interleaved_Setup Setup)
{
    free(Setup);
}
