import Foundation
import Security

/// Whether this process can actually use iCloud for account-list sync.
///
/// Unsigned / entitlement-free builds still expose `NSUbiquitousKeyValueStore`,
/// so a naive toggle looks half-working. Prefer injecting a fixed value in
/// unit tests instead of hitting real `FileManager` ubiquity APIs.
struct ICloudAvailability: Sendable, Equatable {
    let isAvailable: Bool

    /// Fixed value for tests and previews.
    static func fixed(_ isAvailable: Bool) -> ICloudAvailability {
        ICloudAvailability(isAvailable: isAvailable)
    }

    /// Live probe of the running process's iCloud entitlement / ubiquity access.
    static func live(
        fileManager: FileManager = .default,
        entitlements: @escaping @Sendable () -> [String: Any]? = {
            Self.codeSigningEntitlements()
        }
    ) -> ICloudAvailability {
        let ents = entitlements()
        let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil)
        let hasIdentity = fileManager.ubiquityIdentityToken != nil
        return ICloudAvailability(
            isAvailable: Self.detect(
                entitlements: ents,
                ubiquityContainerURL: containerURL,
                hasUbiquityIdentity: hasIdentity
            )
        )
    }

    /// Detects whether iCloud sync capability is present.
    ///
    /// Requires an iCloud-related code-signing entitlement. When only a
    /// ubiquity-*container* entitlement is present (no KV-store id), also
    /// requires a resolvable ubiquity container URL or identity token.
    ///
    /// Unit tests pass explicit container/identity flags instead of calling
    /// real `FileManager` ubiquity APIs.
    static func detect(
        entitlements: [String: Any]?,
        ubiquityContainerURL: URL? = nil,
        hasUbiquityIdentity: Bool = false
    ) -> Bool {
        guard let entitlements, hasICloudEntitlement(entitlements) else {
            return false
        }

        if entitlements["com.apple.developer.ubiquity-kvstore-identifier"] != nil {
            return true
        }

        if ubiquityContainerURL != nil {
            return true
        }

        return hasUbiquityIdentity
    }

    static func hasICloudEntitlement(_ entitlements: [String: Any]) -> Bool {
        if entitlements["com.apple.developer.ubiquity-kvstore-identifier"] != nil {
            return true
        }
        if let containers = entitlements["com.apple.developer.ubiquity-container-identifiers"] as? [Any],
           !containers.isEmpty {
            return true
        }
        if let services = entitlements["com.apple.developer.icloud-services"] as? [Any],
           !services.isEmpty {
            return true
        }
        return false
    }

    /// Reads the running process's code-signing entitlements dictionary.
    static func codeSigningEntitlements() -> [String: Any]? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let info = info as? [String: Any] else {
            return nil
        }

        let key = kSecCodeInfoEntitlementsDict as String
        return info[key] as? [String: Any]
    }
}
