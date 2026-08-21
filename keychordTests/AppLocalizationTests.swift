import Testing
import Foundation
@testable import keychord

/// #51. The catalog match is what decides whether a language change can be
/// applied in place, so it is tested against explicit localization lists rather
/// than whatever this machine happens to be set to.
@Suite("AppLocalization")
struct AppLocalizationTests {

    private static let shipped = ["en", "zh-Hans"]

    @Test func exactLocalizationWins() {
        #expect(AppLocalization.localizationName(for: "zh-Hans", available: Self.shipped) == "zh-Hans")
        #expect(AppLocalization.localizationName(for: "en", available: Self.shipped) == "en")
    }

    @Test func matchingIgnoresCase() {
        #expect(AppLocalization.localizationName(for: "ZH-hans", available: Self.shipped) == "zh-Hans")
    }

    /// A catalog that ships plain `zh` still answers a `zh-Hans` request.
    @Test func fallsBackToTheBareLanguage() {
        #expect(AppLocalization.localizationName(for: "zh-Hans", available: ["en", "zh"]) == "zh")
    }

    /// And the other way round, for a request without a script subtag.
    @Test func fallsBackToARegionalVariant() {
        #expect(AppLocalization.localizationName(for: "zh", available: Self.shipped) == "zh-Hans")
    }

    @Test func aLanguageWeDoNotShipHasNoBundle() {
        #expect(AppLocalization.localizationName(for: "fr", available: Self.shipped) == nil)
    }

    /// Follow System passes no code: the bundle's own resolution is used.
    @Test func noCodeMeansNoOverride() {
        #expect(AppLocalization.localizationName(for: nil, available: Self.shipped) == nil)
        #expect(AppLocalization.localizationName(for: "", available: Self.shipped) == nil)
        #expect(AppLanguagePreference.system.appleLanguageCode == nil)
    }

    @Test func baseLocalizationDoesNotShadowAConcreteOne() {
        #expect(AppLocalization.localizationName(for: "en", available: ["Base", "en"]) == "en")
    }

    /// Language-neutral on purpose: this asserts the lookup answers at all, not
    /// what it answers, because the test machine's language is not fixed.
    @Test func codeBuiltStringsResolveToSomething() {
        let written = String.loc("Written")
        #expect(!written.isEmpty)
    }
}
