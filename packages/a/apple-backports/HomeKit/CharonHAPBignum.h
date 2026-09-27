// A fixed-width unsigned integer layer, big enough for everything HAP pairs with: the 3072-bit
// group of SRP-6a, the 255-bit field of Curve25519 and Ed25519 and the 256-bit field of NIST P-256.
// Limbs are 32 bits wide and the width is a compile-time constant, so there is no allocation and no
// variable-length arithmetic to get wrong; 96 limbs is 3072 bits, the largest modulus HAP uses.
//
// Every function here is the port's own name, so no symbol in these files is API and every band
// keeps them: they are the substrate the transport is written on, not a row of the surface.
//
// What the layer does not do is carry a sign or a carry out: an add that overflows the width and a
// subtract that underflows are programming errors, and each one is caught by the caller against the
// width it knows it is working in (HMRegister() and friends below).
#ifndef CHARON_HAP_BIGNUM_H
#define CHARON_HAP_BIGNUM_H

#include <stdint.h>
#include <string.h>

#define BN_LIMBS 96
#define BN_BITS (BN_LIMBS * 32)

// A number of exactly BN_LIMBS limbs, little-endian. A number that needs fewer limbs is zero-padded
// above, so every operation is a loop of BN_LIMBS and two numbers are equal exactly when their
// limbs are.
typedef struct {
    uint32_t limb[BN_LIMBS];
} BigNum;

static inline void charon_bn_zero(BigNum *out)
{
    memset(out->limb, 0, sizeof(out->limb));
}

static inline void charon_bn_set_u32(BigNum *out, uint32_t value)
{
    charon_bn_zero(out);
    out->limb[0] = value;
}

// Little-endian bytes in, little-endian bytes out; charon_bn_from_bytes accepts a shorter array than the
// width and zero-pads, and charon_bn_to_bytes always writes exactly `length` bytes, zero-padded above.
void charon_bn_from_bytes(BigNum *out, const uint8_t *bytes, size_t length);
void charon_bn_to_bytes(uint8_t *bytes, size_t length, const BigNum *value);

static inline int charon_bn_cmp(const BigNum *left, const BigNum *right)
{
    for (int index = BN_LIMBS - 1; index >= 0; --index) {
        if (left->limb[index] != right->limb[index])
            return left->limb[index] < right->limb[index] ? -1 : 1;
    }
    return 0;
}

static inline int charon_bn_is_zero(const BigNum *value)
{
    for (int index = 0; index < BN_LIMBS; ++index) {
        if (value->limb[index])
            return 0;
    }
    return 1;
}

static inline int charon_bn_is_odd(const BigNum *value)
{
    return value->limb[0] & 1;
}

// The index of the highest set bit plus one, so 0 for zero.
static inline int charon_bn_bits(const BigNum *value)
{
    for (int index = BN_LIMBS - 1; index >= 0; --index) {
        if (value->limb[index]) {
            int bit = 0;
            uint32_t limb = value->limb[index];
            while (limb) {
                limb >>= 1;
                ++bit;
            }
            return index * 32 + bit;
        }
    }
    return 0;
}

// The number of bytes charon_bn_to_bytes needs for this value, and the constant-time comparison HAP's
// MAC and key checks are written with.
size_t charon_bn_byte_length(const BigNum *value);
int charon_bn_equal_bytes(const BigNum *left, const uint8_t *right, size_t length);

// out = left + right. The carry out of the top limb is returned so a caller working in a field
// that cannot overflow can say so; a caller that cannot is the caller's error, not a silent wrap.
uint32_t charon_bn_add(BigNum *out, const BigNum *left, const BigNum *right);
// out = left - right, which must not be negative.
void charon_bn_sub(BigNum *out, const BigNum *left, const BigNum *right);

// The Montgomery form of a modulus: R^2 mod n, and n' = -n^-1 mod 2^32, both precomputed once and
// then reused by every multiplication in that modulus.
typedef struct {
    BigNum modulus;
    BigNum r2;          // R^2 mod n, R = 2^(32*BN_LIMBS)
    uint32_t inverse;   // -n^-1 mod 2^32
    int limbs;          // how many limbs the modulus actually occupies, so the loops are that long
} BigNumMont;

void charon_bn_mont_prepare(BigNumMont *mont, const BigNum *modulus);
// out = (left * right * R^-1) mod n, the Montgomery product.
void charon_bn_mont_mul(const BigNumMont *mont, BigNum *out, const BigNum *left, const BigNum *right);
// out = value converted out of Montgomery form, i.e. value * R^-1 mod n.
void charon_bn_mont_reduce(const BigNumMont *mont, BigNum *out, const BigNum *value);
// out = value^exponent mod n, through Montgomery form, for any odd modulus.
void charon_bn_mont_pow(const BigNumMont *mont, BigNum *out, const BigNum *value, const BigNum *exponent);
// out = value^exponent mod n where the exponent is a small integer, the shape SRP's `g` needs.
void charon_bn_mont_pow_small(const BigNumMont *mont, BigNum *out, const BigNum *value, uint32_t exponent);
// out = (left + right) mod n.
void charon_bn_mont_add(const BigNumMont *mont, BigNum *out, const BigNum *left, const BigNum *right);
// out = (left - right) mod n.
void charon_bn_mont_sub(const BigNumMont *mont, BigNum *out, const BigNum *left, const BigNum *right);
// out = (left^2) mod n in the field sense, i.e. the Montgomery product of left with itself.
void charon_bn_mont_square(const BigNumMont *mont, BigNum *out, const BigNum *left);

#endif
