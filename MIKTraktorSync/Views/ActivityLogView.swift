import SwiftUI

/// Collapsible activity log showing read/write/sync operations
struct ActivityLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Activity Log", systemImage: "list.bullet.rectangle")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(appState.syncEngine.activityLog.count) entries")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    appState.syncEngine.activityLog.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear log")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if appState.syncEngine.activityLog.isEmpty {
                Text("No activity yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.syncEngine.activityLog) { entry in
                    logRow(entry)
                }
                .listStyle(.plain)
                .font(.system(.caption, design: .monospaced))
            }
        }
    }

    private func logRow(_ entry: ActivityLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            logIcon(entry.type)
            Text(entry.timestamp, style: .time)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(entry.message)
                .lineLimit(2)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func logIcon(_ type: ActivityLogEntry.LogType) -> some View {
        Group {
            switch type {
            case .info:
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            case .warning:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            case .error:
                Image(systemName: "xmark.circle")
                    .foregroundColor(.red)
            case .sync:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.green)
            case .backup:
                Image(systemName: "externaldrive.badge.timemachine")
                    .foregroundColor(.purple)
            }
        }
        .frame(width: 16)
    }
}
