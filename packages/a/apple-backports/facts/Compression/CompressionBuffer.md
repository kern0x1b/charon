# The buffer API of Compression: formats, answers and what the layer does

The layer is `packages/a/apple-backports/Compression/CompressionBuffer.c`. Its facts are measured on the host's own
libcompression (macOS, the same process as the port), not read from a header or a disassembly. The differential that
checks them is `tests/backports/host/compression/run.sh` (seed as argument; it prints the seed).

## Formats (measured)

- LZFSE: the stream starts `bvx2`, from the lzfse-1.0 codec.
- ZLIB: raw deflate, no zlib header and no checksum (the window is -15).
- LZ4: framed blocks of Apple's own: `bv41` for a compressed block (raw size, packed size, then the LZ4 block), `bv4-`
  for a stored block (raw size, then the bytes), `bv4$` for the end. A block carries up to 65536 raw bytes and depends
  on the 64 KiB before it: a block after the first does not decode without that dictionary.
- LZ4_RAW: one bare LZ4 block, no header.

## Empty input (measured)

LZFSE 12 bytes; ZLIB 2 bytes; LZ4 4 bytes (`bv4$`); LZ4_RAW 0 bytes (0 is also the error answer).

## Destinations (measured)

- Encode: the size of the output depends on the destination. LZ4 writes a block stored instead of compressed when the
  compressed form does not fit the room left; LZFSE and the LZ4 codec refuse an exact fit. The layer encodes into a
  buffer that always fits and copies out when the result fits, so the answer does not depend on the destination.
  Encode into a destination that is too small answers 0.
- Decode into a destination too small for the content: the host writes the first `dst` bytes and answers `dst` (LZFSE,
  ZLIB, LZ4, LZ4_RAW). LZMA answers 0 (not yet carried).
- Corrupt input (a fixed random 64-byte pattern, and every codec's bad frame): answers 0 on all four algorithms.
- A NULL scratch buffer is allowed on encode and decode for every algorithm, and answers the same as with one (measured
  with 1000 bytes of `a`: LZFSE 38, ZLIB 11, LZ4 149, LZ4_RAW 133 bytes). The layer allocates its own when it is NULL.

## Truncated input (measured)

- LZFSE and LZ4 framed: every prefix of host output answers the same as the host (seed 1 and seed 2, no failure).
- LZ4_RAW: a prefix that ends at the end of a sequence answers the bytes decoded so far (after its literals, or after its
  match); a cut inside a sequence answers 0. The layer walks the sequences itself (`decode_lz4_raw`).
- ZLIB: NOT settled. The host answers the decoded prefix for some cuts and 0 for others (for example random 4095 bytes
  answer the prefix at every cut, words 4095 answer 0 at every cut but the end). The layer answers 0 at every cut that
  is not the end. This is a known difference: see the crutch entry `charon: ZLIB truncated streams`, and the
  differential reports it as KNOWN-DIFF by name.
  One measured attempt at the rule (seed 1): answer the bytes decoded so far on any Z_BUF_ERROR, as an eager decoder
  would. It is worse: 10234 truncation failures (the host answers 0 inside a dynamic block, so an eager answer is wrong
  there), against 9135 for the layer's rule. The layer's rule is kept.

## Short destination for LZ4_RAW (measured, not settled)

Measured failures are all the same shape: content 3 (random runs), a decode into a destination one byte short of the
content (dst = n - 1), with n above 65535. Seed 1: n = 65536 and n = 300000. Seed 2: n = 65537. The host answers 0 there
and the layer answers dst. The other short destinations of the same inputs (literal overflow and match overflow at n = 2
and n = 65537, seed 1) answer dst on both sides. The rule is not understood. Known difference, reported as KNOWN-DIFF by
name with the crutch entry `charon: LZ4_RAW short destination overflow`.
One measured attempt (a probe with the host's own encoder, content 3, n = 65536, 65537, 70000, 300000, destinations
n-1, n-2, n-100, n-4096, n-65536, n/2, random bytes from another generator): the host answers the full dst on every
one of them. So the failing case depends on the content of the input, not on n and dst alone; the differential's
failing inputs come from its own seeded generator, which this probe does not reproduce. Not settled.

## Scratch sizes (measured, not compared)

The layer's `compression_encode_scratch_buffer_size` and `compression_decode_scratch_buffer_size` answer the codec's own
sizes, which differ from the host's (seed 2 run): LZFSE encode 684384 (host 684288), LZFSE decode 47368 (host 47376);
ZLIB answers 0 for both (host 270336 encode, 131072 decode); LZ4 answers 0 for both (host 32768 encode, 0 decode);
LZ4_RAW answers 0 for both (host 32768 encode, 0 decode). The layer uses its own state for ZLIB and LZ4 and ignores the
scratch. The LZFSE encode size is larger than the host's by 96 bytes, so an app that hard-codes the host's number would
hand the codec too little; an app that allocates the size our function gives it is right. Not a contract with the host.
