import Foundation

/// Validates tracks before syncing — checks that referenced files actually exist on disk
struct PreSyncValidator {

    struct ValidationResult {
        let playlist: Playlist
        let missingFiles: [Track]
        let validTracks: [Track]

        var allValid: Bool { missingFiles.isEmpty }
        var missingCount: Int { missingFiles.count }
        var validCount: Int { validTracks.count }
    }

    /// Validate a single playlist — check all track file paths exist
    static func validate(playlist: Playlist) -> ValidationResult {
        var missing: [Track] = []
        var valid: [Track] = []

        for track in playlist.tracks {
            if track.filePath.isEmpty {
                missing.append(track)
            } else if FileManager.default.fileExists(atPath: track.filePath) {
                valid.append(track)
            } else {
                missing.append(track)
            }
        }

        return ValidationResult(playlist: playlist, missingFiles: missing, validTracks: valid)
    }

    /// Validate multiple playlists
    static func validateAll(playlists: [Playlist]) -> [ValidationResult] {
        playlists.map { validate(playlist: $0) }
    }

    /// Return only the tracks with valid file paths (for syncing without broken references)
    static func filterValid(playlist: Playlist) -> Playlist {
        let result = validate(playlist: playlist)
        var filtered = playlist
        filtered.tracks = result.validTracks
        return filtered
    }
}
