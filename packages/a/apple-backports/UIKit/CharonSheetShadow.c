#include "CharonSheetShadow.h"
#include <math.h>
#include <stdlib.h>

const float charon_sheet_shadow_matrix[20] = {
    0.796875f, -0.1875f, 0.078125f, 0, 0,
    -0.09375f, 0.71875f, 0.09375f, 0, 0.015625f,
    -0.09375f, -0.1875f, 0.96875f, 0, -0.015625f,
    -0.25f, -0.5f, -0.09375f, 1, 0,
};

/* The image is 400 points on a side: the corner drawn four times (-_loadImageIfNecessary). */
static const double charon_shadow_image = 400;
static const double charon_shadow_corner_points = 200;

/* _UIPopoverShadow is an image, not a formula; its alpha is two blurred rounded quadrants laid over each other,
   alpha = 1 - (1 - k1 G(s1) * Q(e1, r1)) (1 - k2 G(s2) * Q(e2, r2)), with Q the quadrant x >= e, y >= e (points from the
   outer edge) whose corner has the radius r, and G(s) a Gaussian blur of s points. The values are fitted to the host's
   image (Mac Catalyst, macOS 27, 400 x 400 pixels at scale 2; tests/backports/host/sheetshadow holds the generated
   corner to it pixel by pixel). */
typedef struct {
    double k, e, s, r;
} CharonShadowTerm;

static const CharonShadowTerm charon_shadow_terms[2] = {
    {0.4874, 83.3059, 34.0324, 37.7051},
    {0.9917, 132.5797, 21.4618, 3.8867},
};

static double charon_phi(double x)
{
    return 0.5 * erfc(-x / M_SQRT2);
}

static double charon_clamp01(double x)
{
    return x < 0 ? 0 : x > 1 ? 1 : x;
}

/* One term at n pixels per side: the blurred quadrant is the product of two blurred edges, less the blur of what the
   rounded corner cuts off (the r x r square outside the arc). That cut-off is blurred along x exactly, one thin row at
   a time, and the rows, gathered per pixel row, along y. */
static void charon_shadow_term(const CharonShadowTerm *t, size_t n, double scale, double *out)
{
    double *edge = malloc(n * sizeof(double));
    for (size_t i = 0; i < n; i++)
        edge[i] = charon_phi(((i + 0.5) / scale - t->e) / t->s);
    size_t first = (size_t)floor(t->e * scale), last = (size_t)ceil((t->e + t->r) * scale);
    if (last > n)
        last = n;
    size_t rows = last > first ? last - first : 0;
    double *cut = calloc(rows * n + 1, sizeof(double));
    const int steps = 8;
    for (size_t j = 0; j < rows; j++)
        for (int q = 0; q < steps; q++) {
            double y = (first + j + (q + 0.5) / steps) / scale, dy = y - (t->e + t->r);
            if (y < t->e || y > t->e + t->r)
                continue;
            double end = t->e + t->r - sqrt(t->r * t->r - dy * dy);
            for (size_t i = 0; i < n; i++)
                cut[j * n + i] += (edge[i] - charon_phi(((i + 0.5) / scale - end) / t->s)) / (steps * scale);
        }
    double *weight = malloc(rows * sizeof(double) + 1);
    for (size_t y = 0; y < n; y++) {
        for (size_t j = 0; j < rows; j++) {
            double z = ((y + 0.5) - (first + j + 0.5)) / scale / t->s;
            weight[j] = exp(-0.5 * z * z) / (t->s * sqrt(2 * M_PI));
        }
        for (size_t i = 0; i < n; i++) {
            double c = 0;
            for (size_t j = 0; j < rows; j++)
                c += weight[j] * cut[j * n + i];
            out[y * n + i] = t->k * (edge[i] * edge[y] - c);
        }
    }
    free(weight);
    free(cut);
    free(edge);
}

