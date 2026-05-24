import SwiftUI

/// Sidebar showing playlists grouped by source
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedPlaylist?.id },
            set: { id in
                appState.selectedPlaylist = allPlaylists.first { $0.id == id }
            }
        )) {
            Section("Mixed In Key") {
                ForEach(filteredMIKPlaylists) { playlist in
                    playlistRow(playlist)
                        .tag(playlist.id)
                }
            }

            Section("Traktor") {
                ForEach(filteredTraktorPlaylists) { playlist in
                    playlistRow(playlist)
                        .tag(playlist.id)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Filter playlists")
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Export Selected…", action: exportSelected)
                        .disabled(appState.selectedPlaylist == nil)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        let isExcluded = playlist.source == .mixedInKey && appState.syncEngine.excludedPlaylists.contains(playlist.name)
        return HStack {
            if playlist.source == .mixedInKey {
                Button {
                    if isExcluded {
                        appState.syncEngine.excludedPlaylists.remove(playlist.name)
                    } else {
                        appState.syncEngine.excludedPlaylists.insert(playlist.name)
                    }
                    appState.objectWillChange.send()
                } label: {
                    Image(systemName: isExcluded ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundColor(isExcluded ? .red : .green)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help(isExcluded ? "Click to include in sync" : "Click to exclude from sync")
            }

            Text(playlist.name)
                .font(.body)
                .lineLimit(1)
                .opacity(isExcluded ? 0.5 : 1.0)

            Spacer()
            Text("\(playlist.trackCount)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))

            syncIndicator(for: playlist)
        }
        .contextMenu {
            contextMenuItems(for: playlist)
        }
    }

    @ViewBuilder
    private func syncIndicator(for playlist: Playlist) -> some View {
        let diff = appState.syncEngine.diffs.first { $0.playlistName == playlist.name }
        if let diff = diff {
            switch diff.status {
            case .newInMIK:
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
                    .help("New — not yet in Traktor")
            case .trackDifference:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help("Track differences detected")
            case .pendingSync:
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.yellow)
                    .help("Pending sync")
            case .synced:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for playlist: Playlist) -> some View {
        if playlist.source == .traktor {
            Button("Rename…") {
                // Handled via alert in a real implementation
            }
            Button("Delete from Traktor", role: .destructive) {
                try? appState.syncEngine.deletePlaylistFromTraktor(name: playlist.name)
            }
        }

        Divider()

        Button("Export as NML…") { exportPlaylist(playlist, format: .nml) }
        Button("Export as M3U…") { exportPlaylist(playlist, format: .m3u) }
        Button("Export as CSV…") { exportPlaylist(playlist, format: .csv) }

        if playlist.source == .mixedInKey {
            Divider()
            Button("Sync to Traktor") {
                Task { try? await appState.syncEngine.syncMIKToTraktor(playlistNames: [playlist.name]) }
            }
        }
    }

    // MARK: - Filtered Lists

    private var allPlaylists: [Playlist] {
        appState.mikDatabase.playlists + appState.traktorCollection.playlists
    }

    private var filteredMIKPlaylists: [Playlist] {
        let playlists = appState.mikDatabase.playlists
        if searchText.isEmpty { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredTraktorPlaylists: [Playlist] {
        let playlists = appState.traktorCollection.playlists
        if searchText.isEmpty { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Export

    private func exportSelected() {
        guard let playlist = appState.selectedPlaylist else { return }
        exportPlaylist(playlist, format: .nml)
    }

    private func exportPlaylist(_ playlist: Playlist, format: PlaylistExporter.ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = "\(playlist.name).\(format.fileExtension)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let data = PlaylistExporter.export(playlist: playlist, format: format) {
                try? data.write(to: url)
            }
        }
    }
}
