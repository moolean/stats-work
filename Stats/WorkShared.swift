import Foundation
import Darwin

struct WorkItem: Codable, Identifiable {
    var id = UUID()
    var keyword: String
    var notes = ""
    var link = ""
    var pinned = false
}

struct PinnedItem: Codable, Identifiable, Equatable {
    let id: UUID
    let keyword: String
}

enum WorkLinks {
    static let scheme = "moolean-stats-work"
    static let add = URL(string: "\(scheme)://add")!

    static func item(_ id: UUID) -> URL {
        URL(string: "\(scheme)://item/\(id.uuidString)")!
    }

    static func external(_ input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

struct WorkFiles {
    static let widgetKind = "PinnedWork"
    static let pinLimit = 5
    let directory: URL

    static var local: WorkFiles {
        let loginHome = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) }
        let home = loginHome.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return WorkFiles(directory: home.appendingPathComponent(
            "Library/Application Support/com.moolean.stats-work", isDirectory: true))
    }

    private var itemsURL: URL { directory.appendingPathComponent("WorkItems.json") }
    private var pinsURL: URL { directory.appendingPathComponent("Pinned.json") }

    func load() throws -> [WorkItem] {
        do {
            return try JSONDecoder().decode([WorkItem].self, from: Data(contentsOf: itemsURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    func save(_ items: [WorkItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(items).write(to: itemsURL, options: .atomic)
        try persistPins(items)
    }

    func loadPins() throws -> [PinnedItem] {
        try JSONDecoder().decode([PinnedItem].self, from: Data(contentsOf: pinsURL))
    }

    func persistPins(_ items: [WorkItem]) throws {
        let pins = Self.pins(in: items)
        if (try? loadPins()) != pins {
            try JSONEncoder().encode(pins).write(to: pinsURL, options: .atomic)
        }
    }

    static func pins(in items: [WorkItem]) -> [PinnedItem] {
        items.lazy.filter(\.pinned).prefix(pinLimit).map {
            PinnedItem(id: $0.id, keyword: $0.keyword)
        }
    }

    static func exactMatch(_ text: String, in items: [WorkItem]) -> WorkItem? {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.first { $0.keyword.compare(keyword, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
    }
}
