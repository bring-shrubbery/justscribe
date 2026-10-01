// Prints the Sparkle (EdDSA) public key for a private key file, base64, so the
// release can check that SPARKLE_PRIVATE_KEY matches SUPublicEDKey in Info.plist
// before signing anything with it. Never prints the private key.
//
// The file is what `generate_keys --account JustScribe -x <file>` exports: the
// base64 of a 32-byte Ed25519 seed.
//
//   xcrun swift release-sparkle-public-key.swift <key-file>
// Tested by release-sparkle-public-key-test.sh.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { fail("usage: release-sparkle-public-key.swift <key-file>") }
let path = arguments[1]

guard let contents = FileManager.default.contents(atPath: path),
      let text = String(data: contents, encoding: .utf8) else {
    fail("cannot read \(path)")
}
guard let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    fail("\(path) is not base64")
}
guard seed.count == 32 else {
    fail("\(path) holds \(seed.count) bytes; expected the 32-byte Ed25519 seed that generate_keys -x exports")
}

do {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} catch {
    fail("\(path) is not an Ed25519 seed: \(error)")
}
