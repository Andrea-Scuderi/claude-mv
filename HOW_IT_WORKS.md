# How It Works

```
claude-mv [--already-moved] <old_directory> <new_directory>
                │
                ▼
┌─────────────────────────────────────┐
│  VALIDATE                           │
│  - $HOME set, ~/.claude/ exists     │
│  - old_dir not a symlink            │
│  - old_dir exists on disk           │
│  - new_dir does NOT exist yet       │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  ENCODE PATHS                       │
│  Every / and . → -                  │
│  /Users/alice/my.app                │
│        → -Users-alice-my-app        │
│  (matches Claude's internal format) │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  CONFLICT CHECK  (pre-move)         │
│  Does ~/.claude/{projects,          │
│  file-history, todos, ...}/NEW_KEY  │
│  already exist?                     │
│    YES → prompt: [c]lean / [m]erge  │
│                / [n] abort          │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  MIGRATE CLAUDE CONTEXT             │
│  For each of 5 subdirectories:      │
│    projects  file-history  todos    │
│    shell-snapshots  debug           │
│                                     │
│  OLD_KEY dir/file → NEW_KEY         │
│  (merge if both sides exist)        │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  PATCH SESSION FILES                │
│  ~/.claude/projects/NEW_KEY/*.jsonl │
│  literal str.replace(old, new)      │  no regex — safe for special characters
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  TOCTOU RE-CHECK                    │
│  Is new_dir still free?             │
│  (skipped with --already-moved)     │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  mv old_dir new_dir                 │  skipped with --already-moved
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│  PATCH history.jsonl                │
│  literal str.replace(old, new)      │
│  timestamped backup created first   │
└─────────────────────────────────────┘
```

---

## Step-by-Step Walkthrough

### 1. Flag and argument parsing

`--already-moved` is an optional flag that skips the physical directory rename.
It is useful when the directory has already been renamed by another tool (Finder,
an IDE, `git mv`, etc.) and only the Claude context needs to be updated.

It is exposed as an `ArgumentParser` `@Flag` on the `ClaudeMV` command.

### 2. Environment validation

Before touching anything the tool verifies that `$HOME` is set and that
`~/.claude/` exists. This prevents a missing `$HOME` from silently expanding
`CLAUDE_DIR` to `/.claude` and operating on root-owned files.

### 3. Source path resolution

**Normal mode** — the source directory must exist and must not be a symlink.
The path is resolved to an absolute, symlink-free form.

**`--already-moved` mode** — the source directory is already gone. The argument
is used as a literal string. An absolute path is required because there is nothing
to resolve on disk.

The destination path is resolved in both modes: if it is relative, its parent is
resolved and the basename is appended, failing explicitly if the parent does not
exist.

### 4. Path encoding (`PathHelpers.encodePath`)

Claude stores context in directories whose names are derived from the project
path by replacing every `/` and `.` with `-`:

```
/Users/alice/my.app  →  -Users-alice-my-app
```

Both encoded values are checked for emptiness before any filesystem operations
are attempted — an empty key would expand to `~/.claude/projects/`, which would
affect all projects.

### 5. Conflict check (`ConflictResolver`)

*Before moving anything*, the tool checks whether any of the five Claude
context subdirectories already contain an entry for the destination key. If so,
the user is prompted interactively:

| Choice | Behaviour |
|--------|-----------|
| `c` | Delete destination context, then proceed |
| `m` | Merge: files from old are moved into existing destination |
| `n` (default) | Abort with no changes made |

### 6. Context migration (`ContextMigrator.migrateContext`)

Iterates the five subdirectories (`projects`, `file-history`, `todos`,
`shell-snapshots`, `debug`). For each one it either renames the entry (simple
case) or merges it — moves all items from the old directory into the existing
destination directory, then removes the now-empty source.

### 7. Session file patching (`ContextMigrator.patchSessionFiles`)

Every `.jsonl` session file contains the project's absolute path embedded in
JSON records. A **literal** string replacement is performed on each file — no
regex — so special characters in paths (`&`, `\`, `|`) cannot corrupt the
result. Per-file errors are collected and reported as warnings; the remaining
files are still processed.

### 8. TOCTOU re-check

A second existence check on the destination immediately before the rename
narrows the race window between the initial validation and the actual `mv`.
Skipped when `--already-moved` is set.

### 9. Directory move

The physical directory is renamed **last**, after all Claude context has already
been updated. This ensures that if the rename fails (e.g. cross-device move),
the Claude context still reflects reality and nothing is left in a half-migrated
state. Skipped when `--already-moved` is set.

### 10. History patching (`ContextMigrator.patchHistoryFile`)

`~/.claude/history.jsonl` is a global command history shared across all projects.
It too embeds absolute path references. A timestamped backup
(`history.jsonl.YYYYMMDDHHMMSS.backup`) is created before the file is modified,
so previous backups are never silently overwritten.