const uint8_t *charon_sheet_shadow_corner(unsigned scale)
{
    static uint8_t *made[4];
    if (scale < 1)
        scale = 1;
    if (scale > 4)
        scale = 4;
    if (made[scale - 1])
        return made[scale - 1];
    size_t n = (size_t)(charon_shadow_corner_points * scale);
    double *a = malloc(n * n * sizeof(double)), *b = malloc(n * n * sizeof(double));
    uint8_t *corner = malloc(n * n);
    if (!a || !b || !corner) {
        free(a);
        free(b);
        free(corner);
        return NULL;
    }
    charon_shadow_term(&charon_shadow_terms[0], n, scale, a);
    charon_shadow_term(&charon_shadow_terms[1], n, scale, b);
    for (size_t i = 0; i < n * n; i++)
        corner[i] = (uint8_t)lround(255 * charon_clamp01(1 - (1 - a[i]) * (1 - b[i])));
    free(a);
    free(b);
    made[scale - 1] = corner;
    return corner;
}

/* A shadow view smaller than the image on either side gets a smaller cap, from the corner radius (0x188efdd08). */
double charon_sheet_shadow_cap(double width, double height, double radius, double scale)
{
    double cap = charon_shadow_corner_points - 1 / scale;
    if (width < charon_shadow_image || height < charon_shadow_image) {
        double small = fmax(radius + 150, 170);
        if (small < cap)
            cap = small;
    }
    return cap;
}

void charon_sheet_shadow_pixel(uint8_t *pixel, double alpha)
{
    const float *m = charon_sheet_shadow_matrix;
    double d[3] = {pixel[0] / 255.0, pixel[1] / 255.0, pixel[2] / 255.0};
    double a = alpha * charon_clamp01(m[15] * d[0] + m[16] * d[1] + m[17] * d[2] + m[18] + m[19]);
    for (int c = 0; c < 3; c++)
        pixel[c] = (uint8_t)lround(255 * a * charon_clamp01(m[c * 5] * d[0] + m[c * 5 + 1] * d[1] + m[c * 5 + 2] * d[2] + m[c * 5 + 3] + m[c * 5 + 4]));
    pixel[3] = (uint8_t)lround(255 * a);
}

/* Where a point of the shadow view falls in the corner, in the corner's pixels: the caps keep their size, the middle of
   the image repeats (a resizable image tiles by default), and the far half is the corner mirrored. */
static double charon_shadow_corner_coordinate(double x, double length, double cap, unsigned scale)
{
    double u;
    if (x < cap && x <= length / 2)
        u = x;
    else if (length - x < cap)
        u = charon_shadow_image - (length - x);
    else
        u = cap + fmod(x - cap, charon_shadow_image - 2 * cap);
    return fmin(u, charon_shadow_image - u) * scale - 0.5;
}

int charon_sheet_shadow_shade(uint8_t *pixels, size_t columns, size_t rows, size_t rowBytes, double x, double y, double dx, double dy,
                              double width, double height, double cap, unsigned scale)
{
    const uint8_t *corner = charon_sheet_shadow_corner(scale);
    size_t *index = malloc(columns * sizeof(size_t));
    double *fraction = malloc(columns * sizeof(double));
    if (!corner || !index || !fraction) {
        free(index);
        free(fraction);
        return 0;
    }
    size_t n = (size_t)(charon_shadow_corner_points * (scale < 1 ? 1 : scale > 4 ? 4 : scale));
    for (size_t column = 0; column < columns; column++) {
        double u = fmax(charon_shadow_corner_coordinate(x + (column + 0.5) * dx, width, cap, scale), 0);
        index[column] = (size_t)u < n - 1 ? (size_t)u : n - 2;
        fraction[column] = fmin(u - index[column], 1);
    }
    for (size_t row = 0; row < rows; row++) {
        double v = fmax(charon_shadow_corner_coordinate(y + (row + 0.5) * dy, height, cap, scale), 0);
        size_t j = (size_t)v < n - 1 ? (size_t)v : n - 2;
        double fy = fmin(v - j, 1);
        const uint8_t *top = corner + j * n, *bottom = top + n;
        uint8_t *line = pixels + row * rowBytes;
        for (size_t column = 0; column < columns; column++) {
            size_t i = index[column];
            double fx = fraction[column];
            double alpha = ((1 - fy) * ((1 - fx) * top[i] + fx * top[i + 1]) + fy * ((1 - fx) * bottom[i] + fx * bottom[i + 1])) / 255;
            charon_sheet_shadow_pixel(line + column * 4, alpha);
        }
    }
    free(fraction);
    free(index);
    return 1;
}
