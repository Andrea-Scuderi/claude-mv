import Testing
import Foundation
@testable import ClaudeMVCore

@Suite("encodePath")
struct EncodePathTests {
    @Test func slashesBecomeDashes() {
        #expect(encodePath("/Users/alice/my-project") == "-Users-alice-my-project")
    }

    @Test func dotsBecomeDashes() {
        #expect(encodePath("/Users/alice/my.project") == "-Users-alice-my-project")
    }

    @Test func emptyStringRemainsEmpty() {
        #expect(encodePath("") == "")
    }

    @Test func rootSlash() {
        #expect(encodePath("/") == "-")
    }
}

@Suite("makeAbsolute")
struct MakeAbsoluteTests {
    @Test func absolutePathReturnedUnchanged() {
        #expect(makeAbsolute("/foo/bar") == "/foo/bar")
    }

    @Test func dotDotResolved() {
        #expect(makeAbsolute("/foo/bar/../baz") == "/foo/baz")
    }

    @Test func relativePrependsCurrentDirectory() {
        let result = makeAbsolute("subdir", currentDirectory: "/home/alice")
        #expect(result == "/home/alice/subdir")
    }

    @Test func tildeExpanded() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let result = makeAbsolute("~/projects")
        #expect(result == "\(home)/projects")
    }
}

@Suite("isDirectory / isSymlink")
struct FileTypeTests {
    @Test func temporaryDirectoryIsDirectory() {
        #expect(isDirectory(FileManager.default.temporaryDirectory.path))
    }

    @Test func nonExistentPathIsNotDirectory() {
        #expect(!isDirectory("/nonexistent/path/\(UUID().uuidString)"))
    }

    @Test func regularFileIsNotDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(!isDirectory(tmp.path))
    }

    @Test func regularFileIsNotSymlink() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(!isSymlink(tmp.path))
    }

    @Test func symlinkDetected() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let link = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: base)
            try? fm.removeItem(at: link)
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: base)
        #expect(isSymlink(link.path))
    }
}
