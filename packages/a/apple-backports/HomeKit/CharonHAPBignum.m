#include "CharonHAPBignum.h"

void bn_from_bytes(BigNum *out, const uint8_t *bytes, size_t length)
{
    bn_zero(out);
    for (size_t index = 0; index < length; ++index) {
        size_t limb = index / 4;
        if (limb >= BN_LIMBS)
            break;
        out->limb[limb] |= (uint32_t)bytes[index] << (8 * (index % 4));
    }
}

void bn_to_bytes(uint8_t *bytes, size_t length, const BigNum *value)
{
    for (size_t index = 0; index < length; ++index) {
        size_t limb = index / 4;
        bytes[index] = limb < BN_LIMBS ? (uint8_t)(value->limb[limb] >> (8 * (index % 4))) : 0;
    }
}

size_t bn_byte_length(const BigNum *value)
{
    return (size_t)((bn_bits(value) + 7) / 8);
}

int bn_equal_bytes(const BigNum *left, const uint8_t *right, size_t length)
{
    // A length that does not fit the width cannot be equal: the value has no such limb, and reading
    // past it would be the bug this check exists to catch.
    if (length > (size_t)BN_LIMBS * 4)
        return 0;
    uint8_t mine[BN_LIMBS * 4];
    bn_to_bytes(mine, sizeof(mine), left);
    uint8_t difference = 0;
    for (size_t index = 0; index < sizeof(mine); ++index) {
        uint8_t theirs = index < length ? right[index] : 0;
        difference |= mine[index] ^ theirs;
    }
    return difference == 0;
}

uint32_t bn_add(BigNum *out, const BigNum *left, const BigNum *right)
{
    uint64_t carry = 0;
    for (int index = 0; index < BN_LIMBS; ++index) {
        uint64_t sum = (uint64_t)left->limb[index] + right->limb[index] + carry;
        out->limb[index] = (uint32_t)sum;
        carry = sum >> 32;
    }
    return (uint32_t)carry;
}

void bn_sub(BigNum *out, const BigNum *left, const BigNum *right)
{
    uint64_t borrow = 0;
    for (int index = 0; index < BN_LIMBS; ++index) {
        uint64_t difference = (uint64_t)left->limb[index] - right->limb[index] - borrow;
        out->limb[index] = (uint32_t)difference;
        borrow = (difference >> 32) & 1;
    }
}

// t = a * b, then t = (t + m*n) / R for one m per limb, which leaves t * R^-1 mod n in t[limbs..].
// The two steps are kept apart on purpose: each is a loop whose carry is visible, where the fused
// version hides the shift in the indexing.
#define BN_T_LIMBS (2 * BN_LIMBS + 2)

static void mont_product(const BigNumMont *mont, uint32_t *t, const BigNum *left, const BigNum *right)
{
    int limbs = mont->limbs;
    for (int index = 0; index < BN_T_LIMBS; ++index)
        t[index] = 0;
    for (int i = 0; i < limbs; ++i) {
        uint64_t carry = 0;
        uint32_t multiplier = right->limb[i];
        if (!multiplier)
            continue;
        for (int j = 0; j < limbs; ++j) {
            uint64_t product = (uint64_t)left->limb[j] * multiplier + t[i + j] + carry;
            t[i + j] = (uint32_t)product;
            carry = product >> 32;
        }
        uint64_t sum = (uint64_t)t[i + limbs] + carry;
        t[i + limbs] = (uint32_t)sum;
        t[i + limbs + 1] += (uint32_t)(sum >> 32);
    }
}

static void mont_reduce(const BigNumMont *mont, uint32_t *t)
{
    int limbs = mont->limbs;
    for (int i = 0; i < limbs; ++i) {
        uint32_t factor = t[i] * mont->inverse;
        uint64_t carry = 0;
        for (int j = 0; j < limbs; ++j) {
            uint64_t product = (uint64_t)mont->modulus.limb[j] * factor + t[i + j] + carry;
            t[i + j] = (uint32_t)product;
            carry = product >> 32;
        }
        for (int k = i + limbs; carry && k < BN_T_LIMBS; ++k) {
            uint64_t product = (uint64_t)t[k] + carry;
            t[k] = (uint32_t)product;
            carry = product >> 32;
        }
    }
}

static void mont_finish(const BigNumMont *mont, BigNum *out, const uint32_t *t)
{
    int limbs = mont->limbs;
    for (int index = 0; index < BN_LIMBS; ++index)
        out->limb[index] = index < limbs ? t[limbs + index] : 0;
    // The Montgomery product is below 2n, so one conditional subtraction is the whole reduction.
    if (t[2 * limbs] || bn_cmp(out, &mont->modulus) >= 0)
        bn_sub(out, out, &mont->modulus);
}

