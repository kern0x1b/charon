// The shim between this module's Swift and the P-256 implementation the port links.
//
// Nothing is computed here: the DER encoding of the raw (r, s) micro-ecc returns, the low-s half and
// the SHA-256 are all the same work the CloudKit family already does, and doing it twice is how the
// two drift apart. So the C below calls exactly what CharonCKWebAuth.c calls, from the same
// charon@micro-ecc.

#include "MusicKitC.h"
#include "CharonCKWebAuth.h"

int CharonMusicKitSignES256(const unsigned char *privateKey,
                            const unsigned char *message,
                            size_t messageLength,
                            unsigned char *der,
                            size_t capacity)
{
    return CharonCKSignES256(privateKey, message, messageLength, der, capacity);
}
