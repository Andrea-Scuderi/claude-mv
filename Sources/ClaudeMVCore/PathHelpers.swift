import Foundation

/// Returns true if `path` points to a directory (follows symlinks).
public func isDirectory(_ path: String, using fm: FileManager = .default) -> Bool {
    var isDir: ObjCBool = false
    return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
}

/// Returns true if `path` is a symbolic link.
public func isSymlink(_ path: String, using fm: FileManager = .default) -> Bool {
    guard let attrs = try? fm.attributesOfItem(atPath: path) else { return false }
    return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
}

/// Expands `~`, prepends `currentDirectory` for relative paths, resolves `.` and `..` syntactically.
public func makeAbsolute(
    _ path: String,
    currentDirectory: String = FileManager.default.currentDirectoryPath
) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") {
        return URL(fileURLWithPath: expanded).standardized.path
    }
    return URL(fileURLWithPath: currentDirectory + "/" + expanded).standardized.path
}

/// Replaces every `/` and `.` with `-`, matching Claude's internal project-key format.
///
/// - Note: Paths that differ only by `/` vs `.` at the same position (e.g. `my.project` vs
///   `my/project`) will produce identical keys. Back up `~/.claude` before running if this
///   may affect you.
public func encodePath(_ path: String) -> String {
    path
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ".", with: "-")
}
