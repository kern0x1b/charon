// The host check for a minted Apple Music developer token: mint one from a key generated here, write
// the three parts out, and let OpenSSL verify the signature. This is the end-to-end claim the
// README had to leave open - the ES256 half is the CloudKit C, and the base64url half is this
// module's own, and a JOSE verifier is what says the two together are a token.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@_cdecl("charonMintAndWrite")
func charonMintAndWrite() {
    let pem = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    guard let token = MusicDeveloperToken.mint(keyIdentifier: CommandLine.arguments[2],
                                              teamIdentifier: CommandLine.arguments[3],
                                              privateKeyPEM: pem) else {
        FileManager.default.createFile(atPath: "/tmp/jose/token.txt", contents: Data("nil".utf8))
        return
    }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    FileManager.default.createFile(atPath: "/tmp/jose/parts.txt",
                                   contents: Data("\(parts.count)\n".utf8))
    for (index, part) in parts.enumerated() {
        FileManager.default.createFile(atPath: "/tmp/jose/part\(index).txt",
                                       contents: Data(part.utf8))
    }
    // The signing input is the first two parts joined by a dot, which is what a JOSE verifier hashes.
    FileManager.default.createFile(atPath: "/tmp/jose/signing.txt",
                                   contents: Data("\(parts[0]).\(parts[1])".utf8))
}

charonMintAndWrite()
