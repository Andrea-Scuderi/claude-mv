import Testing
import Foundation
@testable import ClaudeMVCore

@Suite("ContextMigrator")
struct ContextMigratorTests {
    private let fm = FileManager.default
    private let subdirs = ["projects", "todos", "shell-snapshots"]

    /// Builds a minimal fake `~/.claude` directory tree.
    private func makeClaudeDir() throws -> String {
        let root = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        for sub in subdirs {
            try fm.createDirectory(atPath: "\(root)/\(sub)", withIntermediateDirectories: true)
        }
        return root
    }

    // MARK: migrateContext

    @Test func migratesDirectoryToNewKey() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let oldKey = "-Users-old-proj"
        let newKey = "-Users-new-proj"
        let oldDir = "\(claudeDir)/projects/\(oldKey)"
        try fm.createDirectory(atPath: oldDir, withIntermediateDirectories: true)
        try "session".write(toFile: "\(oldDir)/s.jsonl", atomically: true, encoding: .utf8)

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let count = try migrator.migrateContext(oldEncoded: oldKey, newEncoded: newKey)

        #expect(count == 1)
        #expect(fm.fileExists(atPath: "\(claudeDir)/projects/\(newKey)"))
        #expect(!fm.fileExists(atPath: oldDir))
    }

    @Test func returnsZeroWhenNoContextExists() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let count = try migrator.migrateContext(
            oldEncoded: "-Users-ghost",
            newEncoded: "-Users-new"
        )
        #expect(count == 0)
    }

    @Test func mergesIntoExistingDestinationDirectory() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let oldKey = "-Users-src"
        let newKey = "-Users-dst"
        let oldDir = "\(claudeDir)/projects/\(oldKey)"
        let newDir = "\(claudeDir)/projects/\(newKey)"

        try fm.createDirectory(atPath: oldDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: newDir, withIntermediateDirectories: true)
        try "old session".write(toFile: "\(oldDir)/old.jsonl", atomically: true, encoding: .utf8)
        try "new session".write(toFile: "\(newDir)/new.jsonl", atomically: true, encoding: .utf8)

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        _ = try migrator.migrateContext(oldEncoded: oldKey, newEncoded: newKey)

        // Both session files should now live under newKey.
        let contents = try fm.contentsOfDirectory(atPath: newDir)
        #expect(contents.contains("old.jsonl"))
        #expect(contents.contains("new.jsonl"))
        #expect(!fm.fileExists(atPath: oldDir))
    }

    @Test func migratesMultipleSubdirs() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let oldKey = "-Users-old"
        let newKey = "-Users-new"
        for sub in ["projects", "todos"] {
            try fm.createDirectory(
                atPath: "\(claudeDir)/\(sub)/\(oldKey)",
                withIntermediateDirectories: true
            )
        }

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let count = try migrator.migrateContext(oldEncoded: oldKey, newEncoded: newKey)

        #expect(count == 2)
    }

    // MARK: patchSessionFiles

    @Test func patchesPathInSessionFiles() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let key = "-Users-new-proj"
        let projDir = "\(claudeDir)/projects/\(key)"
        try fm.createDirectory(atPath: projDir, withIntermediateDirectories: true)
        try #"{"cwd":"/Users/old/proj"}"#.write(
            toFile: "\(projDir)/s.jsonl",
            atomically: true,
            encoding: .utf8
        )

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let failures = try migrator.patchSessionFiles(
            newEncoded: key,
            oldAbs: "/Users/old/proj",
            newAbs: "/Users/new/proj"
        )

        #expect(failures.isEmpty)
        let result = try String(contentsOfFile: "\(projDir)/s.jsonl", encoding: .utf8)
        #expect(result == #"{"cwd":"/Users/new/proj"}"#)
    }

    @Test func returnsEmptyWhenNoProjectsDir() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let failures = try migrator.patchSessionFiles(
            newEncoded: "-no-such-key",
            oldAbs: "/old",
            newAbs: "/new"
        )
        #expect(failures.isEmpty)
    }

    // MARK: patchHistoryFile

    @Test func patchesHistoryAndCreatesBackup() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let historyFile = "\(claudeDir)/history.jsonl"
        try #"{"cwd":"/Users/old/proj"}"#.write(
            toFile: historyFile,
            atomically: true,
            encoding: .utf8
        )

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let backupName = try migrator.patchHistoryFile(
            oldAbs: "/Users/old/proj",
            newAbs: "/Users/new/proj"
        )

        #expect(backupName != nil)
        let result = try String(contentsOfFile: historyFile, encoding: .utf8)
        #expect(result == #"{"cwd":"/Users/new/proj"}"#)

        let backupPath = "\(claudeDir)/\(backupName!)"
        #expect(fm.fileExists(atPath: backupPath))
    }

    @Test func returnsNilWhenNoHistoryFile() throws {
        let claudeDir = try makeClaudeDir()
        defer { try? fm.removeItem(atPath: claudeDir) }

        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs, fileManager: fm)
        let backupName = try migrator.patchHistoryFile(oldAbs: "/old", newAbs: "/new")
        #expect(backupName == nil)
    }
}
