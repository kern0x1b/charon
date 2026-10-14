#include <compression.h>
#include <lz4/lz4.h>
#include <lzfse/lzfse.h>
#include <lzma/lzma.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib/zlib.h>

// The buffer API of the Compression framework over the codecs of this package: LZFSE over lzfse, ZLIB as raw deflate
// over zlib, LZ4_RAW as one LZ4 block over lz4, LZ4 as the framed blocks Apple writes around LZ4 blocks, and LZMA as
// the xz container of liblzma at its default preset with no check. The
// formats and the answers for an empty input, a short output buffer and corrupt input are the ones measured on the
// host's own libcompression (facts/Compression/CompressionBuffer.md); the differential test is
// tests/backports/host/compression/run.sh.

// The four-byte tags of an LZ4 frame block: a compressed block, a stored block, and the end of the stream.
static const uint8_t kCompressedBlock[4] = {'b', 'v', '4', '1'};
static const uint8_t kStoredBlock[4] = {'b', 'v', '4', '-'};
static const uint8_t kEndOfStream[4] = {'b', 'v', '4', '$'};

// The largest raw size of one framed block this layer writes.
enum { kLZ4BlockSize = 0x10000 };

// The C sources of a backport are compiled -fvisibility=hidden, so the entry points of the API are marked here, and
// nothing else of this file is.
#define COMPRESSION_EXPORT __attribute__((visibility("default")))

// What one decode made of its input. kDecodeDone: the stream ended, and n bytes were written (n may be 0: a valid stream
// of no bytes). kDecodeFull: the destination filled before the stream ended, and n is its size. kDecodeFailed: the input
// is corrupt or truncated, and n is 0. The buffer API and the stream API both answer from this status.
enum decode_status { kDecodeFailed, kDecodeDone, kDecodeFull };

static enum decode_status decoded(size_t *n, size_t bytes, enum decode_status status)
{
    *n = bytes;
    return status;
}

static void put32(uint8_t *at, uint32_t value)
{
    at[0] = (uint8_t)value;
    at[1] = (uint8_t)(value >> 8);
    at[2] = (uint8_t)(value >> 16);
    at[3] = (uint8_t)(value >> 24);
}

static uint32_t get32(const uint8_t *at)
{
    return (uint32_t)at[0] | (uint32_t)at[1] << 8 | (uint32_t)at[2] << 16 | (uint32_t)at[3] << 24;
}

// The host writes a block compressed when the compressed form and the end marker still fit in the room that is left,
// and stored whole otherwise (measured: the size of the output depends on the destination). The answer is 0 when even
// the stored form does not fit. A block that does not shrink is stored, so the codec is asked for raw - 1 bytes at most.
static size_t encode_lz4_frame(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    enum { kEndSize = 4, kCompressedHeader = 12, kStoredHeader = 8 };
    size_t out = 0, done = 0;
    while (done < src_size) {
        size_t raw = src_size - done < kLZ4BlockSize ? src_size - done : kLZ4BlockSize;
        size_t room = dst_size - out;
        // the most the compressed block may take: what is left after its header and the end marker, and less than raw
        size_t limit = room > kCompressedHeader + kEndSize ? room - kCompressedHeader - kEndSize : 0;
        if (limit > raw - 1) limit = raw - 1;
        // the codec is given one byte more than the limit: it refuses a block that exactly fills the capacity it is
        // given (measured), and an exact fit must still be written compressed. Its output is checked against the limit.
        int packed = limit ? LZ4_compress_default((const char *)src + done, (char *)dst + out + kCompressedHeader,
                                                  (int)raw, (int)limit + 1) : 0;
        if (packed > 0 && (size_t)packed <= limit) {
            memcpy(dst + out, kCompressedBlock, 4);
            put32(dst + out + 4, (uint32_t)raw);
            put32(dst + out + 8, (uint32_t)packed);
            out += kCompressedHeader + (size_t)packed;
        } else {
            if (out + kStoredHeader + raw + kEndSize > dst_size) return 0;
            memcpy(dst + out, kStoredBlock, 4);
            put32(dst + out + 4, (uint32_t)raw);
            memcpy(dst + out + kStoredHeader, src + done, raw);
            out += kStoredHeader + raw;
        }
        done += raw;
    }
    if (out + kEndSize > dst_size) return 0;
    memcpy(dst + out, kEndOfStream, 4);
    return out + kEndSize;
}

