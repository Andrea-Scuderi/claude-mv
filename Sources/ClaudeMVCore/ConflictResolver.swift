import Foundation

/// Describes a single piece of existing Claude context that conflicts with the destination key.
public struct ConflictInfo {
    /// The subdirectory name inside `~/.claude` (e.g. `"projects"`, `"todos"`).
    public let subdir: String
    /// Number of `.jsonl` session files found, only populated for the `"projects"` subdir.
    public let sessionCount: Int?

    public init(subdir: String, sessionCount: Int?) {
        self.subdir = subdir
        self.sessionCount = sessionCount
    }
}

/// Detects and removes existing Claude context that would conflict with a rename destination.
public struct ConflictResolver {
    private let claudeDir: String
    private let subdirs: [String]
    private let fileManager: FileManager

    public init(claudeDir: String, subdirs: [String], fileManager: FileManager = .default) {
        self.claudeDir = claudeDir
        self.subdirs = subdirs
        self.fileManager = fileManager
    }

    /// Returns all subdirectories that already contain context for `newEncoded`.
    public func findConflicts(newEncoded: String) -> [ConflictInfo] {
        subdirs.compactMap { subdir in
            let candidate = "\(claudeDir)/\(subdir)/\(newEncoded)"
            guard fileManager.fileExists(atPath: candidate) else { return nil }
            let sessionCount: Int? = subdir == "projects"
                ? (try? fileManager.contentsOfDirectory(atPath: candidate))?
                    .filter { $0.hasSuffix(".jsonl") }.count
                : nil
            return ConflictInfo(subdir: subdir, sessionCount: sessionCount)
        }
    }

    /// Removes all context entries for `newEncoded` across every tracked subdirectory.
    public func cleanConflicts(newEncoded: String) throws {
        for subdir in subdirs {
            let path = "\(claudeDir)/\(subdir)/\(newEncoded)"
            guard fileManager.fileExists(atPath: path) else { continue }
            try fileManager.removeItem(atPath: path)
        }
    }
}
