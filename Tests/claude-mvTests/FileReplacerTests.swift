import Testing
import Foundation
@testable import ClaudeMVCore

@Suite("literalReplace")
struct FileReplacerTests {
    private func tempFile(content: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test func replacesOccurrence() throws {
        let path = try tempFile(content: "hello /old/path world")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try literalReplace(file: path, old: "/old/path", new: "/new/path")
        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result == "hello /new/path world")
    }

    @Test func replacesAllOccurrences() throws {
        let path = try tempFile(content: "/old /old /old")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try literalReplace(file: path, old: "/old", new: "/new")
        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result == "/new /new /new")
    }

    @Test func noMatchLeavesFileUnchanged() throws {
        let original = "nothing to replace here"
        let path = try tempFile(content: original)
        defer { try? FileManager.default.removeItem(atPath: path) }
        try literalReplace(file: path, old: "/old", new: "/new")
        let result = try String(contentsOfFile: path, encoding: .utf8)
        #expect(result == original)
    }

    @Test func throwsForNonexistentFile() {
        #expect(throws: (any Error).self) {
            try literalReplace(
                file: "/nonexistent/\(UUID().uuidString).txt",
                old: "x",
                new: "y"
            )
        }
    }
}
