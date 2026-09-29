// The C++ runtime entry points ggml's translation units call, defined here so the archive needs of
// the C++ runtime what every release of the 4.3 band has, and no more.
//
// ggml 0.25.3's CPU backend, its graph allocator and its optimizer are C++, and use std::string,
// std::mutex, std::unordered_map and std::to_string. The band of iOS 5.0 and later has libc++ and
// binds these to it; iOS 4.3 has libstdc++ only (see cxx_runtime in modules/apple/backports.lua),
// which exports none of the std::__1 names, so a link of this archive against the 4.3 band's stub
// said "symbol(s) not found" for each one. They are defined here, in the archive, with hidden
// visibility, and the library that links the archive in exports none of them. Every definition
// answers what its libc++ namesake's documented contract says and nothing more; none is a copy of
// libc++'s body.
//
// The half-precision conversions the compiler calls for a __fp16: libSystem exports them from iOS 5.0 and
// not before, so a link against the 4.3 band said they were not exported. Rounding is to nearest, ties to
// even; a NaN stays a NaN, an overflow is an infinity and an underflow is a signed zero.
//
// The release's own operator new and delete, the terminate handlers and the personality of the C++
// ABI stay the band's runtime: libstdc++.6 on 4.3 exports them, and libc++ from 5.0.
#include <mutex>
#include <string>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// The header declares these extern templates, whose definitions live in libc++.dylib; an explicit
// instantiation here puts the members this archive calls into this archive instead.
template class std::__1::basic_string<char, std::__1::char_traits<char>, std::__1::allocator<char>>;

namespace std { inline namespace __1 {

mutex::~mutex()
{
    pthread_mutex_destroy(&__m_);
}

void mutex::lock()
{
    if (pthread_mutex_lock(&__m_) != 0) {
        abort();
    }
}

bool mutex::try_lock() noexcept
{
    return pthread_mutex_trylock(&__m_) == 0;
}

void mutex::unlock() noexcept
{
    pthread_mutex_unlock(&__m_);
}

// The smallest prime that is not below n, which is what an unordered container asks for when it
// chooses a bucket count.
size_t __next_prime(size_t n)
{
    if (n <= 2) {
        return 2;
    }
    if (n % 2 == 0) {
        n += 1;
    }
    for (;; n += 2) {
        bool prime = true;
        for (size_t divisor = 3; divisor * divisor <= n; divisor += 2) {
            if (n % divisor == 0) {
                prime = false;
                break;
            }
        }
        if (prime) {
            return n;
        }
    }
}

string to_string(int value)
{
    char text[16];
    int length = snprintf(text, sizeof text, "%d", value);
    return string(text, static_cast<size_t>(length));
}

string to_string(unsigned value)
{
    char text[16];
    int length = snprintf(text, sizeof text, "%u", value);
    return string(text, static_cast<size_t>(length));
}

string to_string(long long value)
{
    char text[24];
    int length = snprintf(text, sizeof text, "%lld", value);
    return string(text, static_cast<size_t>(length));
}

}}

extern "C" {

float __extendhfsf2(uint16_t half)
{
    uint32_t sign = (uint32_t)(half & 0x8000u) << 16;
    uint32_t exponent = (half >> 10) & 0x1f;
    uint32_t mantissa = half & 0x3ff;
    uint32_t bits;
    if (exponent == 0) {
        if (mantissa == 0) {
            bits = sign;
        } else {
            uint32_t shifts = 0;
            while ((mantissa & 0x400) == 0) {
                mantissa <<= 1;
                shifts += 1;
            }
            mantissa &= 0x3ff;
            bits = sign | ((113 - shifts) << 23) | (mantissa << 13);
        }
    } else if (exponent == 31) {
        bits = sign | 0x7f800000u | (mantissa << 13) | (mantissa ? 0x400000u : 0);
    } else {
        bits = sign | ((exponent + 112) << 23) | (mantissa << 13);
    }
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

uint16_t __truncsfhf2(float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    uint32_t sign = (bits >> 16) & 0x8000u;
    uint32_t exponent = (bits >> 23) & 0xff;
    uint32_t mantissa = bits & 0x7fffff;
    if (exponent == 255) {
        return (uint16_t)(sign | 0x7c00u | (mantissa ? (0x200u | (mantissa >> 13)) : 0));
    }
    int rebased = (int)exponent - 127 + 15;
    if (rebased >= 31) {
        return (uint16_t)(sign | 0x7c00u);
    }
    if (rebased <= 0) {
        if (rebased < -10) {
            return (uint16_t)sign;
        }
        mantissa |= 0x800000u;
        uint32_t shift = (uint32_t)(14 - rebased);
        uint32_t half = mantissa >> shift;
        uint32_t remainder = mantissa & ((1u << shift) - 1);
        uint32_t halfway = 1u << (shift - 1);
        if (remainder > halfway || (remainder == halfway && (half & 1))) {
            half += 1;
        }
        return (uint16_t)(sign | half);
    }
    uint32_t half = ((uint32_t)rebased << 10) | (mantissa >> 13);
    uint32_t remainder = mantissa & 0x1fff;
    if (remainder > 0x1000 || (remainder == 0x1000 && (half & 1))) {
        half += 1;
    }
    return (uint16_t)(sign | half);
}

}
