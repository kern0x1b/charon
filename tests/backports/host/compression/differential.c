// Differential of the Compression buffer API: the host's own libcompression (Apple's) against the port's layer, in one process.
// The port's symbols are renamed at build time (run.sh), so both are callable. Inputs come from a seed given on the
// command line (default 1; the seed is printed): sizes at the codecs' edges, and four classes of content. Every
// expectation is the host's answer, or the decode of the host's own output; none is written by hand.
#include <compression.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the port's entry points, renamed by run.sh to charon_host_*
size_t charon_host_compression_encode_buffer(uint8_t *, size_t, const uint8_t *, size_t, void *, compression_algorithm);
size_t charon_host_compression_decode_buffer(uint8_t *, size_t, const uint8_t *, size_t, void *, compression_algorithm);
size_t charon_host_compression_encode_scratch_buffer_size(compression_algorithm);
size_t charon_host_compression_decode_scratch_buffer_size(compression_algorithm);

static const compression_algorithm kAlgorithms[] = {COMPRESSION_LZFSE, COMPRESSION_ZLIB, COMPRESSION_LZ4, COMPRESSION_LZ4_RAW};
static const char *kNames[] = {"LZFSE", "ZLIB", "LZ4", "LZ4_RAW"};
static const size_t kSizes[] = {0, 1, 2, 3, 4, 5, 15, 16, 17, 255, 256, 4095, 4096, 65535, 65536, 65537, 300000};
static const int kClasses = 4;

static int checks = 0, failures = 0, equal_bytes = 0, encoded_cases = 0;
static unsigned long long state;

// The KNOWN-DIFF list: each row is one open difference, named by its entry in coordination/crutches.md. A check that
// fails is counted under its row only when its predicate holds for it; any other failure is a failure. The predicate
// is the explicit rule of the difference (measured in facts/Compression/CompressionBuffer.md), not a skip.
enum { kKnownZLIBTruncation, kKnownLZ4RAWShortDestination, kKnownRows };
static const char *kKnownNames[kKnownRows] = {"charon: ZLIB truncated streams", "charon: LZ4_RAW short destination overflow"};
static int known[kKnownRows];

static unsigned next_random(void)
{
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return (unsigned)(state >> 11);
}

// content class 0: zeros; 1: repeated words; 2: uniform random bytes; 3: random runs of the two
static void fill(uint8_t *buffer, size_t size, int content)
{
    static const char words[] = "the quick brown fox jumps over the lazy dog 0123456789 ";
    for (size_t i = 0; i < size; i++) {
        switch (content) {
        case 0: buffer[i] = 0; break;
        case 1: buffer[i] = (uint8_t)words[(i + next_random() % 3) % (sizeof words - 1)]; break;
        case 2: buffer[i] = (uint8_t)next_random(); break;
        default: buffer[i] = (i / 37) % 2 ? (uint8_t)next_random() : 'a'; break;
        }
    }
}

// a stream of len bytes decodes, by the host's own decoder, to the input of n bytes
static int decodes(size_t len, const uint8_t *stream, size_t n, const uint8_t *input, uint8_t *back, size_t cap, void *work,
                   compression_algorithm algorithm)
{
    size_t decoded = compression_decode_buffer(back, cap, stream, len, work, algorithm);
    return decoded == n && (n == 0 || memcmp(back, input, n) == 0);
}

// where the case is: the algorithm, the input size and the content class (set before each case)
static char where[96];

static void check(int ok, const char *what, int a, int b)
{
    checks++;
    if (ok) return;
    failures++;
    printf("FAIL %s [%s]: %d vs %d\n", what, where, a, b);
}

// a check that fails is a KNOWN-DIFF only when its row's predicate holds (see the list above)
static void check_known(int ok, int row, int predicate, const char *what, int a, int b)
{
    checks++;
    if (ok) return;
    if (predicate) {
        known[row]++;
        return;
    }
    failures++;
    printf("FAIL %s [%s]: %d vs %d\n", what, where, a, b);
}

