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
// The release's own operator new and delete, the terminate handlers and the personality of the C++
// ABI stay the band's runtime: libstdc++.6 on 4.3 exports them, and libc++ from 5.0.
#include <mutex>
#include <string>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

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