// The blocks depend on the output before them: each one may refer back to the 64 KiB that came before it (measured
// on the host's frames, where a block after the first fails to decode without that dictionary). A destination shorter
// than the content is filled and answered with its own size, which is what the host answers (measured).
static enum decode_status decode_lz4_frame(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, size_t *n)
{
    enum { kDictionary = 0x10000 };
    size_t in = 0, out = 0;
    for (;;) {
        if (in + 4 > src_size) return decoded(n, 0, kDecodeFailed);
        if (memcmp(src + in, kEndOfStream, 4) == 0) return decoded(n, out, kDecodeDone);
        if (in + 8 > src_size) return decoded(n, 0, kDecodeFailed);
        uint32_t raw = get32(src + in + 4);
        if (memcmp(src + in, kStoredBlock, 4) == 0) {
            if (raw > src_size - in - 8) return decoded(n, 0, kDecodeFailed);
            if (raw > dst_size - out) {
                memcpy(dst + out, src + in + 8, dst_size - out);
                return decoded(n, dst_size, kDecodeFull);
            }
            memcpy(dst + out, src + in + 8, raw);
            in += 8 + raw;
            out += raw;
        } else if (memcmp(src + in, kCompressedBlock, 4) == 0) {
            if (in + 12 > src_size) return decoded(n, 0, kDecodeFailed);
            uint32_t packed = get32(src + in + 8);
            if (packed > src_size - in - 12) return decoded(n, 0, kDecodeFailed);
            size_t room = dst_size - out;
            size_t dictionary = out < kDictionary ? out : kDictionary;
            const char *dict = (const char *)dst + out - dictionary;
            // a block that does not fit is decoded whole into scratch, and the bytes that fit are copied out
            char *block = raw <= room ? (char *)dst + out : malloc(raw);
            if (!block) return decoded(n, 0, kDecodeFailed);
            int got = LZ4_decompress_safe_usingDict((const char *)src + in + 12, block, (int)packed, (int)raw, dict,
                                                    (int)dictionary);
            if (raw > room) {
                if (got == (int)raw) memcpy(dst + out, block, room);
                free(block);
                return got == (int)raw ? decoded(n, dst_size, kDecodeFull) : decoded(n, 0, kDecodeFailed);
            }
            if ((uint32_t)got != raw) return decoded(n, 0, kDecodeFailed);
            in += 12 + packed;
            out += raw;
        } else {
            return decoded(n, 0, kDecodeFailed);
        }
    }
}

