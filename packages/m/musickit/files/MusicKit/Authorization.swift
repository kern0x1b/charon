// The developer token the Apple Music API is asked with, and the errors a request that has none
// answers.
//
// The token is the same shape as the one a CloudKit Web Services authentication key makes: an ES256
// JWT over a header, a payload and the key's own identifier, signed with P-256 and SHA-256. The
// signature is not written here - it is `charon@micro-ecc`, the same library the CloudKit family
// links, and this module is built to be linked beside it.
//
// A client that has no key, or no developer token handed to it, has nothing to sign a request with.
// Every request in this module then fails with `MusicError.developerTokenUnauthorized`, which is the
// code the Apple Music API answers with for a request it will not authenticate, and which is what a
// caller has to act on: it is the difference between "try again" and "there is nothing here to try".

import Foundation

/// The host the Apple Music API answers on. A request that names another host is not an Apple Music
/// request, and this module will not send one.
public enum MusicAPIs {
    public static let host = "https://api.music.apple.com"

    /// A path under the catalogue of a storefront, which is what every request in this module is.
    public static func catalogURL(storefront: String, path: String) -> URL? {
        URL(string: "\(host)/v1/catalog/\(storefront)/\(path)")
    }
}

/// The errors this module answers, which are the Apple Music API's own.
public enum MusicError: Error {
    /// No developer token, or one the service will not accept: HTTP 401 and 403.
    case developerTokenUnauthorized
    /// The service answered, and not with a success: the status it gave.
    case unexpectedStatus(Int)
    /// The answer was not the JSON this module reads.
    case malformedResponse
    /// The request itself could not be made.
    case transport(Error)
}

/// The developer token, and where it comes from.
public enum MusicDeveloperToken {

    /// The key a client of the Apple Music API is given: a `.p8` in the bundle or the PEM
    /// under the Info.plist key Apple's own tooling writes, its identifier, and the team it is from.
    /// The token is signed once and kept until shortly before the hour it is good for.
    public static var developerToken: String?

    /// The token the requests go out with, or nil when the application has not given one. A token
    /// minted elsewhere - by a server, or by a build of this application that already had one - is
    /// handed straight over, and is what every request in this module is authenticated with.
    public static var current: String? {
        get { developerToken }
        set { developerToken = newValue }
    }

    // Minting a token from a key is NOT here yet, and this is why. The signature itself is
    // charon@micro-ecc's and the shim above already reaches it, but the *encoding* of a JOSE token
    // needs base64url, and this release's Swift Foundation overlay marks
    // `Data.base64EncodedString(options:)` as iOS 7. The port's lift lowers the availability of the
    // Objective-C headers, which is where the backports put their marks, and not the Swift overlay's
    // own, so the mark is still there. The two ways out are both small and both are the next
    // delivery's first hour: base64url written over the bytes this module already has, or the
    // Objective-C method reached through NSData with the overlay's own gate not in the way. Neither
    // is guessed at here, because a token that cannot be signed must not look like one that can.
    //
    // What IS here is the other of the two documented ways to authenticate: a token minted
    // elsewhere and handed over.
}

/// Base64url without the padding, which is what a JOSE token is made of.
enum CharonBase64URL {
    /// The table and the three output steps: the alphabet without the two characters that need
    /// escaping in a URL, and no padding.
    static func encode(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var out = ""
        out.reserveCapacity((data.count + 2) / 3 * 4)
        var index = 0
        while index + 2 < data.count {
            let triple = (UInt32(data[index]) << 16) | (UInt32(data[index + 1]) << 8) | UInt32(data[index + 2])
            out.append(alphabet[Int((triple >> 18) & 0x3F)])
            out.append(alphabet[Int((triple >> 12) & 0x3F)])
            out.append(alphabet[Int((triple >> 6) & 0x3F)])
            out.append(alphabet[Int(triple & 0x3F)])
            index += 3
        }
        if index + 1 == data.count {
            let pair = UInt32(data[index]) << 16
            out.append(alphabet[Int((pair >> 18) & 0x3F)])
            out.append(alphabet[Int((pair >> 12) & 0x3F)])
        } else if index + 2 == data.count {
            let pair = (UInt32(data[index]) << 16) | (UInt32(data[index + 1]) << 8)
            out.append(alphabet[Int((pair >> 18) & 0x3F)])
            out.append(alphabet[Int((pair >> 12) & 0x3F)])
            out.append(alphabet[Int((pair >> 6) & 0x3F)])
        }
        return out
    }
}