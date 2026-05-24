import Foundation

/// Stores and retrieves sync diff history so you can see what changed over time
final class DiffHistory: ObservableObject {
    @Published var entries: [DiffHistoryEntry] = []

    private let storageURL: URL

    static let defaultURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Application Support/MIKTraktorSync")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diff_history.json")
    }()

    init(storageURL: URL = DiffHistory.defaultURL) {
        self.storageURL = storageURL
        load()
    }

    // MARK: - Record

    /// Record diffs from a sync operation
    func record(diffs: [SyncDiff], direction: String) {
        let entry = DiffHistoryEntry(
            timestamp: Date(),
            direction: direction,
            items: diffs.map { diff in
                DiffHistoryItem(
                    playlistName: diff.playlistName,
                    addedCount: diff.additions.count,
                    removedCount: diff.deletions.count,
                    addedTracks: diff.additions.prefix(20).map { "\($0.artist) - \($0.title)" },
                    removedTracks: diff.deletions.prefix(20).map { "\($0.artist) - \($0.title)" },
                    status: diff.status.label
                )
            }
        )
        entries.insert(entry, at: 0)

        // Keep last 100 entries
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }

        save()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: storageURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([DiffHistoryEntry].self, from: data)) ?? []
    }

    /// Clear all history
    func clearHistory() {
        entries.removeAll()
        save()
    }
}

// MARK: - Models

struct DiffHistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let direction: String  // "MIK → Traktor"
    let items: [DiffHistoryItem]

    init(id: UUID = UUID(), timestamp: Date, direction: String, items: [DiffHistoryItem]) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.items = items
    }

    var totalAdded: Int { items.reduce(0) { $0 + $1.addedCount } }
    var totalRemoved: Int { items.reduce(0) { $0 + $1.removedCount } }
    var playlistCount: Int { items.count }
}

struct DiffHistoryItem: Identifiable, Codable {
    let id: UUID
    let playlistName: String
    let addedCount: Int
    let removedCount: Int
    let addedTracks: [String]    // "Artist - Title" for detail view
    let removedTracks: [String]
    let status: String

    init(id: UUID = UUID(), playlistName: String, addedCount: Int, removedCount: Int, addedTracks: [String], removedTracks: [String], status: String) {
        self.id = id
        self.playlistName = playlistName
        self.addedCount = addedCount
        self.removedCount = removedCount
        self.addedTracks = addedTracks
        self.removedTracks = removedTracks
        self.status = status
    }
}

// MARK: - SyncStatus Label Extension

extension SyncStatus {
    var label: String {
        switch self {
        case .synced: return "Synced"
        case .pendingSync: return "Pending"
        case .newInMIK: return "New"
        case .trackDifference: return "Modified"
        }
    }
}