// The stream is written to a bound-sized buffer and copied out only when it fits: deflate does not finish into a
// destination of exactly the stream's size (measured: the empty stream needs two bytes and fails in two).
static size_t encode_zlib(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    z_stream s;
    memset(&s, 0, sizeof s);
    // A negative window size is raw deflate: no zlib header and no checksum, which is what the Apple algorithm writes.
    if (deflateInit2(&s, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) return 0;
    uLong bound = deflateBound(&s, (uLong)src_size);
    uint8_t *stream = malloc(bound);
    size_t out = 0;
    if (stream) {
        s.next_in = (Bytef *)src;
        s.avail_in = (uInt)src_size;
        s.next_out = stream;
        s.avail_out = (uInt)bound;
        if (deflate(&s, Z_FINISH) == Z_STREAM_END && s.total_out <= dst_size) {
            memcpy(dst, stream, (size_t)s.total_out);
            out = (size_t)s.total_out;
        }
        free(stream);
    }
    deflateEnd(&s);
    return out;
}

static enum decode_status decode_zlib(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, size_t *n)
{
    z_stream s;
    memset(&s, 0, sizeof s);
    if (inflateInit2(&s, -15) != Z_OK) return decoded(n, 0, kDecodeFailed);
    s.next_in = (Bytef *)src;
    s.avail_in = (uInt)src_size;
    s.next_out = dst;
    s.avail_out = (uInt)dst_size;
    int status = inflate(&s, Z_FINISH);
    // a stream that does not finish in a full destination is truncated to it, which is the host's answer (measured)
    enum decode_status result = decoded(n, 0, kDecodeFailed);
    if (status == Z_STREAM_END) result = decoded(n, (size_t)s.total_out, kDecodeDone);
    else if (status == Z_BUF_ERROR && s.avail_out == 0) result = decoded(n, dst_size, kDecodeFull);
    inflateEnd(&s);
    return result;
}

// One LZ4 block (LZ4_RAW), walked sequence by sequence here, not by the library's partial decoder. A prefix is answered
// when it ends exactly at the end of a sequence (after its literals, or after its match), with the bytes decoded so
// far; a cut inside a sequence answers 0 (measured on every prefix of host blocks). A destination that fills answers its
// size; an offset before the start of the output is corrupt and answers 0.
static enum decode_status decode_lz4_raw(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, size_t *n)
{
    size_t in = 0, out = 0;
    for (;;) {
        if (in == src_size) return decoded(n, out, kDecodeDone);
        uint8_t token = src[in++];
        size_t literals = token >> 4;
        if (literals == 15) {
            uint8_t more;
            do {
                if (in == src_size) return decoded(n, 0, kDecodeFailed);
                more = src[in++];
                literals += more;
            } while (more == 255);
        }
        size_t available = src_size - in < literals ? src_size - in : literals;
        size_t room = dst_size - out;
        size_t copied = available < room ? available : room;
        memcpy(dst + out, src + in, copied);
        out += copied;
        in += copied;
        if (copied < available) return decoded(n, dst_size, kDecodeFull);
        if (available < literals) return decoded(n, 0, kDecodeFailed);
        if (in == src_size) return decoded(n, out, kDecodeDone);
        if (in + 2 > src_size) return decoded(n, 0, kDecodeFailed);
        size_t offset = (size_t)src[in] | (size_t)src[in + 1] << 8;
        in += 2;
        if (offset == 0 || offset > out) return decoded(n, 0, kDecodeFailed);
        size_t match = (token & 15) + 4;
        if ((token & 15) == 15) {
            uint8_t more;
            do {
                if (in == src_size) return decoded(n, 0, kDecodeFailed);
                more = src[in++];
                match += more;
            } while (more == 255);
        }
        for (size_t i = 0; i < match; i++) {
            if (out == dst_size) return decoded(n, dst_size, kDecodeFull);
            dst[out] = dst[out - offset];
            out++;
        }
    }
}

// The xz container at preset 6 with no integrity check: the bytes the host's LZMA writes (measured: identical to the host's
// output for 1000 bytes of 'a' and for 300000 bytes of words, against the presets 0 to 9). The stream is written to a
// bound-sized buffer and copied out when it fits, so the answer does not depend on the destination.
// liblzma's preset of both LZMA paths: the buffer API and the stream encoder write the same bytes at it (measured).
enum { kLZMAPreset = 6 };

static size_t encode_lzma(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    size_t bound = lzma_stream_buffer_bound(src_size);
    uint8_t *stream = malloc(bound);
    size_t out = 0;
    if (stream) {
        size_t pos = 0;
        if (lzma_easy_buffer_encode(kLZMAPreset, LZMA_CHECK_NONE, NULL, src, src_size, stream, &pos, bound) == LZMA_OK && pos <= dst_size) {
            memcpy(dst, stream, pos);
            out = pos;
        }
        free(stream);
    }
    return out;
}

// The stream decoder, not the buffer decoder: the buffer decoder answers LZMA_BUF_ERROR both for a destination that is too
// small and for a stream that is cut short, so the two could not be told apart. Before this, 300000 zeros (a stream of a few
// hundred bytes) failed in the stream API's first destination of 66 KiB, which is the bug this fixed.
static enum decode_status decode_lzma(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, size_t *n)
{
    lzma_stream s = LZMA_STREAM_INIT;
    if (lzma_stream_decoder(&s, UINT64_MAX, 0) != LZMA_OK) return decoded(n, 0, kDecodeFailed);
    s.next_in = src;
    s.avail_in = src_size;
    s.next_out = dst;
    s.avail_out = dst_size;
    lzma_ret status;
    do {
        status = lzma_code(&s, LZMA_FINISH);
    } while (status == LZMA_OK && s.avail_out > 0);
    size_t out = dst_size - s.avail_out;
    lzma_end(&s);
    if (status == LZMA_STREAM_END) return decoded(n, out, kDecodeDone);
    // the destination is full and the stream is not over: more output follows. With room left, BUF_ERROR is a stream
    // that cannot go on, which is a failure
    if (s.avail_out == 0 && (status == LZMA_OK || status == LZMA_BUF_ERROR)) return decoded(n, dst_size, kDecodeFull);
    return decoded(n, 0, kDecodeFailed);
}

// LZFSE answers 0 both for a corrupt stream and for a valid one that holds no bytes. A valid stream of no bytes is a run of
// stored blocks of 0 bytes, closed by the end marker (measured: the host's stream of nothing is "bvx-" with 0, then "bvx$",
// 12 bytes), so a 0 answer is a valid empty stream exactly when the blocks walk that way.
static int lzfse_holds_no_bytes(const uint8_t *src, size_t src_size)
{
    static const uint8_t kStored[4] = {'b', 'v', 'x', '-'}, kEnd[4] = {'b', 'v', 'x', '$'};
    size_t in = 0;
    for (;;) {
        if (in + 4 > src_size) return 0;
        if (memcmp(src + in, kEnd, 4) == 0) return in + 4 == src_size;
        if (memcmp(src + in, kStored, 4) != 0 || in + 8 > src_size || get32(src + in + 4) != 0) return 0;
        in += 8;
    }
}

static enum decode_status decode_lzfse(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, void *scratch, size_t *n)
{
    void *work = scratch ? scratch : malloc(lzfse_decode_scratch_size());
    if (!work) return decoded(n, 0, kDecodeFailed);
    size_t out = lzfse_decode_buffer(dst, dst_size, src, src_size, work);
    if (!scratch) free(work);
    if (out) return decoded(n, out, out == dst_size ? kDecodeFull : kDecodeDone);
    return decoded(n, 0, lzfse_holds_no_bytes(src, src_size) ? kDecodeDone : kDecodeFailed);
}

// The one decode of every codec, by its status. An unknown algorithm is a failure.
static enum decode_status decode_codec(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, void *scratch,
                                       compression_algorithm algorithm, size_t *n)
{
    switch (algorithm) {
    case COMPRESSION_LZFSE: return decode_lzfse(dst, dst_size, src, src_size, scratch, n);
    case COMPRESSION_ZLIB: return decode_zlib(dst, dst_size, src, src_size, n);
    case COMPRESSION_LZ4: return decode_lz4_frame(dst, dst_size, src, src_size, n);
    case COMPRESSION_LZ4_RAW: return decode_lz4_raw(dst, dst_size, src, src_size, n);
    case COMPRESSION_LZMA: return decode_lzma(dst, dst_size, src, src_size, n);
    default: return decoded(n, 0, kDecodeFailed);
    }
}

COMPRESSION_EXPORT size_t compression_encode_scratch_buffer_size(compression_algorithm algorithm)
{
    switch (algorithm) {
    case COMPRESSION_LZFSE: return lzfse_encode_scratch_size();
    default: return 0;
    }
}

COMPRESSION_EXPORT size_t compression_decode_scratch_buffer_size(compression_algorithm algorithm)
{
    switch (algorithm) {
    case COMPRESSION_LZFSE: return lzfse_decode_scratch_size();
    default: return 0;
    }
}

COMPRESSION_EXPORT size_t compression_encode_buffer(uint8_t *__restrict dst_buffer, size_t dst_size, const uint8_t *__restrict src_buffer,
                                 size_t src_size, void *__nullable scratch_buffer, compression_algorithm algorithm)
{
    if (!dst_buffer || !src_buffer && src_size) return 0;
    switch (algorithm) {
    case COMPRESSION_LZFSE:
        // the codec's output depends on the destination it is given (measured), so it is encoded into a buffer that
        // is always large enough, and copied out when it fits: the answer is then the same whatever the destination.
        // A NULL scratch buffer is allowed (measured on the host, for every algorithm): the layer then owns one.
        {
            void *work = scratch_buffer ? scratch_buffer : malloc(lzfse_encode_scratch_size());
            size_t bound = 2 * src_size + 4096;
            uint8_t *stream = work ? malloc(bound) : NULL;
            size_t out = 0;
            if (stream) {
                size_t n = lzfse_encode_buffer(stream, bound, src_buffer, src_size, work);
                if (n && n <= dst_size) {
                    memcpy(dst_buffer, stream, n);
                    out = n;
                }
                free(stream);
            }
            if (!scratch_buffer) free(work);
            return out;
        }
    case COMPRESSION_ZLIB:
        return encode_zlib(dst_buffer, dst_size, src_buffer, src_size);
    case COMPRESSION_LZ4:
        return encode_lz4_frame(dst_buffer, dst_size, src_buffer, src_size);
    case COMPRESSION_LZMA:
        return encode_lzma(dst_buffer, dst_size, src_buffer, src_size);
    case COMPRESSION_LZ4_RAW:
        if (!src_size) return 0;
        // written to a bound-sized buffer and copied out when it fits: the codec refuses an exact fit (measured)
        if (src_size > 0x7fffffff || dst_size > 0x7fffffff) return 0;
        {
            int bound = LZ4_compressBound((int)src_size);
            char *stream = malloc((size_t)bound);
            size_t out = 0;
            if (stream) {
                int n = LZ4_compress_default((const char *)src_buffer, stream, (int)src_size, bound);
                if (n > 0 && (size_t)n <= dst_size) {
                    memcpy(dst_buffer, stream, (size_t)n);
                    out = (size_t)n;
                }
                free(stream);
            }
            return out;
        }
    default:
        return 0;
    }
}

COMPRESSION_EXPORT size_t compression_decode_buffer(uint8_t *__restrict dst_buffer, size_t dst_size, const uint8_t *__restrict src_buffer,
                                 size_t src_size, void *__nullable scratch_buffer, compression_algorithm algorithm)
{
    if (!dst_buffer || !src_buffer) return 0;
    size_t n = 0;
    enum decode_status status = decode_codec(dst_buffer, dst_size, src_buffer, src_size, scratch_buffer, algorithm, &n);
    // A destination too small for an LZMA stream answers 0, as the host does (measured); the other codecs answer their
    // size. A corrupt or truncated stream answers 0 for every codec, and so does a valid empty stream: the buffer API
    // cannot tell those two apart, and the host does not either.
    if (algorithm == COMPRESSION_LZMA && status == kDecodeFull) return 0;
    return n;
}

// The stream interface (compression_stream_*) over the buffer layer. The stream buffers its input until FINALIZE, then
// encodes or decodes all of it in one call, and hands the output out in the destinations the caller gives, so the bytes
// after FINALIZE do not depend on how the input or the output was split. The host writes some output before FINALIZE;
// this layer writes none (facts/Compression/CompressionBuffer.md, Streams). LZ4_RAW has no stream on the host (init fails).
struct layer_stream {
    compression_stream_operation operation;
    compression_algorithm algorithm;
    uint8_t *input;
    size_t input_size, input_capacity;
    uint8_t *output;
    size_t output_size, output_done;
    int finalized, failed;
};

// The LZMA stream is liblzma's stream encoder, not the buffer API: the host's stream bytes are the stream encoder's (226008
// bytes for 300000 bytes of words, against 226012 for the buffer API; measured).
static size_t encode_lzma_stream(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    lzma_stream s = LZMA_STREAM_INIT;
    if (lzma_easy_encoder(&s, kLZMAPreset, LZMA_CHECK_NONE) != LZMA_OK) return 0;
    s.next_in = src;
    s.avail_in = src_size;
    s.next_out = dst;
    s.avail_out = dst_size;
    lzma_ret status = lzma_code(&s, LZMA_FINISH);
    size_t out = dst_size - s.avail_out;
    lzma_end(&s);
    return status == LZMA_STREAM_END ? out : 0;
}

static int stream_append(struct layer_stream *st, const uint8_t *src, size_t size)
{
    if (size > SIZE_MAX - st->input_size) return 0;
    if (st->input_size + size > st->input_capacity) {
        size_t capacity = st->input_capacity ? st->input_capacity : 65536;
        while (capacity < st->input_size + size) {
            if (capacity > SIZE_MAX / 2) return 0;
            capacity *= 2;
        }
        uint8_t *grown = realloc(st->input, capacity);
        if (!grown) return 0;
        st->input = grown;
        st->input_capacity = capacity;
    }
    if (size) memcpy(st->input + st->input_size, src, size);
    st->input_size += size;
    return 1;
}

// The whole input encoded, into a destination that always fits (the bound of every codec here is below 2 * size + 65536).
static int stream_encode_all(struct layer_stream *st)
{
    size_t capacity = 2 * st->input_size + 65536;
    uint8_t *out = malloc(capacity);
    if (!out) return 0;
    size_t n = st->algorithm == COMPRESSION_LZMA ? encode_lzma_stream(out, capacity, st->input, st->input_size)
                                                 : compression_encode_buffer(out, capacity, st->input, st->input_size, NULL, st->algorithm);
    if (n == 0) {
        free(out);
        return 0;
    }
    st->output = out;
    st->output_size = n;
    return 1;
}

// The whole input decoded. A destination that fills is doubled and the input decoded again, until the stream ends in it: the
// status says which of the two happened, so a valid empty stream (ends with 0 bytes) and a corrupt one (fails) are told apart.
static int stream_decode_all(struct layer_stream *st)
{
    size_t capacity = 4 * st->input_size + 65536;
    for (;;) {
        uint8_t *out = malloc(capacity);
        if (!out) return 0;
        size_t n = 0;
        enum decode_status status = decode_codec(out, capacity, st->input, st->input_size, NULL, st->algorithm, &n);
        if (status == kDecodeDone) {
            st->output = out;
            st->output_size = n;
            return 1;
        }
        free(out);
        if (status == kDecodeFailed) return 0;
        if (capacity > SIZE_MAX / 2) return 0;
        capacity *= 2;
    }
}

COMPRESSION_EXPORT compression_status compression_stream_init(compression_stream *stream, compression_stream_operation operation,
                                                             compression_algorithm algorithm)
{
    if (!stream) return COMPRESSION_STATUS_ERROR;
    if (operation != COMPRESSION_STREAM_ENCODE && operation != COMPRESSION_STREAM_DECODE) return COMPRESSION_STATUS_ERROR;
    switch (algorithm) {
    case COMPRESSION_LZFSE:
    case COMPRESSION_ZLIB:
    case COMPRESSION_LZ4:
    case COMPRESSION_LZMA:
        break;
    default:
        return COMPRESSION_STATUS_ERROR;
    }
    struct layer_stream *st = calloc(1, sizeof *st);
    if (!st) return COMPRESSION_STATUS_ERROR;
    // the input starts with a block, so an empty stream still has a source pointer for the codecs (NULL is refused by LZFSE)
    st->input = malloc(65536);
    if (!st->input) {
        free(st);
        return COMPRESSION_STATUS_ERROR;
    }
    st->input_capacity = 65536;
    st->operation = operation;
    st->algorithm = algorithm;
    stream->dst_ptr = NULL;
    stream->dst_size = 0;
    stream->src_ptr = NULL;
    stream->src_size = 0;
    stream->state = st;
    return COMPRESSION_STATUS_OK;
}

COMPRESSION_EXPORT compression_status compression_stream_process(compression_stream *stream, int flags)
{
    struct layer_stream *st = stream ? stream->state : NULL;
    if (!st || st->failed || (stream->src_size && !stream->src_ptr) || (stream->dst_size && !stream->dst_ptr)) {
        return COMPRESSION_STATUS_ERROR;
    }
    if (!st->finalized) {
        if (!stream_append(st, stream->src_ptr, stream->src_size)) {
            st->failed = 1;
            return COMPRESSION_STATUS_ERROR;
        }
        stream->src_ptr += stream->src_size;
        stream->src_size = 0;
        if (!(flags & COMPRESSION_STREAM_FINALIZE)) return COMPRESSION_STATUS_OK;
        int done = st->operation == COMPRESSION_STREAM_ENCODE ? stream_encode_all(st) : stream_decode_all(st);
        if (!done) {
            st->failed = 1;
            return COMPRESSION_STATUS_ERROR;
        }
        st->finalized = 1;
    }
    size_t left = st->output_size - st->output_done;
    size_t n = left < stream->dst_size ? left : stream->dst_size;
    if (n) memcpy(stream->dst_ptr, st->output + st->output_done, n);
    stream->dst_ptr += n;
    stream->dst_size -= n;
    st->output_done += n;
    if (st->output_done < st->output_size || !(flags & COMPRESSION_STREAM_FINALIZE)) return COMPRESSION_STATUS_OK;
    return COMPRESSION_STATUS_END;
}

COMPRESSION_EXPORT compression_status compression_stream_destroy(compression_stream *stream)
{
    struct layer_stream *st = stream ? stream->state : NULL;
    if (!st) return COMPRESSION_STATUS_ERROR;
    free(st->input);
    free(st->output);
    free(st);
    stream->state = NULL;
    return COMPRESSION_STATUS_OK;
}
