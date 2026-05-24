import Foundation

// MARK: - Track Model

struct Track: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var artist: String
    var bpm: Double?
    var key: String?          // Camelot notation (e.g., "8A", "11B")
    var energy: Int?          // 1-10 energy level from MIK
    var filePath: String      // Absolute path to audio file
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        bpm: Double? = nil,
        key: String? = nil,
        energy: Int? = nil,
        filePath: String,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.key = key
        self.energy = energy
        self.filePath = filePath
        self.duration = duration
    }
}

// MARK: - Playlist Source

enum PlaylistSource: String, Codable, CaseIterable {
    case mixedInKey = "Mixed In Key"
    case traktor = "Traktor"
}

// MARK: - Playlist Model

struct Playlist: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var source: PlaylistSource
    var tracks: [Track]
    var lastSyncDate: Date?
    var sourceIdentifier: String?  // Original ID in the source database

    init(
        id: UUID = UUID(),
        name: String,
        source: PlaylistSource,
        tracks: [Track] = [],
        lastSyncDate: Date? = nil,
        sourceIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.tracks = tracks
        self.lastSyncDate = lastSyncDate
        self.sourceIdentifier = sourceIdentifier
    }

    var trackCount: Int { tracks.count }
}

// MARK: - Sync Status

enum SyncStatus: Equatable {
    case synced
    case pendingSync
    case newInMIK        // Exists in MIK but not yet in Traktor
    case trackDifference // Track list differs between MIK and Traktor
}

// MARK: - Sync Diff

struct SyncDiff: Identifiable {
    let id = UUID()
    let playlistName: String
    var additions: [Track]
    var deletions: [Track]
    var sourcePlaylist: Playlist?
    var targetPlaylist: Playlist?
    var status: SyncStatus

    var hasChanges: Bool {
        !additions.isEmpty || !deletions.isEmpty
    }
}

// MARK: - Activity Log Entry

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType

    enum LogType: String {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case sync = "SYNC"
        case backup = "BACKUP"
    }
}
