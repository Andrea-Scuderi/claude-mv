# claude-mv

A command-line tool that renames a project directory **and** migrates all associated
Claude Code context (sessions, history, todos, file-history, shell snapshots) to
match the new path.

---

## The Problem

Claude Code stores per-project context under `~/.claude/` using the project's
absolute path as a key. When you rename or move a project directory — whether
with `mv`, Finder, or an IDE — Claude can no longer find that context. From
Claude's perspective, you are now working in a brand-new project with no history.

`claude-mv` fixes this by renaming both the directory on disk and every matching
entry inside `~/.claude/` in one atomic operation.

---

## Analogy

Think of `~/.claude/` as a **filing cabinet** where every drawer is labelled with
a project's full path. When you rename the project folder on disk, the drawer
labels are not updated — Claude cannot find anything.

`claude-mv` is the office assistant who:

1. Re-labels every matching drawer before touching the folder.
2. Opens every document inside and crosses out the old address, writing the new one.
3. Only then physically moves the folder.

---

## How It Works

See [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for the full pipeline diagram and step-by-step walkthrough.

---

## Usage

### Rename a project directory

```bash
claude-mv ~/projects/old-name ~/projects/new-name
```

### Move a project to a different location

```bash
claude-mv ~/projects/my-app /work/clients/acme/my-app
```

### Directory already renamed on disk

Use `--already-moved` when you have already renamed the directory yourself (via
Finder, an IDE, or `mv`) and only need to migrate the Claude context. The old
path must be the **original absolute path** (it no longer needs to exist on disk).
The new directory must already be in place.

```bash
claude-mv --already-moved /Users/alice/old-name ~/projects/new-name
```

---

## Building

Requires Swift 6.3+ (ships with Xcode 26 or the Swift toolchain).

```bash
# Build
swift build -c release

# Run directly
.build/release/claude-mv ~/old-project ~/new-project

# Install to /usr/local/bin
cp .build/release/claude-mv /usr/local/bin/claude-mv
```

### Running the tests

```bash
swift test
```

---

## Project Structure

```
Sources/
  ClaudeMVCore/          # Reusable library (imported by the executable and tests)
    PathHelpers.swift    # isDirectory, isSymlink, makeAbsolute, encodePath
    FileReplacer.swift   # literalReplace — UTF-8 in-place string substitution
    ConflictResolver.swift  # Detect and remove conflicting context entries
    ContextMigrator.swift   # migrateContext, patchSessionFiles, patchHistoryFile
  claude-mv/
    ClaudeMove.swift     # @main entry point — ArgumentParser ParsableCommand
Tests/
  claude-mvTests/
    PathHelpersTests.swift
    FileReplacerTests.swift
    ConflictResolverTests.swift
    ContextMigratorTests.swift
```

---

## Known Limitation: Path Encoding Collision

Claude's internal encoding maps both `/` and `.` to `-`. This means two different
paths that differ only by a `/` vs `.` at the same position will produce the
**same** key:

```
/home/user/my.project   →  -home-user-my-project
/home/user/my-project   →  -home-user-my-project  (identical!)
```

If you have projects whose names differ only by a dot vs a hyphen, **back up
`~/.claude/` before running this tool**.

---

## Requirements

- Swift 6.3+ (Xcode 26 or standalone Swift toolchain)
- macOS
