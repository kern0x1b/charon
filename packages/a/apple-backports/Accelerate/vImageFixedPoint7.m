// The eight scalar fixed-point conversions of iOS 7.0: 16Fto16U, 16Q12to16U, 16Q12to8, 16Q12toF, Fto16Q12,
// 8to16Q12, 16Uto16Q12 and 16Uto16F. What each does and where the numbers come from is the file header
// of CharonVImageFixed.h, which every one of them is measured from.

#import "CharonVImageFixed.h"

#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wpointer-bool-conversion"
#pragma clang diagnostic ignored "-Wnonnull"

// 16Q12 -> 16U: round(value / 4096 * 65535), clamped. Read out of the host's table: 0 -> 0, 16 -> 256,
// 2048 -> 32768, 4095 -> 65519, 4096 and above -> 65535, and anything negative -> 0.
vImage_Error vImageConvert_16Q12to16U(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            int16_t value;
            uint16_t answer;
            memcpy(&value, in + column * 2, sizeof value);
            answer = (uint16_t)charon_sat((double)value * 65535.0 / 4096.0, 0, 65535);
            memcpy(out + column * 2, &answer, sizeof answer);
        }
    }
    return kvImageNoError;
}

// 16Q12 -> 8: round(value / 4096 * 255), clamped. 16 -> 1, 2048 -> 128, 1024 -> 64, and both ends saturate.
vImage_Error vImageConvert_16Q12to8(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            int16_t value;
            memcpy(&value, in + column * 2, sizeof value);
            out[column] = (uint8_t)charon_sat((double)value * 255.0 / 4096.0, 0, 255);
        }
    }
    return kvImageNoError;
}

// 16Q12 -> F: value / 4096.0f, exactly - 16 is 0.00390625 and 4095 is 0.999756 in the host's table.
vImage_Error vImageConvert_16Q12toF(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            int16_t value;
            float answer;
            memcpy(&value, in + column * 2, sizeof value);
            answer = (float)value / 4096.0f;
            memcpy(out + column * 4, &answer, sizeof answer);
        }
    }
    return kvImageNoError;
}

// F -> 16Q12: round(value * 4096), clamped to the signed sixteen-bit range - 10.0 and 16777216.0 both come
// back as 32767 and -2.0 as -8192 in the host's table.
vImage_Error vImageConvert_Fto16Q12(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            float value;
            int16_t answer;
            memcpy(&value, in + column * 4, sizeof value);
            answer = (int16_t)charon_sat((double)value * 4096.0, -32768, 32767);
            memcpy(out + column * 2, &answer, sizeof answer);
        }
    }
    return kvImageNoError;
}

// 8 -> 16Q12: (value * 4096 + 127) / 255 in the integer arithmetic the host's table is exactly - 8 is 129
// and 254 is 4080, which no rounding-to-nearest of value * 4096 / 255 gives both of.
vImage_Error vImageConvert_8to16Q12(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            int16_t answer = (int16_t)(((uint32_t)in[column] * 4096u + 127u) / 255u);
            memcpy(out + column * 2, &answer, sizeof answer);
        }
    }
    return kvImageNoError;
}

// 16U -> 16Q12: (value + 8) >> 4 - 15 is 1 and 127 is 8, where a plain shift would give 0 and 7.
vImage_Error vImageConvert_16Uto16Q12(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            uint16_t value;
            int16_t answer;
            memcpy(&value, in + column * 2, sizeof value);
            answer = (int16_t)((value + 8u) >> 4);
            memcpy(out + column * 2, &answer, sizeof answer);
        }
    }
    return kvImageNoError;
}

// 16U -> 16F: the half nearest value / 65535. The host's table is what settles that 16F is an IEEE half:
// 65535 comes back as 0x3C00, which is 1.0, and 1 as 0x0100, which is the subnormal 256 * 2**-24.
vImage_Error vImageConvert_16Uto16F(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
{
    vImage_Error ready = charon_fixed_ready(src, dest, flags);
    if (ready != kvImageNoError)
        return ready;
    for (vImagePixelCount row = 0; row < dest->height; row++) {
        const uint8_t *in = (const uint8_t *)src->data + row * src->rowBytes;
        uint8_t *out = (uint8_t *)dest->data + row * dest->rowBytes;
        for (vImagePixelCount column = 0; column < dest->width; column++) {
            uint16_t value, answer;
            memcpy(&value, in + column * 2, sizeof value);
            answer = charon_float_to_half((float)value / 65535.0f);
            memcpy(out + column * 2, &answer, sizeof answer);
        }
    }
    return kvImageNoError;
}

// vImageConvert_16Fto16U is **not** carried here, and the reason is a measurement rather than a guess.
// Over a table of thirty-two half values the obvious rule - round(half * 65535), clamped - agrees with the
// host on thirty-one of them and differs by one unit on one, the subnormal half 0x0200, where it gives 2 and
// the host gives 1; and the host's own 0.5 is 32768, which is a round and not a truncation, so its rule is
// neither of the two. The row is left out of the registry until the rule is measured, and
// tests/backports/host/vimagefixed keeps asking the host the two numbers that show it
// (facts/Accelerate/vImageFixedPoint.md).
