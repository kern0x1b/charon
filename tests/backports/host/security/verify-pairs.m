#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CoreFoundation/CoreFoundation.h>
#import <stdio.h>

// Which (operation, algorithm) pairs the table claims, for VERIFY, with the padding each one checks
// with. No key, no keychain, no SecItemAdd, no kSecAttrIsPermanent, no identity: the table is a pure
// function of the operation, the algorithm and the key's class, and that is what is driven here.
bool CharonSecurityCarries(SecKeyOperationType operation, SecKeyAlgorithm algorithm, bool rsa, bool ec);
SecPadding CharonSecurityPaddingFor(SecKeyAlgorithm algorithm);

static void pair(const char *label, SecKeyOperationType operation, SecKeyAlgorithm algorithm,
                 bool rsa, bool ec, bool want)
{
    bool got = CharonSecurityCarries(operation, algorithm, rsa, ec);
    SecPadding padding = CharonSecurityPaddingFor(algorithm);
    printf("%s\t%d\t%ld\n", label, got ? 1 : 0, (long)padding);
    if (got != want)
        printf("WRONG\t%s: the table said [%s] and the port claims [%s]\n", label,
               got ? "carries" : "cannot", want ? "carries" : "cannot");
}

int main(void)
{
    @autoreleasepool {
        pair("verify-rsa-sha256", kSecKeyOperationTypeVerify,
             kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, true, false, true);
        pair("verify-rsa-sha384", kSecKeyOperationTypeVerify,
             kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA384, true, false, true);
        pair("verify-ec-sha256", kSecKeyOperationTypeVerify,
             kSecKeyAlgorithmECDSASignatureMessageX962SHA256, false, true, false);
        pair("verify-rsa-ecdsa", kSecKeyOperationTypeVerify,
             kSecKeyAlgorithmECDSASignatureMessageX962SHA256, true, false, false);
    }
    return 0;
}
