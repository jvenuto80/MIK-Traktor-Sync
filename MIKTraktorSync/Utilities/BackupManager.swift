import Foundation

/// Creates timestamped backups of database files before any write operation
final class BackupManager: ObservableObject {
    let backupDirectory: URL

    var traktorNMLPath: String { TraktorCollection.defaultPath }

    static let defaultBackupDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/MIKTraktorSync/backups")
    }()

    init(backupDirectory: URL = BackupManager.defaultBackupDir) {
        self.backupDirectory = backupDirectory
    }

    private func ensureBackupDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDirectory.path) {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }
    }

    /// Create a backup of the current Traktor NML (convenience for restore flow)
    func createBackup() {
        try? backupTraktorCollection()
    }

    /// Backup the Traktor collection.nml before writing
    func backupTraktorCollection() throws {
        let sourcePath = TraktorCollection.defaultPath
        guard FileManager.default.fileExists(atPath: sourcePath) else { return }

        try ensureBackupDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = backupDirectory.appendingPathComponent("collection_\(timestamp).nml").path
        try FileManager.default.copyItem(atPath: sourcePath, toPath: backupPath)
    }

    /// Backup the MIK database (read-only safety copy for reference)
    func backupMIKDatabase() throws {
        let sourcePath = MIKDatabase.defaultPath
        guard FileManager.default.fileExists(atPath: sourcePath) else { return }

        try ensureBackupDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = backupDirectory.appendingPathComponent("MIKStore_\(timestamp).db").path
        try FileManager.default.copyItem(atPath: sourcePath, toPath: backupPath)
    }

    /// List existing backups sorted by date (newest first)
    func listBackups() -> [(path: String, date: Date)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: backupDirectory.path) else { return [] }

        return files.compactMap { filename in
            let fullPath = backupDirectory.appendingPathComponent(filename).path
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let date = attrs[.creationDate] as? Date else { return nil }
            return (fullPath, date)
        }.sorted { $0.date > $1.date }
    }

    /// Remove backups older than the specified number of days
    func pruneBackups(olderThanDays days: Int = 30) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: backupDirectory.path) else { return }

        for filename in files {
            let fullPath = backupDirectory.appendingPathComponent(filename).path
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let date = attrs[.creationDate] as? Date else { continue }
            if date < cutoff {
                try fm.removeItem(atPath: fullPath)
            }
        }
    }
}
