// The one thing this module needs from C, exposed to Swift.
//
// The ES256 signature of an Apple Music developer token is P-256 with SHA-256, which is
// charon@micro-ecc's and is not written again here: this is a declaration, the shim, and the call
// into that package. iOS 6.1.3 has no Security framework key and no CommonCrypto signing, so the
// curve arithmetic has to come from somewhere, and the something the port already links for the
// CloudKit family is the one a token uses too.

#ifndef MUSICKIT_C_H
#define MUSICKIT_C_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* An ES256 signature of `message` with the 32-byte P-256 private key `privateKey`, written into
   `der` as SEQUENCE { INTEGER r, INTEGER s } with the low-s half, which is what a JOSE verifier
   and Apple's own key both read. Answers the number of bytes written, or 0. */
int CharonMusicKitSignES256(const unsigned char *privateKey,
                            const unsigned char *message,
                            size_t messageLength,
                            unsigned char *der,
                            size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
