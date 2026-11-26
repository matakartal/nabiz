// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Foundation
import Testing
@testable import Nabiz

@Suite("Rust caches")
struct DevCachesTests {
    private func folder() throws -> String {
        let path = NSTemporaryDirectory() + "nabiz-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test("Only a folder cargo signed counts as a cache")
    func signature() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let real = root + "/app/target", fake = root + "/other/target"
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: fake, withIntermediateDirectories: true)
        try "Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cargo.\n"
            .write(toFile: real + "/CACHEDIR.TAG", atomically: true, encoding: .utf8)
        try "not cargo".write(toFile: fake + "/CACHEDIR.TAG", atomically: true, encoding: .utf8)
        #expect(DevCaches.isCargoCache(real))
        #expect(!DevCaches.isCargoCache(fake))
        #expect(!DevCaches.isCargoCache(root + "/missing/target"))
    }

    @Test("Delete refuses a folder without cargo's tag")
    func refusesUnsigned() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let plain = root + "/target"
        try FileManager.default.createDirectory(atPath: plain, withIntermediateDirectories: true)
        #expect(!DevCaches.delete(RustCache(path: plain, size: 0, lastBuilt: .distantPast)))
        #expect(FileManager.default.fileExists(atPath: plain))
    }

    @Test("A cache built in the last 10 minutes is active")
    func active() {
        #expect(RustCache(path: "/x/app/target", size: 0, lastBuilt: Date()).isActive)
        #expect(!RustCache(path: "/x/app/target", size: 0, lastBuilt: Date().addingTimeInterval(-3600)).isActive)
        #expect(RustCache(path: "/x/app/target", size: 0, lastBuilt: Date()).project == "app")
    }
}
