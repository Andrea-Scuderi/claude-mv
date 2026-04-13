import Foundation

/// Performs a literal (non-regex) in-place string replacement in a UTF-8 text file.
public func literalReplace(file: String, old: String, new: String) throws {
    let content = try String(contentsOfFile: file, encoding: .utf8)
    let updated = content.replacingOccurrences(of: old, with: new)
    try updated.write(toFile: file, atomically: true, encoding: .utf8)
}
