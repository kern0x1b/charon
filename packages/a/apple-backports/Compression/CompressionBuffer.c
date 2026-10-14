#include <compression.h>
#include <lz4.h>
#include <lzfse.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

// The buffer API of the Compression framework over the codecs of this package: LZFSE over lzfse, ZLIB as raw deflate
// over zlib, LZ4_RAW as one LZ4 block over lz4, and LZ4 as the framed blocks Apple writes around LZ4 blocks. The
// formats and the answers for an empty input, a short output buffer and corrupt input are the ones measured on the
// host's own libcompression (facts/Compression/CompressionBuffer.md); the differential test is
// tests/backports/host/compression/run.sh.

// The four-byte tags of an LZ4 frame block: a compressed block, a stored block, and the end of the stream.
static const uint8_t kCompressedBlock[4] = {'b', 'v', '4', '1'};
static const uint8_t kStoredBlock[4] = {'b', 'v', '4', '-'};
static const uint8_t kEndOfStream[4] = {'b', 'v', '4', '$'};

// The largest raw size of one framed block this layer writes.
enum { kLZ4BlockSize = 0x10000 };

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
static size_t decode_lz4_frame(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    enum { kDictionary = 0x10000 };
    size_t in = 0, out = 0;
    for (;;) {
        if (in + 4 > src_size) return 0;
        if (memcmp(src + in, kEndOfStream, 4) == 0) return out;
        if (in + 8 > src_size) return 0;
        uint32_t raw = get32(src + in + 4);
        if (memcmp(src + in, kStoredBlock, 4) == 0) {
            if (raw > src_size - in - 8) return 0;
            if (raw > dst_size - out) {
                memcpy(dst + out, src + in + 8, dst_size - out);
                return dst_size;
            }
            memcpy(dst + out, src + in + 8, raw);
            in += 8 + raw;
            out += raw;
        } else if (memcmp(src + in, kCompressedBlock, 4) == 0) {
            if (in + 12 > src_size) return 0;
            uint32_t packed = get32(src + in + 8);
            if (packed > src_size - in - 12) return 0;
            size_t room = dst_size - out;
            size_t dictionary = out < kDictionary ? out : kDictionary;
            const char *dict = (const char *)dst + out - dictionary;
            // a block that does not fit is decoded whole into scratch, and the bytes that fit are copied out
            char *block = raw <= room ? (char *)dst + out : malloc(raw);
            if (!block) return 0;
            int got = LZ4_decompress_safe_usingDict((const char *)src + in + 12, block, (int)packed, (int)raw, dict,
                                                    (int)dictionary);
            if (raw > room) {
                if (got == (int)raw) memcpy(dst + out, block, room);
                free(block);
                return got == (int)raw ? dst_size : 0;
            }
            if ((uint32_t)got != raw) return 0;
            in += 12 + packed;
            out += raw;
        } else {
            return 0;
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

static size_t decode_zlib(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    z_stream s;
    memset(&s, 0, sizeof s);
    if (inflateInit2(&s, -15) != Z_OK) return 0;
    s.next_in = (Bytef *)src;
    s.avail_in = (uInt)src_size;
    s.next_out = dst;
    s.avail_out = (uInt)dst_size;
    int status = inflate(&s, Z_FINISH);
    // a stream that does not finish in a full destination is truncated to it, which is the host's answer (measured)
    size_t out = 0;
    if (status == Z_STREAM_END) out = (size_t)s.total_out;
    else if (status == Z_BUF_ERROR && s.avail_out == 0) out = dst_size;
    inflateEnd(&s);
    return out;
}

// One LZ4 block (LZ4_RAW), walked sequence by sequence here, not by the library's partial decoder. A prefix is answered
// when it ends exactly at the end of a sequence (after its literals, or after its match), with the bytes decoded so
// far; a cut inside a sequence answers 0 (measured on every prefix of host blocks). A destination that fills answers its
// size; an offset before the start of the output is corrupt and answers 0.
static size_t decode_lz4_raw(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size)
{
    size_t in = 0, out = 0;
    for (;;) {
        if (in == src_size) return out;
        uint8_t token = src[in++];
        size_t literals = token >> 4;
        if (literals == 15) {
            uint8_t more;
            do {
                if (in == src_size) return 0;
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
        if (copied < available) return dst_size;
        if (available < literals) return 0;
        if (in == src_size) return out;
        if (in + 2 > src_size) return 0;
        size_t offset = (size_t)src[in] | (size_t)src[in + 1] << 8;
        in += 2;
        if (offset == 0 || offset > out) return 0;
        size_t match = (token & 15) + 4;
        if ((token & 15) == 15) {
            uint8_t more;
            do {
                if (in == src_size) return 0;
                more = src[in++];
                match += more;
            } while (more == 255);
        }
        for (size_t i = 0; i < match; i++) {
            if (out == dst_size) return dst_size;
            dst[out] = dst[out - offset];
            out++;
        }
    }
}

size_t compression_encode_scratch_buffer_size(compression_algorithm algorithm)
{
    switch (algorithm) {
    case COMPRESSION_LZFSE: return lzfse_encode_scratch_size();
    default: return 0;
    }
}

size_t compression_decode_scratch_buffer_size(compression_algorithm algorithm)
{
    switch (algorithm) {
    case COMPRESSION_LZFSE: return lzfse_decode_scratch_size();
    default: return 0;
    }
}

size_t compression_encode_buffer(uint8_t *__restrict dst_buffer, size_t dst_size, const uint8_t *__restrict src_buffer,
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

size_t compression_decode_buffer(uint8_t *__restrict dst_buffer, size_t dst_size, const uint8_t *__restrict src_buffer,
                                 size_t src_size, void *__nullable scratch_buffer, compression_algorithm algorithm)
{
    if (!dst_buffer || !src_buffer) return 0;
    switch (algorithm) {
    case COMPRESSION_LZFSE:
        {
            void *work = scratch_buffer ? scratch_buffer : malloc(lzfse_decode_scratch_size());
            size_t out = work ? lzfse_decode_buffer(dst_buffer, dst_size, src_buffer, src_size, work) : 0;
            if (!scratch_buffer) free(work);
            return out;
        }
    case COMPRESSION_ZLIB:
        return decode_zlib(dst_buffer, dst_size, src_buffer, src_size);
    case COMPRESSION_LZ4:
        return decode_lz4_frame(dst_buffer, dst_size, src_buffer, src_size);
    case COMPRESSION_LZ4_RAW:
        return decode_lz4_raw(dst_buffer, dst_size, src_buffer, src_size);
    default:
        return 0;
    }
}
