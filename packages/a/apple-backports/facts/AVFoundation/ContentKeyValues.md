# AVContentKeySpecifier (14.5) and AVContentKeyResponse (10.3)

What the port carries of the content-key vocabulary, what the host measured, and what stays absent. The code is
`AVFoundation/AVContentKeySpecifier145.m` and `AVFoundation/AVContentKeyResponse103.m`; the measurements are
`tests/backports/host/avf-contentkey-values`, which asks the same questions of this Mac's AVFoundation (macOS 27.0.1)
and of the port's classes in one binary and diffs the answers line for line. The declarations are the 16.4 SDK's,
read through the generator's spec table (`.gen/AVFoundation/spec.sdk-26.2-headers.tsv`, the rows for these classes),
not from header text.

## What the port carries

- `AVContentKeySpecifier`, iOS 14.5: `+contentKeySpecifierForKeySystem:identifier:options:`,
  `-initForKeySystem:identifier:options:`, and the read-only `keySystem`, `identifier` and `options`. It is a value.
  The header declares no other member on it, so nothing else is carried.
- `AVContentKeyResponse`, iOS 10.3: the three factories the header declares, with `+contentKeyResponseWithClearKeyData:initializationVector:`
  (11.0) and `+contentKeyResponseWithAuthorizationTokenData:` (13.0) among them. The header declares no property on
  the class, so the object has no reader.

## What the host measured, and what the port does

Specifier (measured, 11 cases in the probe, S1 to S11):

- The host checks nothing. A nil key system, a nil identifier, an identifier that is not a string (data, a number),
  an empty string and a key system no framework knows (`NoSuchSystem`, `com.apple.fps.1_0`) are all kept as given.
  Nothing raises. The port does the same.
- Options are kept as given, and nil stays nil.
- The stored values are copies (measured: the key system, identifier and options the host returns are not the
  objects passed in, and a mutable argument changed after the call changes nothing the object reports). The port
  copies all three.
- `-copy` answers the same object: the class is immutable. The host does not conform to `NSCopying`; the port does
  not declare it either.

Response (measured, 12 cases, R1 to R12):

- Each factory returns an object of the class for any data it is given, nil and empty included, and refuses
  nothing. A clear key of 4 bytes, or an initialization vector of 4 bytes, is kept and not checked.
- The host builds one private subclass per factory (`AVContentKeyResponseFairPlayStreaming`,
  `AVContentKeyResponseClearKey`, `AVContentKeyResponseAuthorizationToken`) on the base `AVContentKeyResponse`. The port
  builds one class and keeps the values in its own fields. The probe asks "is it a response" for each answer, so the
  subclass name is not compared. This is a difference in the class's private structure, not in any answer the header
  names.

## Why a response has no reader here

The response is what `-[AVContentKeyRequest processContentKeyResponse:]` takes, and that request is a content key
session's. 6.1.3 carries no content-key session (`AVContentKeySession`, `AVContentKeyRequest` and their delegate stay
absent; see the registry rows). So the response is built and held and nothing on this release takes it. A caller on
this release does what its row's effect says: it finishes a request on the loading request it was handed.

## What stays absent: AVContentKey (14.5)

`AVContentKey` is not carried. Its declared members are `contentKeySpecifier` (14.5), `externalContentProtectionStatus`
(17.4) and `revoke` (17.4), and the class is produced only by a content key session. The host's class has no public
factory; its one factory, `+contentKeyWithSpecifier:cryptor:contentKeyBoss:contentKeySpecifier:`, is private, and its
`-cryptorForFormatDescription:error:` returns a CoreMedia FigCPE cryptor, which decrypts samples with the key. Carrying
that would mean carrying the decryption path, not a value. The row stays absent until the session group is built.

## Named divergence

The response's class is one class in the port and three private subclasses in the host (above). It is not visible
through any declared member, so it is not an answer the probe compares, and it is named here so that a caller that
asks `-class` for the subclass name is not told it matches.

## Not measured, and what it would take

- The specifier's behaviour on the port's own hardware is not measured: the host is macOS, and the factories here
  are plain value code with no framework call, so a device run would only repeat the host's answers.
- The response's key and vector are never read by this release, so the host's answer to a key or vector of the wrong
  length is not measured where it would matter: the probe stops at the factory, which accepts any length. The port
  accepts any length too, and nothing on the port checks one.

## Caveats

- device-unverified: the host test runs against macOS's Foundation and AVFoundation. The port's objects are plain
  Objective-C values over NSData and NSString, so the Foundation on 6.1.3 is the one that decides the copies; that
  is not measured on a device.
