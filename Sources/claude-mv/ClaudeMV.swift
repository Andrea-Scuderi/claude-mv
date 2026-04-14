import ArgumentParser
import ClaudeMVCore
import Foundation

@main
struct ClaudeMV: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-mv",
        abstract: "Move a project directory and migrate its Claude Code context.",
        discussion: """
            Renames a project directory on disk and updates all associated Claude Code context
            (session history, todos, shell snapshots, etc.) so that future sessions pick up
            where the old path left off.

            Use --already-moved when the directory has already been renamed by another tool.
            In that case, old_directory must be the original *absolute* path (it no longer
            needs to exist on disk).
            """,
        version: "1.0.0-alpha.1"
    )

    @Flag(name: .long, help: "Skip the directory rename; only migrate Claude context.")
    var alreadyMoved = false

    @Argument(help: "Original project directory path.")
    var oldDirectory: String

    @Argument(help: "New project directory path.")
    var newDirectory: String

    mutating func run() throws {
        let fm = FileManager.default

        // --- Environment ---
        guard let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty else {
            throw ValidationError("HOME environment variable is not set.")
        }
        let claudeDir = "\(home)/.claude"
        guard isDirectory(claudeDir) else {
            throw ValidationError("Claude directory does not exist: \(claudeDir)")
        }

        // --- Path resolution ---
        let oldAbs: String
        let newAbsFuture: String

        if alreadyMoved {
            var stripped = oldDirectory
            while stripped.hasSuffix("/") && stripped.count > 1 { stripped.removeLast() }
            guard stripped.hasPrefix("/") else {
                throw ValidationError(
                    "With --already-moved, old_directory must be an absolute path: \(oldDirectory)"
                )
            }
            oldAbs = stripped

            let expandedNew = makeAbsolute(newDirectory)
            guard isDirectory(expandedNew) else {
                throw ValidationError(
                    "New directory does not exist: \(newDirectory)\n" +
                    "       (with --already-moved the new directory must already be in place)"
                )
            }
            newAbsFuture = URL(fileURLWithPath: expandedNew).resolvingSymlinksInPath().path

        } else {
            let expandedOld = makeAbsolute(oldDirectory)
            if isSymlink(expandedOld) {
                throw ValidationError("\(oldDirectory) is a symlink — move the symlink manually.")
            }
            guard fm.fileExists(atPath: expandedOld) else {
                throw ValidationError("Old directory does not exist: \(oldDirectory)")
            }
            oldAbs = URL(fileURLWithPath: expandedOld).resolvingSymlinksInPath().path

            let expandedNew = makeAbsolute(newDirectory)
            guard !fm.fileExists(atPath: expandedNew) else {
                throw ValidationError("New directory already exists: \(newDirectory)")
            }
            let parentOfNew = (expandedNew as NSString).deletingLastPathComponent
            let baseOfNew   = (expandedNew as NSString).lastPathComponent
            let resolvedParent = URL(fileURLWithPath: parentOfNew).resolvingSymlinksInPath().path
            guard isDirectory(resolvedParent) else {
                throw ValidationError("Parent directory does not exist: \(parentOfNew)")
            }
            newAbsFuture = resolvedParent + "/" + baseOfNew
        }

        // --- Encode paths ---
        let oldEncoded = encodePath(oldAbs)
        let newEncoded = encodePath(newAbsFuture)

        let subdirs = ["projects", "file-history", "todos", "shell-snapshots", "debug"]
        let resolver = ConflictResolver(claudeDir: claudeDir, subdirs: subdirs)
        let migrator = ContextMigrator(claudeDir: claudeDir, subdirs: subdirs)

        // --- Conflict check ---
        let conflicts = resolver.findConflicts(newEncoded: newEncoded)
        if !conflicts.isEmpty {
            print("Warning: Claude context already exists for \(newAbsFuture):")
            for info in conflicts {
                let suffix = info.sessionCount.map { " (\($0) sessions)" } ?? ""
                print("  - \(info.subdir)\(suffix)")
            }
            print("""

    Options:
      [c] Clean out existing context and continue
      [m] Merge old context into existing context
      [n] Abort (default)

    """, terminator: "")
            print("Choose [c/m/N]: ", terminator: "")
            fflush(stdout)
            let reply = (readLine() ?? "").lowercased().trimmingCharacters(in: .whitespaces)

            switch reply {
            case "c":
                print("Cleaning out existing context for \(newAbsFuture)...")
                try resolver.cleanConflicts(newEncoded: newEncoded)
                for info in conflicts { print("  ✓ Removed \(info.subdir)") }
                print()
            case "m":
                print("Will merge contexts...")
            default:
                print("Aborted.")
                throw ExitCode.failure
            }
        }

        // --- Migrate Claude context ---
        print("Moving Claude context from:")
        print("  \(oldAbs)")
        print("  → \(newAbsFuture)")
        print()

        let moved = try migrator.migrateContext(oldEncoded: oldEncoded, newEncoded: newEncoded)
        if moved == 0 {
            print("No Claude context found for \(oldAbs)")
        } else {
            print("✓ Moved \(moved) context location(s)")
        }
        print()

        // --- Patch session files ---
        let failures = try migrator.patchSessionFiles(
            newEncoded: newEncoded,
            oldAbs: oldAbs,
            newAbs: newAbsFuture
        )
        if moved > 0 || !failures.isEmpty {
            print("Updating session file references...")
            for (file, error) in failures {
                fputs("Warning: could not patch \(file): \(error.localizedDescription)\n", stderr)
            }
            if failures.isEmpty { print("✓ Updated session files") }
            print()
        }

        // --- Move directory (normal mode only) ---
        let newAbs: String
        if alreadyMoved {
            print("(Directory already moved — skipping mv)")
            print()
            newAbs = newAbsFuture
        } else {
            let expandedNew = makeAbsolute(newDirectory)
            if fm.fileExists(atPath: expandedNew) {
                throw ValidationError(
                    "\(newDirectory) was created by another process between checks — aborting."
                )
            }
            print("Moving directory:")
            print("  \(oldAbs)")
            print("  → \(newDirectory)")
            do {
                try fm.moveItem(atPath: oldAbs, toPath: expandedNew)
            } catch {
                throw ValidationError("Could not move directory: \(error.localizedDescription)")
            }
            newAbs = URL(fileURLWithPath: expandedNew).resolvingSymlinksInPath().path
            print("✓ Directory moved")
            print()
        }

        // --- Patch history.jsonl ---
        if let backupName = try migrator.patchHistoryFile(oldAbs: oldAbs, newAbs: newAbs) {
            print("Updating history.jsonl references...")
            print("✓ Updated history.jsonl (backup: \(backupName))")
        }
    }
}
