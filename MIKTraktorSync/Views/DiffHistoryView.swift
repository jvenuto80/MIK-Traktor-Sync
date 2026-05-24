import SwiftUI

/// Shows history of past sync operations with details of what changed
struct DiffHistoryView: View {
    @ObservedObject var diffHistory: DiffHistory
    @State private var selectedEntry: DiffHistoryEntry?

    var body: some View {
        HSplitView {
            // Left: list of sync events
            List(diffHistory.entries, selection: Binding(
                get: { selectedEntry?.id },
                set: { id in selectedEntry = diffHistory.entries.first { $0.id == id } }
            )) { entry in
                historyRow(entry)
                    .tag(entry.id)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 250)

            // Right: detail of selected entry
            if let entry = selectedEntry {
                entryDetail(entry)
            } else {
                Text("Select a sync event to see details")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .toolbar {
            ToolbarItem {
                Button("Clear History", role: .destructive) {
                    diffHistory.clearHistory()
                    selectedEntry = nil
                }
                .disabled(diffHistory.entries.isEmpty)
            }
        }
        .navigationTitle("Sync History")
    }

    private func historyRow(_ entry: DiffHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.direction)
                    .font(.headline)
                Spacer()
                Text(entry.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(entry.playlistCount) playlists", systemImage: "music.note.list")
                if entry.totalAdded > 0 {
                    Text("+\(entry.totalAdded)")
                        .foregroundColor(.green)
                }
                if entry.totalRemoved > 0 {
                    Text("-\(entry.totalRemoved)")
                        .foregroundColor(.red)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func entryDetail(_ entry: DiffHistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.direction)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(entry.timestamp, style: .date) + Text(" at ") + Text(entry.timestamp, style: .time)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(entry.playlistCount) playlists synced")
                        HStack {
                            Text("+\(entry.totalAdded) added").foregroundColor(.green)
                            Text("-\(entry.totalRemoved) removed").foregroundColor(.red)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                Divider()

                // Per-playlist details
                ForEach(entry.items) { item in
                    playlistItemDetail(item)
                }
            }
            .padding()
        }
    }

    private func playlistItemDetail(_ item: DiffHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.playlistName)
                    .font(.headline)
                Spacer()
                Text(item.status)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }

            if !item.addedTracks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Added (\(item.addedCount)):")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    ForEach(item.addedTracks, id: \.self) { track in
                        Text("  + \(track)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                    if item.addedCount > item.addedTracks.count {
                        Text("  … and \(item.addedCount - item.addedTracks.count) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !item.removedTracks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Removed (\(item.removedCount)):")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    ForEach(item.removedTracks, id: \.self) { track in
                        Text("  - \(track)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    if item.removedCount > item.removedTracks.count {
                        Text("  … and \(item.removedCount - item.removedTracks.count) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()
        }
    }
}
