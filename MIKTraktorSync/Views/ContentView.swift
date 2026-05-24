import SwiftUI

/// Root view with NavigationSplitView: sidebar + track list + optional sync panel
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showActivityLog = false
    @State private var showSyncDiff = false
    @State private var showDiffHistory = false
    @State private var showBackupBrowser = false
    @State private var showValidation = false
    @State private var validationResults: [PreSyncValidator.ValidationResult] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                if let playlist = appState.selectedPlaylist {
                    TrackListView(playlist: playlist)
                } else {
                    emptyState
                }

                if showActivityLog {
                    Divider()
                    ActivityLogView()
                        .frame(height: 200)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .sheet(isPresented: $showSyncDiff) {
            SyncDiffView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showDiffHistory) {
            DiffHistoryView(diffHistory: appState.diffHistory)
                .frame(minWidth: 700, minHeight: 450)
        }
        .sheet(isPresented: $showBackupBrowser) {
            BackupBrowserView(backupManager: appState.backupManager)
                .frame(minWidth: 550, minHeight: 400)
        }
        .sheet(isPresented: $showValidation) {
            ValidationView(results: validationResults) {
                showValidation = false
                Task { try? await appState.syncEngine.syncMIKToTraktor() }
            }
            .frame(minWidth: 550, minHeight: 400)
        }
        .onAppear {
            appState.loadData()
        }
        .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select a playlist from the sidebar")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            Task {
                try? await appState.syncEngine.syncMIKToTraktor()
            }
        } label: {
            Label("Sync MIK → Traktor", systemImage: "arrow.right.circle.fill")
        }
        .help("Sync all Mixed In Key playlists to Traktor")
        .disabled(appState.syncEngine.isSyncing)

        Button {
            showSyncDiff.toggle()
        } label: {
            Label("Diff", systemImage: "arrow.triangle.2.circlepath")
        }
        .help("Show pending sync changes")
        .badge(appState.syncEngine.diffs.count)

        Toggle(isOn: Binding(
            get: { appState.syncEngine.autoSyncEnabled },
            set: { newValue in
                if newValue { appState.syncEngine.startAutoSync() }
                else { appState.syncEngine.stopAutoSync() }
            }
        )) {
            Label("Auto-Sync", systemImage: "bolt.circle")
        }
        .help("Automatically sync when MIK database changes")

        Button {
            showActivityLog.toggle()
        } label: {
            Label("Log", systemImage: "list.bullet.rectangle")
        }
        .help("Toggle activity log")

        Button {
            showDiffHistory.toggle()
        } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
        }
        .help("View sync history")

        Button {
            validationResults = PreSyncValidator.validateAll(playlists: appState.mikDatabase.playlists)
            showValidation = true
        } label: {
            Label("Validate", systemImage: "checkmark.shield")
        }
        .help("Validate track files before syncing")

        Button {
            showBackupBrowser.toggle()
        } label: {
            Label("Backups", systemImage: "externaldrive.badge.timemachine")
        }
        .help("Browse and restore NML backups")

        Button {
            appState.reloadAll()
        } label: {
            Label("Reload", systemImage: "arrow.clockwise")
        }
        .help("Reload both databases")
        .keyboardShortcut("r", modifiers: .command)
    }
}
