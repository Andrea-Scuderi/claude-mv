import Foundation

/// Handles moving Claude context directories and patching path references inside session files.
public struct ContextMigrator {
    public let claudeDir: String
    public let subdirs: [String]
    private let fileManager: FileManager

    public init(
        claudeDir: String,
        subdirs: [String] = ["projects", "file-history", "todos", "shell-snapshots", "debug"],
        fileManager: FileManager = .default
    ) {
        self.claudeDir = claudeDir
        self.subdirs = subdirs
        self.fileManager = fileManager
    }

    /// Moves (or merges) all tracked context subdirectories from `oldEncoded` to `newEncoded`.
    ///
    /// When the destination already exists as a directory the contents are merged in rather than
    /// overwriting. Returns the number of subdirectory entries that were acted upon.
    public func migrateContext(oldEncoded: String, newEncoded: String) throws -> Int {
        var moved = 0
        for subdir in subdirs {
            let oldPath = "\(claudeDir)/\(subdir)/\(oldEncoded)"
            let newPath = "\(claudeDir)/\(subdir)/\(newEncoded)"

            var isOldDir: ObjCBool = false
            guard fileManager.fileExists(atPath: oldPath, isDirectory: &isOldDir) else { continue }

            if isOldDir.boolValue && isDirectory(newPath, using: fileManager) {
                // Merge: move individual items into the existing destination directory.
                let contents = (try? fileManager.contentsOfDirectory(atPath: oldPath)) ?? []
                for entry in contents {
                    let src = "\(oldPath)/\(entry)"
                    let dst = "\(newPath)/\(entry)"
                    try? fileManager.moveItem(atPath: src, toPath: dst)
                }
                try? fileManager.removeItem(atPath: oldPath)
            } else {
                try fileManager.moveItem(atPath: oldPath, toPath: newPath)
            }
            moved += 1
        }
        return moved
    }

    /// Rewrites occurrences of `oldAbs` to `newAbs` inside every `.jsonl` session file found
    /// under the `projects/<newEncoded>` directory.
    ///
    /// Returns a list of `(file, error)` pairs for files that could not be patched; the rest of
    /// the session files are still processed.
    public func patchSessionFiles(
        newEncoded: String,
        oldAbs: String,
        newAbs: String
    ) throws -> [(file: String, error: Error)] {
        let projectsPath = "\(claudeDir)/projects/\(newEncoded)"
        guard isDirectory(projectsPath, using: fileManager) else { return [] }

        var jsonlFiles: [String] = []
        if let enumerator = fileManager.enumerator(atPath: projectsPath) {
            while let entry = enumerator.nextObject() as? String {
                guard entry.hasSuffix(".jsonl") else { continue }
                jsonlFiles.append("\(projectsPath)/\(entry)")
            }
        }

        var failures: [(file: String, error: Error)] = []
        for file in jsonlFiles {
            do {
                try literalReplace(file: file, old: oldAbs, new: newAbs)
            } catch {
                failures.append((file: file, error: error))
            }
        }
        return failures
    }

    /// Backs up and then patches `~/.claude/history.jsonl`, replacing `oldAbs` with `newAbs`.
    ///
    /// Returns the basename of the backup file, or `nil` if `history.jsonl` does not exist.
    public func patchHistoryFile(oldAbs: String, newAbs: String) throws -> String? {
        let historyFile = "\(claudeDir)/history.jsonl"
        guard fileManager.fileExists(atPath: historyFile) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let backupFile = "\(historyFile).\(formatter.string(from: Date())).backup"

        try fileManager.copyItem(atPath: historyFile, toPath: backupFile)
        try literalReplace(file: historyFile, old: oldAbs, new: newAbs)
        return (backupFile as NSString).lastPathComponent
    }
}
