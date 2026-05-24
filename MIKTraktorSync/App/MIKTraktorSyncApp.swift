import SwiftUI

@main
struct MIKTraktorSyncApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Sync MIK → Traktor") {
                    Task { try? await appState.syncEngine.syncMIKToTraktor() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Reload All") {
                    appState.reloadAll()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

/// Shared application state
final class AppState: ObservableObject {
    @Published var mikDatabase: MIKDatabase
    @Published var traktorCollection: TraktorCollection
    @Published var syncEngine: SyncEngine
    @Published var selectedPlaylist: Playlist?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var diffHistory: DiffHistory
    @Published var backupManager: BackupManager

    init() {
        let mik = MIKDatabase()
        let traktor = TraktorCollection()
        let backup = BackupManager()
        let history = DiffHistory()
        self.mikDatabase = mik
        self.traktorCollection = traktor
        self.backupManager = backup
        self.diffHistory = history
        self.syncEngine = SyncEngine(mikDatabase: mik, traktorCollection: traktor, backupManager: backup, diffHistory: history)

        loadData()
    }

    func loadData() {
        isLoading = true
        errorMessage = nil

        do {
            try mikDatabase.connect()
            try mikDatabase.loadPlaylists()
        } catch {
            errorMessage = "MIK: \(error.localizedDescription)"
        }

        do {
            try traktorCollection.load()
        } catch {
            let existing = errorMessage.map { $0 + "\n" } ?? ""
            errorMessage = existing + "Traktor: \(error.localizedDescription)"
        }

        syncEngine.calculateDiffs()
        isLoading = false
    }

    func reloadAll() {
        loadData()
    }
}
