import Foundation
import Combine

/// Handles syncing playlists between Mixed In Key and Traktor Pro
final class SyncEngine: ObservableObject {
    @Published var diffs: [SyncDiff] = []
    @Published var isSyncing = false
    @Published var autoSyncEnabled = false
    @Published var lastSyncDate: Date?
    @Published var activityLog: [ActivityLogEntry] = []

    private let mikDatabase: MIKDatabase
    private let traktorCollection: TraktorCollection
    private let backupManager: BackupManager
    private let diffHistory: DiffHistory?
    private var fileWatcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()

    init(mikDatabase: MIKDatabase, traktorCollection: TraktorCollection, backupManager: BackupManager, diffHistory: DiffHistory? = nil) {
        self.mikDatabase = mikDatabase
        self.traktorCollection = traktorCollection
        self.backupManager = backupManager
        self.diffHistory = diffHistory
    }

    // MARK: - Diff Calculation

    /// Calculate differences: what MIK playlists need to be synced to Traktor
    func calculateDiffs() {
        var newDiffs: [SyncDiff] = []

        let mikPlaylists = mikDatabase.playlists
        let traktorPlaylists = traktorCollection.playlists
        let traktorNames = Set(traktorPlaylists.map { $0.name })

        // Playlists in MIK but not in Traktor
        for playlist in mikPlaylists where !traktorNames.contains(playlist.name) {
            let diff = SyncDiff(
                playlistName: playlist.name,
                additions: playlist.tracks,
                deletions: [],
                sourcePlaylist: playlist,
                targetPlaylist: nil,
                status: .newInMIK
            )
            newDiffs.append(diff)
        }

        // Playlists in both — compare tracks (MIK is source of truth)
        for mikPlaylist in mikPlaylists {
            guard let traktorPlaylist = traktorPlaylists.first(where: { $0.name == mikPlaylist.name }) else {
                continue
            }

            let mikPaths = Set(mikPlaylist.tracks.map { normalizePath($0.filePath) })
            let traktorPaths = Set(traktorPlaylist.tracks.map { normalizePath($0.filePath) })

            // Tracks in MIK but missing from Traktor
            let additions = mikPlaylist.tracks.filter { !traktorPaths.contains(normalizePath($0.filePath)) }
            // Tracks in Traktor but not in MIK (will be removed on sync)
            let deletions = traktorPlaylist.tracks.filter { !mikPaths.contains(normalizePath($0.filePath)) }

            if !additions.isEmpty || !deletions.isEmpty {
                let diff = SyncDiff(
                    playlistName: mikPlaylist.name,
                    additions: additions,
                    deletions: deletions,
                    sourcePlaylist: mikPlaylist,
                    targetPlaylist: traktorPlaylist,
                    status: .trackDifference
                )
                newDiffs.append(diff)
            }
        }

        self.diffs = newDiffs
    }

    // MARK: - Sync Operations

    /// Sync playlists from Mixed In Key to Traktor
    func syncMIKToTraktor(playlistNames: [String]? = nil) async throws {
        isSyncing = true
        defer { isSyncing = false }

        log("Starting MIK → Traktor sync", type: .sync)

        // Backup before writing
        try backupManager.backupTraktorCollection()
        log("Traktor collection backed up", type: .backup)

        let playlistsToSync: [Playlist]
        if let names = playlistNames {
            playlistsToSync = mikDatabase.playlists.filter { names.contains($0.name) }
        } else {
            playlistsToSync = mikDatabase.playlists
        }

        for playlist in playlistsToSync {
            let existsInTraktor = traktorCollection.playlists.contains { $0.name == playlist.name }

            if existsInTraktor {
                // Remove and re-add to update
                try traktorCollection.removePlaylist(named: playlist.name)
            }

            try traktorCollection.addPlaylist(playlist)
            log("Synced playlist '\(playlist.name)' to Traktor (\(playlist.tracks.count) tracks)", type: .sync)
        }

        lastSyncDate = Date()
        calculateDiffs()

        // Record to diff history
        diffHistory?.record(diffs: diffs, direction: "MIK → Traktor")

        log("MIK → Traktor sync complete", type: .sync)
    }

    /// Sync all MIK playlists to Traktor
    func syncAll() async throws {
        try await syncMIKToTraktor()
    }

    // MARK: - Auto-Sync

    func startAutoSync() {
        guard !autoSyncEnabled else { return }
        autoSyncEnabled = true

        // Only watch the MIK database — sync is one-directional (MIK → Traktor)
        fileWatcher = FileWatcher(paths: [MIKDatabase.defaultPath])
        fileWatcher?.onChange = { [weak self] changedPath in
            guard let self = self else { return }
            Task { @MainActor in
                self.log("MIK database changed, syncing to Traktor…", type: .info)
                do {
                    try self.mikDatabase.loadPlaylists()
                    self.calculateDiffs()
                    try await self.syncMIKToTraktor()
                } catch {
                    self.log("Auto-sync error: \(error.localizedDescription)", type: .error)
                }
            }
        }
        fileWatcher?.start()
        log("Auto-sync enabled", type: .info)
    }

    func stopAutoSync() {
        autoSyncEnabled = false
        fileWatcher?.stop()
        fileWatcher = nil
        log("Auto-sync disabled", type: .info)
    }

    // MARK: - Playlist Management

    /// Create a new playlist in Traktor only (MIK is read-only)
    func createPlaylistInTraktor(name: String, tracks: [Track] = []) throws {
        log("Creating playlist '\(name)' in Traktor", type: .info)

        try backupManager.backupTraktorCollection()

        let traktorPlaylist = Playlist(name: name, source: .traktor, tracks: tracks)
        try traktorCollection.addPlaylist(traktorPlaylist)

        log("Playlist '\(name)' created in Traktor", type: .sync)
        calculateDiffs()
    }

    /// Delete a playlist from Traktor (MIK is read-only)
    func deletePlaylistFromTraktor(name: String) throws {
        try backupManager.backupTraktorCollection()
        try traktorCollection.removePlaylist(named: name)
        log("Deleted playlist '\(name)' from Traktor", type: .info)
        calculateDiffs()
    }

    /// Rename a playlist in Traktor (MIK is read-only)
    func renamePlaylistInTraktor(oldName: String, newName: String) throws {
        try backupManager.backupTraktorCollection()
        try traktorCollection.renamePlaylist(from: oldName, to: newName)
        log("Renamed playlist '\(oldName)' → '\(newName)' in Traktor", type: .info)
        calculateDiffs()
    }

    // MARK: - Private Helpers

    private func normalizePath(_ path: String) -> String {
        return URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }

    private func log(_ message: String, type: ActivityLogEntry.LogType) {
        let entry = ActivityLogEntry(timestamp: Date(), message: message, type: type)
        DispatchQueue.main.async {
            self.activityLog.insert(entry, at: 0)
        }
    }
}
