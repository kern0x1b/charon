// differential.m - the port's CGAffineTransformDecompose and CGAffineTransformMakeWithComponents, held to the host's own
// CoreGraphics on the battery below. The port's source is linked in with its two functions renamed (run.sh), so both
// stand in one process. Three checks per transform: the components the two answer for the same matrix, the matrix the
// port rebuilds from its own components, and the matrix each answers for the host's components.
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

CGAffineTransformComponents CharonHostDecompose(CGAffineTransform transform);
CGAffineTransform CharonHostMakeWithComponents(CGAffineTransformComponents components);

static int checks, failures;
static double worst;

// Two numbers agree when they differ by at most 1e-12 of their size (or of 1 for a size below 1). The host's own
// rounding of a cosine or a sine is the reason a zero can come back as 1e-16: the bound is what the battery measures.
static int agree(double host, double port)
{
    double size = fabs(host) > 1 ? fabs(host) : 1;
    double error = fabs(host - port) / size;
    if (error > worst)
        worst = error;
    return error <= 1e-12;
}

static void report(const char *label, const char *what, int ok)
{
    checks++;
    if (!ok)
        failures++;
    printf("%s %s: %s\n", ok ? "ok  " : "FAIL", label, what);
}

static int same_components(CGAffineTransformComponents h, CGAffineTransformComponents p)
{
    return agree(h.scale.width, p.scale.width) && agree(h.scale.height, p.scale.height)
        && agree(h.horizontalShear, p.horizontalShear) && agree(h.rotation, p.rotation)
        && agree(h.translation.dx, p.translation.dx) && agree(h.translation.dy, p.translation.dy);
}

static int same_matrix(CGAffineTransform h, CGAffineTransform p)
{
    return agree(h.a, p.a) && agree(h.b, p.b) && agree(h.c, p.c) && agree(h.d, p.d)
        && agree(h.tx, p.tx) && agree(h.ty, p.ty);
}

static void battery(const char *label, double a, double b, double c, double d, double tx, double ty)
{
    CGAffineTransform m = CGAffineTransformMake(a, b, c, d, tx, ty);
    CGAffineTransformComponents hc = CGAffineTransformDecompose(m);
    CGAffineTransformComponents pc = CharonHostDecompose(m);
    report(label, "decompose agrees with the host", same_components(hc, pc));
    report(label, "the port's components rebuild the matrix as the host's do",
           same_matrix(CGAffineTransformMakeWithComponents(pc), CharonHostMakeWithComponents(pc)));
    /* A singular transform with two rows that are not zero does not come back from its components: the host does
       not either, so the round trip is held only where the determinant is not zero. */
    if (fabs(a * d - b * c) > 1e-9 * (fabs(a * d) + fabs(b * c)))
        report(label, "the port's components rebuild the matrix", same_matrix(m, CGAffineTransformMakeWithComponents(pc)));
    report(label, "port builds the host's matrix from the host's components",
           same_matrix(CGAffineTransformMakeWithComponents(hc), CharonHostMakeWithComponents(hc)));
}

/* Generated transforms, held on the decomposition alone: a deterministic generator (a 64-bit linear congruence), so the
   same transforms come out on every run. A singular one has its second row a multiple of the first, rounded. */
static uint64_t seed = 20261016;

static double next_unit(void)
{
    seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
    return ((double)(seed >> 11) / 9007199254740992.0) * 2 - 1;
}

static void sweep(const char *label, int singular, int count)
{
    int disagreeing = 0;
    for (int index = 0; index < count; index++) {
        double scale = pow(10, (double)(index % 7) - 3);
        double a = next_unit() * scale, b = next_unit() * scale, c, d;
        if (singular) {
            double multiple = next_unit() * 4;
            c = multiple * a;
            d = multiple * b;
        } else {
            c = next_unit() * scale;
            d = next_unit() * scale;
        }
        CGAffineTransform m = CGAffineTransformMake(a, b, c, d, 0, 0);
        if (!same_components(CGAffineTransformDecompose(m), CharonHostDecompose(m)))
            disagreeing++;
    }
    report(label, disagreeing ? "some decompositions disagree with the host" : "every decomposition agrees with the host",
           disagreeing == 0);
}

int main(void)
{
    double s30 = sin(M_PI / 6), c30 = cos(M_PI / 6);
    double s45 = sin(-M_PI / 4), c45 = cos(-M_PI / 4);
    battery("identity", 1, 0, 0, 1, 0, 0);
    battery("translate", 1, 0, 0, 1, 5, -7);
    battery("scale", 2, 0, 0, 3, 0, 0);
    battery("negx", -2, 0, 0, 3, 0, 0);
    battery("negy", 2, 0, 0, -3, 0, 0);
    battery("negboth", -2, 0, 0, -3, 0, 0);
    battery("flipx", -1, 0, 0, 1, 0, 0);
    battery("flipy", 1, 0, 0, -1, 0, 0);
    battery("rot30", c30, s30, -s30, c30, 0, 0);
    battery("rot90", 0, 1, -1, 0, 0, 0);
    battery("rot180", -1, 0, 0, -1, 0, 0);
    battery("rot-45", c45, -s45, s45, c45, 0, 0);
    battery("rotscale", 2 * c30, 2 * s30, -3 * s30, 3 * c30, 1, 2);
    battery("shear", 1, 0, 0.5, 1, 0, 0);
    battery("swap", 0, 1, 1, 0, 0, 0);
    battery("zero", 0, 0, 0, 0, 0, 0);
    battery("degen", 0, 0, 1, 1, 0, 0);
    battery("degen2", 0, 0, 0, 2, 3, 4);
    battery("d-neg", 0, 0, 0, -2, 0, 0);
    battery("c1d-neg", 0, 0, 1, -1, 0, 0);
    battery("rank1a", 1, 0, 0, 0, 0, 0);
    battery("rank1neg", -1, 0, 0, 0, 0, 0);
    battery("rank1c", 0, 1, 0, 0, 0, 0);
    battery("rank1d", 0, -1, 0, 0, 0, 0);
    battery("negdet", 0, 2, 3, 0, 0, 0);
    battery("arb", 1.3, 0.7, -0.4, 2.1, 3.5, -2.25);
    battery("arb2", -1.3, 0.7, 0.4, -2.1, 3.5, -2.25);
    battery("tiny", 1e-9, 0, 0, 1, 0, 0);
    battery("sing1", 2, 2, 1, 1, 0, 0);
    battery("sing2", 1, 2, 2, 4, 0, 0);
    battery("sing3", 3, 1, 6, 2, 0, 0);
    battery("sing4", 1, 1, 1, 1, 0, 0);
    battery("sing5", 5, -2, -10, 4, 0, 0);
    battery("sing6", 0.3, 0.7, 0.6, 1.4, 0, 0);
    battery("sing7", 1, 3, -2, -6, 0, 0);
    battery("sing8", 4, -1, -8, 2, 0, 0);
    sweep("generated singular", 1, 1000);
    sweep("generated general", 0, 1000);
    printf("%d checks, %d failures, largest relative difference %g\n", checks, failures, worst);
    return failures ? 1 : 0;
}
