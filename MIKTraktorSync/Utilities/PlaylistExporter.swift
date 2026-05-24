import Foundation

/// Exports playlists to various formats (.nml, .m3u, .csv)
struct PlaylistExporter {

    enum ExportFormat: String, CaseIterable {
        case nml = "NML (Traktor)"
        case m3u = "M3U"
        case csv = "CSV"

        var fileExtension: String {
            switch self {
            case .nml: return "nml"
            case .m3u: return "m3u"
            case .csv: return "csv"
            }
        }
    }

    /// Export a playlist to the given format and return the file data
    static func export(playlist: Playlist, format: ExportFormat) -> Data? {
        switch format {
        case .nml:
            return exportAsNML(playlist)
        case .m3u:
            return exportAsM3U(playlist)
        case .csv:
            return exportAsCSV(playlist)
        }
    }

    // MARK: - NML Export

    private static func exportAsNML(_ playlist: Playlist) -> Data? {
        let root = XMLElement(name: "NML")
        root.addAttribute(XMLNode.attribute(withName: "VERSION", stringValue: "19") as! XMLNode)

        // Collection
        let collection = XMLElement(name: "COLLECTION")
        collection.addAttribute(XMLNode.attribute(withName: "ENTRIES", stringValue: String(playlist.tracks.count)) as! XMLNode)

        for track in playlist.tracks {
            let entry = XMLElement(name: "ENTRY")
            entry.addAttribute(XMLNode.attribute(withName: "TITLE", stringValue: track.title) as! XMLNode)
            entry.addAttribute(XMLNode.attribute(withName: "ARTIST", stringValue: track.artist) as! XMLNode)

            let location = XMLElement(name: "LOCATION")
            let (volume, dir, file) = parseFilePathToNML(track.filePath)
            location.addAttribute(XMLNode.attribute(withName: "DIR", stringValue: dir) as! XMLNode)
            location.addAttribute(XMLNode.attribute(withName: "FILE", stringValue: file) as! XMLNode)
            location.addAttribute(XMLNode.attribute(withName: "VOLUME", stringValue: volume) as! XMLNode)
            entry.addChild(location)

            if let bpm = track.bpm {
                let tempo = XMLElement(name: "TEMPO")
                tempo.addAttribute(XMLNode.attribute(withName: "BPM", stringValue: String(format: "%.6f", bpm)) as! XMLNode)
                entry.addChild(tempo)
            }

            collection.addChild(entry)
        }
        root.addChild(collection)

        // Playlists
        let playlistsNode = XMLElement(name: "PLAYLISTS")
        let rootNode = XMLElement(name: "NODE")
        rootNode.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "FOLDER") as! XMLNode)
        rootNode.addAttribute(XMLNode.attribute(withName: "NAME", stringValue: "$ROOT") as! XMLNode)

        let plNode = XMLElement(name: "NODE")
        plNode.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "PLAYLIST") as! XMLNode)
        plNode.addAttribute(XMLNode.attribute(withName: "NAME", stringValue: playlist.name) as! XMLNode)

        let plContent = XMLElement(name: "PLAYLIST")
        plContent.addAttribute(XMLNode.attribute(withName: "ENTRIES", stringValue: String(playlist.tracks.count)) as! XMLNode)
        plContent.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "LIST") as! XMLNode)

        for track in playlist.tracks {
            let entry = XMLElement(name: "ENTRY")
            let primaryKey = XMLElement(name: "PRIMARYKEY")
            primaryKey.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "TRACK") as! XMLNode)
            let (volume, dir, file) = parseFilePathToNML(track.filePath)
            primaryKey.addAttribute(XMLNode.attribute(withName: "KEY", stringValue: "\(volume)\(dir)\(file)") as! XMLNode)
            entry.addChild(primaryKey)
            plContent.addChild(entry)
        }

        plNode.addChild(plContent)
        rootNode.addChild(plNode)
        playlistsNode.addChild(rootNode)
        root.addChild(playlistsNode)

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        return doc.xmlData(options: [.nodePrettyPrint])
    }

    // MARK: - M3U Export

    private static func exportAsM3U(_ playlist: Playlist) -> Data? {
        var lines = ["#EXTM3U", "#PLAYLIST:\(playlist.name)"]

        for track in playlist.tracks {
            let duration = Int(track.duration ?? -1)
            lines.append("#EXTINF:\(duration),\(track.artist) - \(track.title)")
            lines.append(track.filePath)
        }

        return lines.joined(separator: "\n").data(using: .utf8)
    }

    // MARK: - CSV Export

    private static func exportAsCSV(_ playlist: Playlist) -> Data? {
        var lines = ["#,Title,Artist,BPM,Key,Energy,File Path"]

        for (index, track) in playlist.tracks.enumerated() {
            let bpm = track.bpm.map { String(format: "%.1f", $0) } ?? ""
            let key = track.key ?? ""
            let energy = track.energy.map { String($0) } ?? ""
            let escapedTitle = csvEscape(track.title)
            let escapedArtist = csvEscape(track.artist)
            let escapedPath = csvEscape(track.filePath)
            lines.append("\(index + 1),\(escapedTitle),\(escapedArtist),\(bpm),\(key),\(energy),\(escapedPath)")
        }

        return lines.joined(separator: "\n").data(using: .utf8)
    }

    // MARK: - Import

    /// Import tracks from an .m3u/.m3u8 file
    static func importM3U(from url: URL) -> [Track] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var tracks: [Track] = []
        var pendingInfo: (artist: String, title: String)?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "#EXTM3U" || trimmed.hasPrefix("#PLAYLIST:") { continue }

            if trimmed.hasPrefix("#EXTINF:") {
                // Parse #EXTINF:duration,Artist - Title
                let info = String(trimmed.dropFirst("#EXTINF:".count))
                if let commaIndex = info.firstIndex(of: ",") {
                    let display = String(info[info.index(after: commaIndex)...])
                    let parts = display.components(separatedBy: " - ")
                    if parts.count >= 2 {
                        pendingInfo = (artist: parts[0], title: parts[1...].joined(separator: " - "))
                    } else {
                        pendingInfo = (artist: "Unknown", title: display)
                    }
                }
            } else if !trimmed.hasPrefix("#") {
                // This is a file path
                let track = Track(
                    title: pendingInfo?.title ?? URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent,
                    artist: pendingInfo?.artist ?? "Unknown",
                    filePath: trimmed
                )
                tracks.append(track)
                pendingInfo = nil
            }
        }

        return tracks
    }

    // MARK: - Helpers

    private static func parseFilePathToNML(_ path: String) -> (volume: String, dir: String, file: String) {
        let url = URL(fileURLWithPath: path)
        let file = url.lastPathComponent
        var dirPath = url.deletingLastPathComponent().path

        var volume = "Macintosh HD"
        if dirPath.hasPrefix("/Volumes/") {
            let components = dirPath.dropFirst("/Volumes/".count).split(separator: "/", maxSplits: 1)
            if let vol = components.first {
                volume = String(vol)
                dirPath = "/" + (components.count > 1 ? String(components[1]) : "")
            }
        }

        let traktorDir = dirPath.split(separator: "/").map { "/:\(String($0))" }.joined() + "/:"
        let finalDir = traktorDir.isEmpty ? "/:" : traktorDir

        return (volume, finalDir, file)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
