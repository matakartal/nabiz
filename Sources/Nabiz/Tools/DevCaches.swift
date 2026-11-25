import Foundation

/// A Rust build cache: a Cargo `target` folder. Cargo marks each one with a CACHEDIR.TAG file carrying a fixed
/// signature, so only real build caches are ever picked up — never a folder that merely happens to be called "target".
struct RustCache: Identifiable, Sendable, Equatable {
    let path: String
    let size: UInt64
    /// The newest change inside the folder's top level: when the project was last built.
    let lastBuilt: Date

    var id: String { path }
    /// The project folder's name ("humanproof", "rust").
    var project: String { ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }
    /// Built in the last 10 minutes: a build may be running, so it is never deleted.
    var isActive: Bool { Date().timeIntervalSince(lastBuilt) < 600 }
}

enum DevCaches {
    private static let signature = "Signature: 8a477f597d28d172789f06886806bc55"

    /// Where projects usually live. Hidden folders and node_modules are skipped; a `target` folder isn't entered.
    static var roots: [String] {
        let home = NSHomeDirectory()
        return ["Developer", "Projects", "code", "src", "dev", "Documents/GitHub"]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Blocking; run off the main actor. Sizing a large cache reads every file's size, which takes a few seconds.
    static func findRust(maxDepth: Int = 5) -> [RustCache] {
        var found: [RustCache] = []
        let fm = FileManager.default
        for root in roots {
            var stack: [(path: String, depth: Int)] = [(root, 0)]
            while let (path, depth) = stack.popLast() {
                guard let children = try? fm.contentsOfDirectory(atPath: path) else { continue }
                for name in children where !name.hasPrefix(".") && name != "node_modules" {
                    let child = path + "/" + name
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: child, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                    if name == "target", isCargoCache(child) {
                        found.append(RustCache(path: child, size: size(of: child), lastBuilt: lastChange(in: child)))
                    } else if depth < maxDepth {
                        stack.append((child, depth + 1))
                    }
                }
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    static func isCargoCache(_ path: String) -> Bool {
        guard let tag = try? String(contentsOfFile: path + "/CACHEDIR.TAG", encoding: .utf8) else { return false }
        return tag.hasPrefix(signature)
    }

    /// Deletes the cache folder. Cargo rebuilds it on the next `cargo build`.
    static func delete(_ cache: RustCache) -> Bool {
        guard isCargoCache(cache.path) else { return false }
        return (try? FileManager.default.removeItem(atPath: cache.path)) != nil
    }

    private static func size(of path: String) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path),
                                                              includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                                              options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            total += UInt64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Cargo touches `target/<profile>/` and `.fingerprint` on every build, so the newest top-level change is enough.
    private static func lastChange(in path: String) -> Date {
        let fm = FileManager.default
        var newest = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        for name in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
            let profile = path + "/" + name
            for inner in [profile, profile + "/.fingerprint", profile + "/deps"] {
                if let date = try? fm.attributesOfItem(atPath: inner)[.modificationDate] as? Date, date > newest { newest = date }
            }
        }
        return newest
    }
}
