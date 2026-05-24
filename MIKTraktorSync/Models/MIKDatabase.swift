import Foundation
import SQLite

/// Reads Mixed In Key 11's SQLite database (Collection11.mikdb) — read-only
final class MIKDatabase: ObservableObject {
    private var db: Connection?
    private let dbPath: String

    @Published var playlists: [Playlist] = []
    @Published var lastError: String?

    static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Mixedinkey/Collection11.mikdb"
    }()

    init(path: String = MIKDatabase.defaultPath) {
        self.dbPath = path
    }

    // MARK: - Connection

    func connect() throws {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw MIKError.databaseNotFound(dbPath)
        }
        // Read-only: we never write to the MIK database to avoid corruption
        db = try Connection(dbPath, readonly: true)
    }

    // MARK: - Load Playlists

    /// Load all playlists (collections) and their tracks from MIK 11.
    /// Schema: ZCOLLECTION → Z_1SONGS (junction) → ZSONG
    func loadPlaylists() throws {
        guard let db = db else { throw MIKError.notConnected }

        var loadedPlaylists: [Playlist] = []

        // Load collections (skip the Library root and folders)
        let collStmt = try db.prepare("""
            SELECT Z_PK, ZNAME FROM ZCOLLECTION
            WHERE ZISLIBRARY = 0 AND ZISFOLDER = 0
            ORDER BY ZINDEX
            """)

        for row in collStmt {
            guard let pk = row[0] as? Int64,
                  let name = row[1] as? String else { continue }

            let tracks = try loadTracksForCollection(db: db, collectionPK: pk)

            let playlist = Playlist(
                name: name,
                source: .mixedInKey,
                tracks: tracks,
                sourceIdentifier: String(pk)
            )
            loadedPlaylists.append(playlist)
        }

        self.playlists = loadedPlaylists
    }

    private func loadTracksForCollection(db: Connection, collectionPK: Int64) throws -> [Track] {
        let stmt = try db.prepare("""
            SELECT s.Z_PK, s.ZNAME, s.ZARTIST, s.ZTEMPO, s.ZKEY, s.ZTAGENERGY, s.ZBOOKMARKDATA
            FROM Z_1SONGS j
            JOIN ZSONG s ON s.Z_PK = j.Z_5SONGS
            WHERE j.Z_1COLLECTIONS = ?
            ORDER BY j.Z_FOK_5SONGS
            """, collectionPK)

        var tracks: [Track] = []

        for row in stmt {
            let title = (row[1] as? String) ?? "Unknown"
            let artist = (row[2] as? String) ?? "Unknown"
            let bpm = row[3] as? Double
            let key = row[4] as? String
            let energy: Int? = (row[5] as? Int64).map { Int($0) }

            // Extract file path from macOS bookmark data
            var filePath = ""
            if let blob = row[6] as? Blob {
                let bookmarkData = Data(blob.bytes)
                filePath = Self.extractPathFromBookmark(bookmarkData) ?? ""
            }

            let track = Track(
                title: title,
                artist: artist,
                bpm: bpm,
                key: key,
                energy: energy,
                filePath: filePath
            )
            tracks.append(track)
        }

        return tracks
    }

    // MARK: - Bookmark Data Parsing

    /// Extract file path from a macOS security-scoped bookmark blob.
    /// Uses NSURL's built-in bookmark resolver when possible, falls back to
    /// scanning the raw bytes for the embedded file:// URL.
    private static func extractPathFromBookmark(_ data: Data) -> String? {
        // Try resolving via NSURL bookmark API
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url.path
        }

        // Fallback: scan raw bytes for "file://" URL or path components
        // Bookmark data contains null-separated path components
        let bytes = [UInt8](data)
        // Look for "file:///" marker
        if let range = data.range(of: Data("file:///".utf8)) {
            let start = range.lowerBound
            // Read until next null byte
            var end = start
            while end < data.count && bytes[end] != 0 {
                end += 1
            }
            if let urlString = String(data: data[start..<end], encoding: .utf8),
               let url = URL(string: urlString) {
                return url.path
            }
        }

        // Last resort: look for path-like strings
        let parts = data.split(separator: 0)
        for part in parts {
            if let str = String(data: part, encoding: .utf8),
               str.hasPrefix("/Users/") || str.hasPrefix("/Volumes/"),
               str.contains(".") {
                return str
            }
        }

        return nil
    }

    // MARK: - Errors

    enum MIKError: LocalizedError {
        case databaseNotFound(String)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .databaseNotFound(let path):
                return "Mixed In Key database not found at: \(path)"
            case .notConnected:
                return "Not connected to the Mixed In Key database"
            }
        }
    }
}
