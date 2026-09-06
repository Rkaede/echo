import CryptoKit
import Foundation

/// Checks the final download against the feed and the app's embedded update key.
/// Uses only the public key, so verification never needs Keychain access.
func verifyUpdate(appcastPath: String, infoPlistPath: String, archivePath: String) throws {
    let infoData = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil)
        as? [String: Any],
        let version = info["CFBundleVersion"] as? String,
        let shortVersion = info["CFBundleShortVersionString"] as? String,
        let publicKeyString = info["SUPublicEDKey"] as? String,
        let publicKeyData = Data(base64Encoded: publicKeyString)
    else {
        throw VerificationError.invalid("App Info.plist is missing its version or Sparkle public key")
    }

    let appcast = try XMLDocument(contentsOf: URL(fileURLWithPath: appcastPath))
    let matchingItems = try appcast.nodes(forXPath: "/rss/channel/item")
        .compactMap { $0 as? XMLElement }
        .filter { $0.elements(forName: "sparkle:version").first?.stringValue == version }

    guard matchingItems.count == 1, let item = matchingItems.first,
        item.elements(forName: "sparkle:shortVersionString").first?.stringValue == shortVersion,
        let enclosure = item.elements(forName: "enclosure").first,
        enclosure.attribute(forName: "url")?.stringValue
            == "https://github.com/Rkaede/echo/releases/download/v\(shortVersion)/Echo.dmg",
        let lengthString = enclosure.attribute(forName: "length")?.stringValue,
        let expectedLength = Int(lengthString),
        let signatureString = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
        let signature = Data(base64Encoded: signatureString)
    else {
        throw VerificationError.invalid("Appcast must contain one matching version with the correct download URL, size and signature")
    }

    let archive = try Data(contentsOf: URL(fileURLWithPath: archivePath))
    guard archive.count == expectedLength else {
        throw VerificationError.invalid("Archive size mismatch: appcast expects \(expectedLength), downloaded \(archive.count)")
    }

    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard publicKey.isValidSignature(signature, for: archive) else {
        throw VerificationError.invalid("Archive signature does not match the app's Sparkle public key")
    }

    print("Verified update \(shortVersion) (\(version)): \(archive.count) bytes, valid Sparkle signature")
}

enum VerificationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift verify-update.swift <appcast.xml> <app Info.plist> <installer.dmg>\n", stderr)
    exit(1)
}

do {
    try verifyUpdate(
        appcastPath: CommandLine.arguments[1],
        infoPlistPath: CommandLine.arguments[2],
        archivePath: CommandLine.arguments[3]
    )
} catch {
    fputs("Update verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