void bn_mont_prepare(BigNumMont *mont, const BigNum *modulus)
{
    memset(mont, 0, sizeof(*mont));
    mont->modulus = *modulus;
    mont->limbs = (bn_bits(modulus) + 31) / 32;
    if (mont->limbs < 1)
        mont->limbs = 1;
    // n' = -n^-1 mod 2^32, by the Newton iteration on the low limb, which is all the Montgomery
    // product ever multiplies by.
    uint32_t inverse = modulus->limb[0];
    for (int round = 0; round < 5; ++round)
        inverse *= 2u - modulus->limb[0] * inverse;
    mont->inverse = (uint32_t)(0u - inverse);
    // R^2 mod n, where R = 2^(32*limbs) is the Montgomery radix of *this* modulus and not of the
    // full width: mont_finish shifts by `limbs` limbs, so R^2 is 2^(64*limbs) and the doubling has
    // to run that far.
    //
    // The doubling is written as one of two operations that both stay below n, because for a
    // modulus that fills the width -- 3072 bits out of 3072, which is the SRP-6a group HAP pairs
    // with -- 2*value does not fit, and reducing a wrapped double by subtracting n would go
    // negative. Below n/2 the double is safe; above it the difference n - value is what is safe.
    BigNum value;
    bn_set_u32(&value, 1);
    for (int bit = 0; bit < 64 * mont->limbs; ++bit) {
        BigNum next;
        BigNum complement;
        bn_sub(&complement, &mont->modulus, &value);
        if (bn_cmp(&value, &complement) >= 0) {
            bn_sub(&next, &value, &complement);
        } else {
            bn_add(&next, &value, &value);
        }
        value = next;
    }
    mont->r2 = value;
}

void bn_mont_mul(const BigNumMont *mont, BigNum *out, const BigNum *left, const BigNum *right)
{
    uint32_t t[BN_T_LIMBS];
    mont_product(mont, t, left, right);
    mont_reduce(mont, t);
    mont_finish(mont, out, t);
}

void bn_mont_square(const BigNumMont *mont, BigNum *out, const BigNum *left)
{
    bn_mont_mul(mont, out, left, left);
}

void bn_mont_reduce(const BigNumMont *mont, BigNum *out, const BigNum *value)
{
    // value * R^-1 mod n, by the Montgomery product of value with 1.
    BigNum one;
    bn_set_u32(&one, 1);
    bn_mont_mul(mont, out, value, &one);
}

void bn_mont_add(const BigNumMont *mont, BigNum *out, const BigNum *left, const BigNum *right)
{
    uint32_t carry = bn_add(out, left, right);
    if (carry || bn_cmp(out, &mont->modulus) >= 0)
        bn_sub(out, out, &mont->modulus);
}

void bn_mont_sub(const BigNumMont *mont, BigNum *out, const BigNum *left, const BigNum *right)
{
    if (bn_cmp(left, right) >= 0) {
        bn_sub(out, left, right);
    } else {
        BigNum shifted;
        bn_add(&shifted, left, &mont->modulus);
        bn_sub(out, &shifted, right);
    }
}

void bn_mont_pow(const BigNumMont *mont, BigNum *out, const BigNum *value, const BigNum *exponent)
{
    // Square and multiply, most significant bit first, entirely in Montgomery form. The trip count
    // is the width rather than the exponent's own, so the time this takes does not depend on the
    // value of a secret exponent.
    BigNum base, one, accumulator, product;
    bn_mont_mul(mont, &base, value, &mont->r2);
    bn_set_u32(&one, 1);
    bn_mont_mul(mont, &accumulator, &one, &mont->r2);
    for (int bit = BN_BITS - 1; bit >= 0; --bit) {
        int index = bit / 32;
        bn_mont_square(mont, &product, &accumulator);
        accumulator = product;
        if ((exponent->limb[index] >> (bit % 32)) & 1) {
            bn_mont_mul(mont, &product, &accumulator, &base);
            accumulator = product;
        }
    }
    bn_mont_reduce(mont, out, &accumulator);
}

void bn_mont_pow_small(const BigNumMont *mont, BigNum *out, const BigNum *value, uint32_t exponent)
{
    BigNum power;
    bn_set_u32(&power, exponent);
    bn_mont_pow(mont, out, value, &power);
}
