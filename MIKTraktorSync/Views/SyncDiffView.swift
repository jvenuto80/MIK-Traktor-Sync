import SwiftUI

/// Shows pending sync differences between MIK and Traktor
struct SyncDiffView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDiffs = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if appState.syncEngine.diffs.isEmpty {
                emptyState
            } else {
                diffList
            }

            Divider()
            actionBar
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var headerBar: some View {
        HStack {
            Text("Sync Preview: MIK → Traktor")
                .font(.headline)
            Spacer()
            Text("\(appState.syncEngine.diffs.count) changes")
                .foregroundColor(.secondary)
            Button("Close") { dismiss() }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("Everything is in sync")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var diffList: some View {
        List(appState.syncEngine.diffs, selection: $selectedDiffs) { diff in
            diffRow(diff)
        }
    }

    private func diffRow(_ diff: SyncDiff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon(diff.status)
                Text(diff.playlistName)
                    .font(.headline)
                Spacer()
                statusLabel(diff.status)
            }

            if !diff.additions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(diff.additions.count) track(s) to add to Traktor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !diff.deletions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("\(diff.deletions.count) track(s) in Traktor not in MIK")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusIcon(_ status: SyncStatus) -> some View {
        Group {
            switch status {
            case .newInMIK:
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.blue)
            case .trackDifference:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case .pendingSync:
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.yellow)
            case .synced:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private func statusLabel(_ status: SyncStatus) -> some View {
        Group {
            switch status {
            case .newInMIK:
                Text("New playlist")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            case .trackDifference:
                Text("Tracks differ")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            case .pendingSync:
                Text("Pending")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.15)))
            case .synced:
                Text("Synced")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if let lastSync = appState.syncEngine.lastSyncDate {
                Text("Last sync: \(lastSync, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button("Sync Selected") {
                let names = appState.syncEngine.diffs
                    .filter { selectedDiffs.contains($0.id) }
                    .map { $0.playlistName }
                Task { try? await appState.syncEngine.syncMIKToTraktor(playlistNames: names) }
            }
            .disabled(selectedDiffs.isEmpty || appState.syncEngine.isSyncing)

            Button("Sync All to Traktor") {
                Task { try? await appState.syncEngine.syncMIKToTraktor() }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.syncEngine.diffs.isEmpty || appState.syncEngine.isSyncing)
        }
        .padding()
    }
}
