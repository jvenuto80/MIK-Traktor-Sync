import SwiftUI

/// View for pre-sync validation results — shows which tracks have missing files
struct ValidationView: View {
    let results: [PreSyncValidator.ValidationResult]
    let onSyncValid: () -> Void

    var totalMissing: Int { results.reduce(0) { $0 + $1.missingCount } }
    var totalValid: Int { results.reduce(0) { $0 + $1.validCount } }
    var allValid: Bool { results.allSatisfy { $0.allValid } }

    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                if allValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("All files valid")
                            .font(.headline)
                        Text("\(totalValid) tracks ready to sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("\(totalMissing) missing file\(totalMissing == 1 ? "" : "s")")
                            .font(.headline)
                        Text("\(totalValid) valid, \(totalMissing) missing across \(results.count) playlists")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Sync Valid Tracks") {
                    onSyncValid()
                }
                .buttonStyle(.borderedProminent)
                .disabled(totalValid == 0)
            }
            .padding()

            Divider()

            // Per-playlist results
            List {
                ForEach(results, id: \.playlist.id) { result in
                    playlistSection(result)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 350)
        .navigationTitle("Pre-Sync Validation")
    }

    private func playlistSection(_ result: PreSyncValidator.ValidationResult) -> some View {
        DisclosureGroup {
            if result.missingFiles.isEmpty {
                Text("All \(result.validCount) tracks are valid")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                ForEach(result.missingFiles) { track in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(track.artist) - \(track.title)")
                            .font(.body)
                        Text(track.filePath.isEmpty ? "No file path" : track.filePath)
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            HStack {
                Text(result.playlist.name)
                    .font(.headline)
                Spacer()
                if result.allValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("\(result.missingCount) missing")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
