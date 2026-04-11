import Testing
import Foundation
@testable import keychord

@Suite("KeygenService")
struct KeygenServiceTests {

    static func withTempDir(_ test: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keychord-keygen-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(dir.path)
    }

    @Test func generatesEd25519KeyPair() throws {
        try Self.withTempDir { dir in
            let result = try KeygenService.generateSync(
                type: .ed25519,
                name: "id_test",
                comment: "test@example.com",
                directory: dir
            )
            #expect(FileManager.default.fileExists(atPath: result.privateKeyPath))
            #expect(FileManager.default.fileExists(atPath: result.publicKeyPath))
            #expect(result.publicKeyContent.hasPrefix("ssh-ed25519 "))
            #expect(result.publicKeyContent.contains("test@example.com"))
        }
    }

    @Test func generatesRSA4096KeyPair() throws {
        try Self.withTempDir { dir in
            let result = try KeygenService.generateSync(
                type: .rsa4096,
                name: "id_rsa_test",
                comment: "rsa@example.com",
                directory: dir
            )
            #expect(FileManager.default.fileExists(atPath: result.privateKeyPath))
            #expect(result.publicKeyContent.hasPrefix("ssh-rsa "))
        }
    }

    @Test func rejectsExistingPrivateKeyPath() throws {
        try Self.withTempDir { dir in
            let privPath = (dir as NSString).appendingPathComponent("id_existing")
            try "pretend private key".write(toFile: privPath, atomically: true, encoding: .utf8)

            #expect(throws: KeygenService.KeygenError.self) {
                _ = try KeygenService.generateSync(
                    type: .ed25519,
                    name: "id_existing",
                    comment: "x@example.com",
                    directory: dir
                )
            }
        }
    }

    @Test func rejectsExistingPublicKeyPath() throws {
        try Self.withTempDir { dir in
            let pubPath = (dir as NSString).appendingPathComponent("id_orphan.pub")
            try "ssh-ed25519 AAAAblah".write(toFile: pubPath, atomically: true, encoding: .utf8)

            #expect(throws: KeygenService.KeygenError.self) {
                _ = try KeygenService.generateSync(
                    type: .ed25519,
                    name: "id_orphan",
                    comment: "x@example.com",
                    directory: dir
                )
            }
        }
    }

    @Test func rejectsInvalidNames() throws {
        try Self.withTempDir { dir in
            for badName in [
                "",
                "   ",
                "has/slash",
                ".hidden",
                "has..dotdot",
                "has\nnewline",
                "has\\backslash",
                "has$dollar",
                "has space"
            ] {
                #expect(throws: KeygenService.KeygenError.self) {
                    _ = try KeygenService.generateSync(
                        type: .ed25519,
                        name: badName,
                        comment: "x@example.com",
                        directory: dir
                    )
                }
            }
        }
    }

    @Test func isValidKeyNameWhitelistsSafeChars() {
        #expect(KeygenService.isValidKeyName("id_ed25519"))
        #expect(KeygenService.isValidKeyName("key-name_v2.3"))
        #expect(!KeygenService.isValidKeyName(""))
        #expect(!KeygenService.isValidKeyName("../escape"))
        #expect(!KeygenService.isValidKeyName("id_rsa\0null"))
    }

    @Test func stripsNewlinesFromComment() throws {
        try Self.withTempDir { dir in
            let result = try KeygenService.generateSync(
                type: .ed25519,
                name: "id_comment_test",
                comment: "first line\nmalicious ssh-rsa AAAA",
                directory: dir
            )
            // .pub content should have the comment merged into one line
            #expect(!result.publicKeyContent.contains("\nmalicious"))
            #expect(result.publicKeyContent.contains("first line"))
        }
    }

    @Test func trimsWhitespaceInName() throws {
        try Self.withTempDir { dir in
            let result = try KeygenService.generateSync(
                type: .ed25519,
                name: "  id_whitespace  ",
                comment: "x@example.com",
                directory: dir
            )
            #expect(result.privateKeyPath.hasSuffix("id_whitespace"))
        }
    }
}
