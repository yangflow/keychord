import Testing
import Foundation
@testable import keychord

@Suite("AccountColor")
struct AccountColorTests {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    @Test func decodesLegacyNamedColors() throws {
        for name in ["blue", "green", "orange", "red", "purple", "yellow"] {
            let color = try decoder.decode(Account.AccountColor.self, from: Data("\"\(name)\"".utf8))
            #expect(color.rawValue == name)
        }
    }

    @Test func decodesHexColors() throws {
        let color = try decoder.decode(Account.AccountColor.self, from: Data("\"#1A2B3C\"".utf8))
        #expect(color.rawValue == "#1A2B3C")
        let components = try #require(color.sRGBComponents)
        #expect(abs(components.red - 26.0 / 255.0) < 0.001)
        #expect(abs(components.green - 43.0 / 255.0) < 0.001)
        #expect(abs(components.blue - 60.0 / 255.0) < 0.001)
        #expect(components.alpha == 1)
    }

    @Test func encodesHexFromSRGB() throws {
        let color = Account.AccountColor(sRGBRed: 1, green: 0.5, blue: 0)
        let data = try encoder.encode(color)
        let raw = String(data: data, encoding: .utf8)
        #expect(raw == "\"#FF8000\"")
    }

    @Test func accountRoundTripKeepsLegacyColorName() throws {
        var account = Account.new(
            label: "Work",
            sshAlias: "github-work",
            keyPath: "~/.ssh/id",
            gitUserName: "Ada",
            gitUserEmail: "ada@example.com",
            color: .blue
        )
        account.username = "ada"
        let data = try encoder.encode(account)
        let decoded = try decoder.decode(Account.self, from: data)
        #expect(decoded.color == .blue)
        #expect(decoded.color.rawValue == "blue")
    }

    @Test func accountRoundTripKeepsHexColor() throws {
        var account = Account.new(
            label: "Work",
            sshAlias: "github-work",
            keyPath: "~/.ssh/id",
            gitUserName: "Ada",
            gitUserEmail: "ada@example.com",
            color: Account.AccountColor(rawValue: "#AABBCC")
        )
        account.username = "ada"
        let data = try encoder.encode(account)
        let decoded = try decoder.decode(Account.self, from: data)
        #expect(decoded.color.rawValue == "#AABBCC")
    }

    @Test func presetsMatchFormerEnumCases() {
        #expect(Account.AccountColor.presets.map(\.rawValue) == [
            "blue", "green", "orange", "red", "purple", "yellow",
        ])
        #expect(Account.AccountColor.allCases == Account.AccountColor.presets)
    }
}
