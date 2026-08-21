import AppKit
import Foundation
import Observation

/// In-app UI language: Follow System, English, or Simplified Chinese.
enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    /// BCP-47 tag written to `AppleLanguages`, or `nil` to follow the system.
    var appleLanguageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            Locale.autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .simplifiedChinese:
            Locale(identifier: "zh-Hans")
        }
    }
}

/// Persists the language choice, mirrors it into `AppleLanguages` for
/// `String(localized:)`, and exposes a SwiftUI `Locale` for live `Text` updates.
///
/// Catalog lookups via `String(localized:)` generally need a process relaunch
/// after `AppleLanguages` changes; the Settings UI surfaces that and offers relaunch.
@MainActor
@Observable
final class AppLanguageStore {
    static let preferenceKey = "keychord.appLanguage"

    private let defaults: UserDefaults

    var preference: AppLanguagePreference {
        didSet {
            guard oldValue != preference else { return }
            defaults.set(preference.rawValue, forKey: Self.preferenceKey)
            Self.applyAppleLanguages(preference, defaults: defaults)
            pendingRelaunch = true
        }
    }

    /// True after the user changes language until they relaunch (or dismiss).
    var pendingRelaunch = false

    var locale: Locale { preference.locale }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.preferenceKey),
           let stored = AppLanguagePreference(rawValue: raw) {
            self.preference = stored
        } else {
            self.preference = .system
        }
    }

    /// Call once at process start so `String(localized:)` matches the saved choice.
    static func bootstrapAppleLanguages(defaults: UserDefaults = .standard) {
        let preference: AppLanguagePreference
        if let raw = defaults.string(forKey: preferenceKey),
           let stored = AppLanguagePreference(rawValue: raw) {
            preference = stored
        } else {
            preference = .system
        }
        applyAppleLanguages(preference, defaults: defaults)
    }

    static func applyAppleLanguages(
        _ preference: AppLanguagePreference,
        defaults: UserDefaults = .standard
    ) {
        if let code = preference.appleLanguageCode {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Relaunches the app bundle, then terminates this process.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
