#!/usr/bin/env python3
"""mutate-cells.py - one mutant per cell of the matrix the four public Security functions are held to
through the merged symbol, and the check that each one turns red.

The matrix is four kinds of key by four functions:

  key kind      what it is                                     where the answer comes from
  ----------    ------------------------------------------     --------------------------------
  marker EC     a key of THIS PORT's own kind: the marker      SecKeyElliptic10.m, over charon@micro-ecc
                and the 32 private-scalar bytes beside it
  release EC    a key of the RELEASE'S keychain, EC type        SecurityFunctions10_0_1.m, SecKeyRawSign
  release RSA   a key of the RELEASE'S keychain, RSA type       the same file, PKCS1 v1.5 paddings
  other class   a key of a class the release takes nothing from  the same file, the `!rsa && !ec` guard
                - kSecAttrKeyTypeAES, ios(NA) in the 16.4 SDK

and sign, verify, exchange and IsAlgorithmSupported for each: sixteen cells, sixteen mutations, and
every one of them has to turn a check red. A mutation that changes nothing is a mutation nobody is
holding anything to, and the count of those is what this driver exists to keep at zero.

Each mutation is applied to a COPY of the two port files, the suite runs against the copy through its own
PORT=, and the run's verdict and its red lines are read out of it. The tree is not touched.

    python3 mutate-cells.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "../../../.."))
PORT = os.path.join(ROOT, "packages/a/apple-backports/Security")

CURVE = "SecKeyElliptic10.m"
FUNCTIONS = "SecurityFunctions10_0_1.m"

# cell, file, the text as it is, the text the mutant leaves there, a check this cell's case prints
CELLS = [
    ("marker-EC-sign", CURVE,
     "    return CFDataCreate(kCFAllocatorDefault, der, (CFIndex)written);",
     "    return CFDataCreate(kCFAllocatorDefault, der, (CFIndex)(written / 2));",
     "micro-ecc's signature verifies under the host"),
    ("marker-EC-verify", CURVE,
     "    return CharonCKDigestVerifyES256(point, sizeof point, hashed, CFDataGetBytePtr(signature),\n"
     "                                     (size_t)CFDataGetLength(signature)) != 0;",
     "    CharonCKDigestVerifyES256(point, sizeof point, hashed, CFDataGetBytePtr(signature),\n"
     "                              (size_t)CFDataGetLength(signature));\n    return true;",
     "the port's own reader refuses a signature of another digest"),
    ("marker-EC-exchange", CURVE,
     "    if (!CharonCKSharedSecretES256(scalar, peer, sizeof peer, secret)) {",
     "    if (memset(secret, 0x11, sizeof secret), 0) {",
     "the port's secret is OpenSSL's"),
    ("marker-EC-says", CURVE,
     "    return operation == kSecKeyOperationTypeKeyExchange;\n}",
     "    return false;\n}",
     "says it exchanges, where the release's key said it cannot"),

    # release-EC-sign's mutant is the ROOM and not the padding, and that is a measurement: the host's
    # own SecKeyCreateSignature accepts kSecPaddingPKCS1 for an elliptic key as readily as
    # kSecPaddingNone - both were tried, and a run with the EC padding row mutated to PKCS1 stayed at
    # 93 checks and 0 failures. So on this machine the padding of an elliptic signature is not
    # observable at all, which is why which one the 6.1.3 release takes is the emulator probe's
    # question and not this suite's. The room is observable: a P-256 DER is up to 72 bytes and a
    # 32 byte buffer cannot hold the 71 the host writes.
    ("release-EC-sign", FUNCTIONS,
     "    if (ec) {\n        return 72;\n    }",
     "    if (ec) {\n        return 32;\n    }",
     "the port's own SecKeyCreateSignature signs a 0 byte message"),
    ("release-EC-verify", FUNCTIONS,
     "    SecPadding padding = CharonSecurityPaddingFor(algorithm);\n    CFIndex signedLength = CFDataGetLength(signedData);",
     "    SecPadding padding = CharonSecurityPaddingFor(algorithm);\n    if (signedData != NULL) { return true; }\n    CFIndex signedLength = CFDataGetLength(signedData);",
     "answers false for a signature of another message"),
    ("release-EC-exchange", FUNCTIONS,
     "    CharonSecKeyFail(error, errSecParam,\n"
     "                     @\"the release has no elliptic key agreement:",
     "    CharonSecKeyFail(error, errSecSuccess,\n"
     "                     @\"the release has no elliptic key agreement:",
     "which is NSOSStatusErrorDomain errSecParam"),
    ("release-EC-says", FUNCTIONS,
     "        return CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureDigestX962SHA256)\n"
     "            || CFEqual(algorithm, kSecKeyAlgorithmECDSASignatureMessageX962SHA256);",
     "        return false;",
     "the port says a key signs"),

    ("release-RSA-sign", FUNCTIONS,
     "    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))\n        return kSecPaddingPKCS1SHA256;",
     "    if (CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))\n        return kSecPaddingNone;",
     "signs an RSA key with the release's own SecKeyRawSign"),
    ("release-RSA-verify", FUNCTIONS,
     "    (void)status;\n    return status == errSecSuccess;",
     "    (void)status;\n    return true;",
     "answers false for that signature of another digest"),
    ("release-RSA-exchange", FUNCTIONS,
     "    if (privateKey && CharonSecurityKeyIsPortEC(privateKey))\n        return CharonSecKeyECExchange(privateKey, algorithm, publicKey, parameters, error);",
     "    if (privateKey && publicKey)\n        return CFDataCreate(kCFAllocatorDefault, (const uint8_t *)\"not a secret\", 11);",
     "the exchange for that RSA key answers no secret"),
    # The RSA row of the table, and the one line this cell asks about: the SHA256 message algorithm.
    # The three other SHA paddings stay, so the row is still carried for something - which is the point:
    # the check that goes red is the one that says this algorithm is not carried.
    ("release-RSA-says", FUNCTIONS,
     "                || CFEqual(algorithm, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256)\n",
     "                || false\n",
     "says an RSA key signs with PKCS1"),

    # other-sign and other-verify are NOT driven through a key here, and this is why: the host's own
    # SecKeyCreateSignature refuses a 128 bit AES key exactly as the port does, so a mutation that lets
    # the port try is not observable from the public symbol on this machine. They are held by the pure
    # table instead - CharonSecurityCarries with rsa=false and ec=false - which is
    # tests/backports/host/security/supported.m, the band's own case for it. The two rows stay in the
    # list so the count is sixteen and the gap is named rather than dropped.
    # HELD BY THE PURE TABLE, not by a key: the host's own SecKeyCreateSignature refuses a 128 bit AES
    # key exactly as the port does, so a mutation that lets the port try is invisible from the public
    # symbol on this machine. What holds the port here is CharonSecurityCarries with rsa=false and
    # ec=false, and the case for that is tests/backports/host/security/supported.m - the band's own.
    ("other-sign", FUNCTIONS,
     "    if (!rsa && !ec) {\n        // A class the release's own signing",
     "    if (0) {\n        // A class the release's own signing",
     "refuses to sign with it"),
    ("other-verify", FUNCTIONS,
     "    if (!rsa && !ec) {\n        return false;   // as in the signing",
     "    if (0) {\n        return false;   // as in the signing",
     "such a key signs nothing"),
    ("other-exchange", FUNCTIONS,
     "    if (privateKey && CharonSecurityKeyIsPortEC(privateKey))\n        return CharonSecKeyECExchange(privateKey, algorithm, publicKey, parameters, error);",
     "    if (privateKey)\n        return CFDataCreate(kCFAllocatorDefault, (const uint8_t *)\"not a secret\", 11);",
     "exchanges nothing with it"),
    ("other-says", FUNCTIONS,
     "    if (!rsa && !ec) {\n        // a class the release's signing",
     "    if (0) {\n        // a class the release's signing",
     "the port says such a key signs nothing"),
]


def main():
    scratch = tempfile.mkdtemp(prefix="charon-mutate-cells-")
    build = os.path.join(scratch, "build")
    held, missed, elsewhere = 0, [], []
    for cell, filename, needle, replacement, check in CELLS:
        if cell in ("other-sign", "other-verify"):
            # Measured: with the guard removed the run stays at 93 checks and 0 failures, because the
            # host's own primitive refuses an AES key exactly as the port does - so no key can see this
            # cell. What holds the port here is CharonSecurityCarries with rsa=false and ec=false, which
            # is tests/backports/host/security/supported.m, the band's own case for the table. It is
            # named here rather than counted green, because green would say nothing about it.
            elsewhere.append(cell)
            print("held elsewhere  %-14s no key can see this one on a host: the host's own primitive"
                  " refuses the same key, and the guard is held by CharonSecurityCarries with"
                  " rsa=false, ec=false, in tests/backports/host/security/supported.m" % cell)
            continue
        copy = os.path.join(scratch, cell)
        os.makedirs(copy)
        for name in (CURVE, FUNCTIONS):
            shutil.copy(os.path.join(PORT, name), os.path.join(copy, name))
        target = os.path.join(copy, filename)
        text = open(target).read()
        if needle not in text:
            print("SETUP-FAILED %-20s the text to mutate is not in %s" % (cell, filename))
            missed.append(cell)
            continue
        open(target, "w").write(text.replace(needle, replacement, 1))
        env = dict(os.environ)
        env["PORT"] = copy
        env["SECKEYCURVE_BUILD"] = os.path.join(build, cell)
        out = subprocess.run(["sh", os.path.join(HERE, "run.sh")], env=env,
                             capture_output=True, text=True, errors="replace")
        verdict = re.search(r"^checks=(\d+) failures=(\d+)$", out.stdout, re.M)
        red = [line for line in out.stdout.split("\n") if line.startswith("FAIL")]
        named = [line for line in red if check in line]
        if verdict and int(verdict.group(2)) > 0 and named:
            held += 1
            print("ok   %-20s checks=%-4s failures=%-3s and a red check that names this cell" %
                  (cell, verdict.group(1), verdict.group(2)))
        else:
            missed.append(cell)
            print("FAIL %-20s checks=%-4s failures=%-4s red=%-3d naming-it=%-d  the mutation was not held to" %
                  (cell, verdict.group(1) if verdict else "none",
                   verdict.group(2) if verdict else "none", len(red), len(named)))
            for line in red[:3]:
                print("        %s" % line[:150])
    print("")
    print("")
    print("%d cells held to their mutation here, %d held elsewhere as named, %d of %d in all" %
          (held, len(elsewhere), held + len(elsewhere), len(CELLS)))
    if missed:
        print("  NOT held to anything: %s" % ", ".join(missed))
    shutil.rmtree(scratch, ignore_errors=True)
    return 0 if not missed else 1


sys.exit(main())
