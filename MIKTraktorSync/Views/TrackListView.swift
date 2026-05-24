import SwiftUI

/// Sortable, filterable track table for a selected playlist
struct TrackListView: View {
    let playlist: Playlist
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<Track>] = [
        KeyPathComparator(\Track.title, order: .forward)
    ]
    @State private var selection = Set<Track.ID>()
    @State private var orderedTracks: [Track]?
    @State private var activeStrategy: SmartPlaylistOrderer.Strategy?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            trackTable
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                HStack(spacing: 12) {
                    Label("\(playlist.trackCount) tracks", systemImage: "music.note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label(playlist.source.rawValue, systemImage: playlist.source == .mixedInKey ? "key.fill" : "record.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Menu {
                ForEach(SmartPlaylistOrderer.Strategy.allCases, id: \.rawValue) { strategy in
                    Button(strategy.rawValue) {
                        orderedTracks = SmartPlaylistOrderer.order(tracks: playlist.tracks, strategy: strategy)
                        activeStrategy = strategy
                    }
                }
                Divider()
                Button("Reset to Original Order") {
                    orderedTracks = nil
                    activeStrategy = nil
                }
                .disabled(orderedTracks == nil)
            } label: {
                Label(activeStrategy?.rawValue ?? "Smart Order", systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Reorder tracks for smooth DJ mixing")

            TextField("Filter tracks…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var trackTable: some View {
        Table(filteredTracks, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("#") { track in
                if let index = playlist.tracks.firstIndex(where: { $0.id == track.id }) {
                    Text("\(index + 1)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .width(min: 30, ideal: 40, max: 50)

            TableColumn("Title", value: \Track.title) { track in
                Text(track.title)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Artist", value: \Track.artist) { track in
                Text(track.artist)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("BPM") { track in
                if let bpm = track.bpm {
                    Text(String(format: "%.1f", bpm))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }
            .width(min: 50, ideal: 60, max: 70)

            TableColumn("Key") { track in
                if let key = track.key {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(keyColor(key).opacity(0.15))
                        .cornerRadius(3)
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }
            .width(min: 45, ideal: 55, max: 65)

            TableColumn("Energy") { track in
                if let energy = track.energy {
                    HStack(spacing: 2) {
                        Text("\(energy)")
                            .monospacedDigit()
                        energyBar(energy)
                    }
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }
            .width(min: 60, ideal: 80, max: 100)

            TableColumn("File") { track in
                Text(track.filePath.components(separatedBy: "/").suffix(2).joined(separator: "/"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(track.filePath)
            }
            .width(min: 150, ideal: 250)
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            if let id = ids.first, let track = playlist.tracks.first(where: { $0.id == id }) {
                Button("Reveal in Finder") {
                    revealInFinder(track.filePath)
                }
            }
        } primaryAction: { ids in
            // Double-click: reveal in Finder
            if let id = ids.first, let track = playlist.tracks.first(where: { $0.id == id }) {
                revealInFinder(track.filePath)
            }
        }
    }

    // MARK: - Filtering & Sorting

    private var filteredTracks: [Track] {
        var tracks = orderedTracks ?? playlist.tracks

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            tracks = tracks.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                ($0.key?.lowercased().contains(query) ?? false) ||
                $0.filePath.lowercased().contains(query)
            }
        }

        // Only apply table sort if no smart ordering is active
        if orderedTracks == nil {
            return tracks.sorted(using: sortOrder)
        }
        return tracks
    }

    // MARK: - Helpers

    private func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func keyColor(_ key: String) -> Color {
        // Color by Camelot wheel position
        if key.hasSuffix("A") { return .blue }
        if key.hasSuffix("B") { return .green }
        return .gray
    }

    private func energyBar(_ energy: Int) -> some View {
        GeometryReader { _ in
            RoundedRectangle(cornerRadius: 2)
                .fill(energyColor(energy))
                .frame(width: CGFloat(energy) * 4, height: 8)
        }
        .frame(width: 40, height: 8)
    }

    private func energyColor(_ energy: Int) -> Color {
        switch energy {
        case 1...3: return .blue
        case 4...6: return .yellow
        case 7...8: return .orange
        case 9...10: return .red
        default: return .gray
        }
    }
}
