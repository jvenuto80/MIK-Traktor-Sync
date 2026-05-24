import SwiftUI

/// Browse and restore backups of the Traktor collection.nml
struct BackupBrowserView: View {
    @ObservedObject var backupManager: BackupManager
    @State private var backups: [BackupFile] = []
    @State private var showRestoreConfirm = false
    @State private var selectedBackup: BackupFile?
    @State private var restoreMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Traktor NML Backups")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(backupManager.backupDirectory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.open(backupManager.backupDirectory)
                }
            }
            .padding()

            Divider()

            if backups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No backups found")
                        .font(.headline)
                    Text("Backups are created automatically before each sync operation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(backups) { backup in
                    backupRow(backup)
                }
            }

            // Status bar
            if let message = restoreMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(message)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
            }
        }
        .frame(minWidth: 500, minHeight: 350)
        .onAppear { loadBackups() }
        .alert("Restore Backup?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    restoreBackup(backup)
                }
            }
        } message: {
            if let backup = selectedBackup {
                Text("This will replace your current collection.nml with the backup from \(backup.date.formatted()). Traktor must be closed. A backup of the current file will be made first.")
            }
        }
        .navigationTitle("Backup Browser")
    }

    private func backupRow(_ backup: BackupFile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.filename)
                    .font(.system(.body, design: .monospaced))
                HStack(spacing: 12) {
                    Text(backup.date, style: .date)
                    Text(backup.date, style: .time)
                    Text(backup.formattedSize)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button("Restore") {
                selectedBackup = backup
                showRestoreConfirm = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func loadBackups() {
        let fm = FileManager.default
        let dir = backupManager.backupDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
            backups = []
            return
        }

        backups = files
            .filter { $0.pathExtension == "nml" }
            .compactMap { url -> BackupFile? in
                let attrs = try? fm.attributesOfItem(atPath: url.path)
                let size = attrs?[.size] as? Int ?? 0
                let date = attrs?[.creationDate] as? Date ?? Date.distantPast
                return BackupFile(url: url, filename: url.lastPathComponent, date: date, size: size)
            }
            .sorted { $0.date > $1.date }
    }

    private func restoreBackup(_ backup: BackupFile) {
        // First, backup current state
        backupManager.createBackup()

        // Restore
        let traktorPath = backupManager.traktorNMLPath
        do {
            let backupData = try Data(contentsOf: backup.url)
            try backupData.write(to: URL(fileURLWithPath: traktorPath))
            restoreMessage = "Restored backup from \(backup.date.formatted()). Restart Traktor to see changes."
            loadBackups()
        } catch {
            restoreMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - BackupFile Model

struct BackupFile: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let date: Date
    let size: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