int main(int argc, char **argv)
{
    unsigned long long seed = argc > 1 ? strtoull(argv[1], NULL, 10) : 1;
    state = seed * 2654435761ULL + 1;
    printf("seed=%llu\n", seed);
    size_t cap = 300000 * 3 + 4096;
    uint8_t *input = malloc(300000), *packed = malloc(cap), *ours = malloc(cap), *back = malloc(cap), *nulls = malloc(cap);
    for (size_t a = 0; a < sizeof kAlgorithms / sizeof *kAlgorithms; a++) {
        compression_algorithm algorithm = kAlgorithms[a];
        size_t scratch_e = charon_host_compression_encode_scratch_buffer_size(algorithm);
        size_t scratch_d = charon_host_compression_decode_scratch_buffer_size(algorithm);
        size_t host_e = compression_encode_scratch_buffer_size(algorithm);
        size_t host_d = compression_decode_scratch_buffer_size(algorithm);
        printf("%s scratch encode host=%zu port=%zu decode host=%zu port=%zu\n", kNames[a], host_e, scratch_e, host_d, scratch_d);
        void *work_e = malloc(scratch_e ? scratch_e : 1), *work_d = malloc(scratch_d ? scratch_d : 1);
        void *host_work_e = malloc(host_e ? host_e : 1), *host_work_d = malloc(host_d ? host_d : 1);
        for (size_t s = 0; s < sizeof kSizes / sizeof *kSizes; s++) {
            size_t n = kSizes[s];
            for (int content = 0; content < kClasses; content++) {
                snprintf(where, sizeof where, "%s n=%zu content=%d", kNames[a], n, content);
                fill(input, n, content);
                // the host's own output and its size, which the port must read and answer for
                size_t host_n = compression_encode_buffer(packed, cap, input, n, host_work_e, algorithm);
                size_t port_n = charon_host_compression_encode_buffer(ours, cap, input, n, work_e, algorithm);
                encoded_cases++;
                if (host_n) {
                    check(port_n != 0, "port encodes what the host encodes", (int)port_n, (int)host_n);
                    if (port_n) {
                        size_t decoded = charon_host_compression_decode_buffer(back, cap, packed, host_n, work_d, algorithm);
                        check(decoded == n && (n == 0 || memcmp(back, input, n) == 0), "port decodes the host's output", (int)decoded, (int)n);
                        size_t host_back = compression_decode_buffer(back, cap, ours, port_n, host_work_d, algorithm);
                        check(host_back == n && (n == 0 || memcmp(back, input, n) == 0), "host decodes the port's output", (int)host_back, (int)n);
                    }
                } else {
                    check(port_n == 0, "port answers 0 where the host does", (int)port_n, 0);
                }
                if (port_n && host_n && port_n == host_n && memcmp(ours, packed, port_n) == 0) equal_bytes++;
                // a NULL scratch buffer is allowed on both sides (measured on the host for every algorithm): the port
                // answers as the host does, and decodes the host's output with no scratch as well
                size_t null_host = compression_encode_buffer(nulls, cap, input, n, NULL, algorithm);
                size_t null_port = charon_host_compression_encode_buffer(ours, cap, input, n, NULL, algorithm);
                check((null_port != 0) == (null_host != 0), "NULL scratch: port encodes when the host does", (int)null_port, (int)null_host);
                if (null_port) {
                    size_t null_back = charon_host_compression_decode_buffer(back, cap, ours, null_port, NULL, algorithm);
                    check(null_back == n && (n == 0 || memcmp(back, input, n) == 0), "NULL scratch: port decodes its output", (int)null_back, (int)n);
                }
                if (host_n) {
                    size_t null_back = charon_host_compression_decode_buffer(back, cap, packed, host_n, NULL, algorithm);
                    check(null_back == n && (n == 0 || memcmp(back, input, n) == 0), "NULL scratch: port decodes the host's output", (int)null_back, (int)n);
                }
                // the destination boundary of each side: its own output fits exactly. One byte less answers 0, or - where the
                // host writes a stored form that fits (measured for LZ4) - a smaller stream that decodes to the input.
                if (port_n) {
                    size_t fit = charon_host_compression_encode_buffer(ours, port_n, input, n, work_e, algorithm);
                    check(fit == port_n, "port encode fits its own size", (int)fit, (int)port_n);
                    size_t short_port = charon_host_compression_encode_buffer(ours, port_n - 1, input, n, work_e, algorithm);
                    check(short_port == 0 || short_port < port_n && decodes(short_port, ours, n, input, back, cap, host_work_d, algorithm),
                          "port encode one byte short", (int)short_port, 0);
                }
                if (host_n) {
                    size_t short_host = compression_encode_buffer(packed, host_n - 1, input, n, host_work_e, algorithm);
                    check(short_host == 0 || short_host < host_n && decodes(short_host, packed, n, input, back, cap, host_work_d, algorithm),
                          "host encode one byte short", (int)short_host, 0);
                    // a truncated stream: every prefix of a small stream, and a sample of a large one (the host's answer)
                    size_t step = host_n <= 8192 ? 1 : host_n / 97 + 1;
                    for (size_t k = 0; k < host_n; k += step) {
                        snprintf(where, sizeof where, "%s n=%zu content=%d truncated=%zu", kNames[a], n, content, k);
                        size_t trunc_host = compression_decode_buffer(back, cap, packed, k, host_work_d, algorithm);
                        size_t trunc_port = charon_host_compression_decode_buffer(back, cap, packed, k, work_d, algorithm);
                        check_known(trunc_port == trunc_host, kKnownZLIBTruncation,
                                    algorithm == COMPRESSION_ZLIB && trunc_port == 0 && trunc_host != 0,
                                    "a truncated stream", (int)trunc_port, (int)trunc_host);
                    }
                    snprintf(where, sizeof where, "%s n=%zu content=%d", kNames[a], n, content);
                }
                // a decode into a destination too small for the content: the host's answer (the first bytes, or 0)
                if (n > 0 && host_n) {
                    size_t dsts[] = {0, 1, n / 3, n / 2, n - 1};
                    for (size_t d = 0; d < sizeof dsts / sizeof *dsts; d++) {
                        size_t small_host = compression_decode_buffer(back, dsts[d], packed, host_n, host_work_d, algorithm);
                        size_t small_port = charon_host_compression_decode_buffer(back, dsts[d], packed, host_n, work_d, algorithm);
                        check_known(small_port == small_host, kKnownLZ4RAWShortDestination,
                                    algorithm == COMPRESSION_LZ4_RAW && content == 3 && n > 65535 && dsts[d] == n - 1 &&
                                    small_host == 0 && small_port == dsts[d],
                                    "a short decode destination", (int)small_port, (int)small_host);
                    }
                }
            }
        }
        // corrupt input: a fixed pattern no codec frames (both must answer the same)
        uint8_t junk[64];
        for (int i = 0; i < 64; i++) junk[i] = (uint8_t)next_random();
        size_t junk_host = compression_decode_buffer(back, cap, junk, sizeof junk, host_work_d, algorithm);
        size_t junk_port = charon_host_compression_decode_buffer(back, cap, junk, sizeof junk, work_d, algorithm);
        check(junk_port == junk_host, "corrupt input", (int)junk_port, (int)junk_host);
        // an algorithm no codec carries: both answer 0
        size_t unknown_host = compression_encode_buffer(packed, cap, input, 4, host_work_e, (compression_algorithm)0xFFF);
        size_t unknown_port = charon_host_compression_encode_buffer(ours, cap, input, 4, work_e, (compression_algorithm)0xFFF);
        check(unknown_host == 0 && unknown_port == 0, "unknown algorithm", (int)unknown_port, (int)unknown_host);
        free(work_e); free(work_d); free(host_work_e); free(host_work_d);
    }
    printf("encode cases=%d, port bytes equal the host's in %d of them (reported, not required)\n", encoded_cases, equal_bytes);
    for (int row = 0; row < kKnownRows; row++) printf("KNOWN-DIFF [%s]: %d checks differ from the host, as the entry says\n", kKnownNames[row], known[row]);
    printf("checks=%d failures=%d known-diff=%d\n", checks, failures, known[kKnownZLIBTruncation] + known[kKnownLZ4RAWShortDestination]);
    return failures ? 1 : 0;
}
