import Foundation
import Darwin

public final class StatsWidgetDefaults {
    public static let shared = StatsWidgetDefaults()

    private let lock = NSLock()
    private let file: URL = {
        let loginHome = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) }
        let home = loginHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/com.moolean.stats-work/WidgetValues.plist")
    }()
    private let readOnly = Bundle.main.bundleURL.pathExtension == "appex"

    private func read() -> [String: Any] {
        guard let bytes = try? Data(contentsOf: file),
              let stored = try? PropertyListSerialization.propertyList(from: bytes, format: nil)
                as? [String: Any] else { return [:] }
        return stored
    }

    public func bool(forKey key: String) -> Bool { read()[key] as? Bool ?? false }
    public func double(forKey key: String) -> Double { read()[key] as? Double ?? 0 }
    public func data(forKey key: String) -> Data? { read()[key] as? Data }

    public func set(_ value: Any, forKey key: String) {
        guard !readOnly else { return }
        lock.lock()
        defer { lock.unlock() }
        var values = read()
        values[key] = value
        do {
            let bytes = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try bytes.write(to: file, options: .atomic)
        } catch {
            NSLog("Stats could not update the widget snapshot: %@", error.localizedDescription)
        }
    }
}
