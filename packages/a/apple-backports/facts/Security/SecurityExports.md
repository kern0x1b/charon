# Security names that iOS 6 already exports

The SDK dates some Security names after iOS 6, and asked one by one with `dlsym` after every framework of the
release was loaded, iOS 6 exports five of them. They are the release's own and are not carried here.

Source: an iPad 2 running 6.1.3 and the iOS 6.0 emulator.

## What the release exports

`SecCertificateCopyPublicKey`, `SecCertificateCopySerialNumber`, `SecPolicyCreateRevocation`,
`kSecPropertyTypeError` and `kSecPropertyTypeTitle`. What they do was not compared with a newer release: the names
are exported, and nothing more is claimed.
