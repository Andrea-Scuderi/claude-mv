import Testing
import Foundation
@testable import ClaudeMVCore

@Suite("ConflictResolver")
struct ConflictResolverTests {
    private let fm = FileManager.default

    /// Creates a temporary fake `~/.claude` tree and returns its path.
    private func makeClaudeDir(subdirs: [String] = ["projects", "todos"]) throws -> String {
        let root = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        for sub in subdirs {
            try fm.createDirectory(
                atPath: "\(root)/\(sub)",
                withIntermediateDirectories: true
            )
        }
        return root
    }

    @Test func findsNoConflictsWhenDestinationIsFree() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let resolver = ConflictResolver(
            claudeDir: claudeDir,
            subdirs: ["projects", "todos"],
            fileManager: fm
        )
        #expect(resolver.findConflicts(newEncoded: "-Users-new").isEmpty)
    }

    @Test func detectsConflictInProjects() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let key = "-Users-new-project"
        try fm.createDirectory(
            atPath: "\(claudeDir)/projects/\(key)",
            withIntermediateDirectories: true
        )
        // Add a session file so sessionCount is exercised.
        try "{}".write(
            toFile: "\(claudeDir)/projects/\(key)/session.jsonl",
            atomically: true,
            encoding: .utf8
        )

        let resolver = ConflictResolver(
            claudeDir: claudeDir,
            subdirs: ["projects", "todos"],
            fileManager: fm
        )
        let conflicts = resolver.findConflicts(newEncoded: key)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].subdir == "projects")
        #expect(conflicts[0].sessionCount == 1)
    }

    @Test func detectsConflictsInMultipleSubdirs() throws {
        let claudeDir = try makeClaudeDir(subdirs: ["projects", "todos"])
        defer { try? fm.removeItem(atPath: claudeDir) }

        let key = "-Users-dup"
        for sub in ["projects", "todos"] {
            try fm.createDirectory(
                atPath: "\(claudeDir)/\(sub)/\(key)",
                withIntermediateDirectories: true
            )
        }

        let resolver = ConflictResolver(
            claudeDir: claudeDir,
            subdirs: ["projects", "todos"],
            fileManager: fm
        )
        #expect(resolver.findConflicts(newEncoded: key).count == 2)
    }

    @Test func cleanConflictsRemovesItems() throws {
        let claudeDir = try makeClaudeDir(subdirs: ["projects", "todos"])
        defer { try? fm.removeItem(atPath: claudeDir) }

        let key = "-Users-gone"
        for sub in ["projects", "todos"] {
            try fm.createDirectory(
                atPath: "\(claudeDir)/\(sub)/\(key)",
                withIntermediateDirectories: true
            )
        }

        let resolver = ConflictResolver(
            claudeDir: claudeDir,
            subdirs: ["projects", "todos"],
            fileManager: fm
        )
        try resolver.cleanConflicts(newEncoded: key)

        #expect(resolver.findConflicts(newEncoded: key).isEmpty)
    }
}
