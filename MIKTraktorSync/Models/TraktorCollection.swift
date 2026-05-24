import Foundation

/// Reads and writes Traktor Pro's collection.nml XML file
final class TraktorCollection: ObservableObject {
    private var xmlDocument: XMLDocument?
    private let nmlPath: String

    @Published var playlists: [Playlist] = []
    @Published var lastError: String?

    static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let documentsPath = "\(home)/Documents/Native Instruments"
        // Find the newest Traktor version folder by sorting descending
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: documentsPath) {
            let traktorDirs = contents
                .filter { $0.lowercased().contains("traktor") }
                .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
            if let newest = traktorDirs.first {
                return "\(documentsPath)/\(newest)/collection.nml"
            }
        }
        return "\(documentsPath)/Traktor Pro 4/collection.nml"
    }()

    init(path: String = TraktorCollection.defaultPath) {
        self.nmlPath = path
    }

    // MARK: - Load

    func load() throws {
        guard FileManager.default.fileExists(atPath: nmlPath) else {
            throw TraktorError.fileNotFound(nmlPath)
        }

        let url = URL(fileURLWithPath: nmlPath)
        let data = try Data(contentsOf: url)
        xmlDocument = try XMLDocument(data: data, options: [.nodePreserveAll])

        try parseCollection()
    }

    private func parseCollection() throws {
        guard let root = xmlDocument?.rootElement() else {
            throw TraktorError.invalidXML
        }

        // Parse all tracks from COLLECTION into a lookup dictionary
        let trackLookup = parseTrackCollection(root: root)

        // Parse playlists from PLAYLISTS node
        var loadedPlaylists: [Playlist] = []

        if let playlistsNode = root.elements(forName: "PLAYLISTS").first {
            let rootNode = playlistsNode.elements(forName: "NODE").first
            if let rootNode = rootNode {
                loadedPlaylists = parsePlaylistNodes(rootNode, trackLookup: trackLookup)
            }
        }

        self.playlists = loadedPlaylists
    }

    private func parseTrackCollection(root: XMLElement) -> [String: Track] {
        var lookup: [String: Track] = [:]

        guard let collectionNode = root.elements(forName: "COLLECTION").first else {
            return lookup
        }

        for entry in collectionNode.elements(forName: "ENTRY") {
            let title = entry.attribute(forName: "TITLE")?.stringValue ?? "Unknown"
            let artist = entry.attribute(forName: "ARTIST")?.stringValue ?? "Unknown"

            // Parse location
            var filePath = ""
            if let location = entry.elements(forName: "LOCATION").first {
                let dir = location.attribute(forName: "DIR")?.stringValue ?? ""
                let file = location.attribute(forName: "FILE")?.stringValue ?? ""
                let volume = location.attribute(forName: "VOLUME")?.stringValue ?? ""
                // Traktor uses /:/ as path separator in DIR
                let normalizedDir = dir.replacingOccurrences(of: "/:/", with: "/")
                    .replacingOccurrences(of: ":", with: "/")
                filePath = "/Volumes/\(volume)\(normalizedDir)\(file)"
                if volume.isEmpty || volume == "Macintosh HD" {
                    filePath = "\(normalizedDir)\(file)"
                }
            }

            // Parse tempo/BPM
            var bpm: Double?
            if let tempo = entry.elements(forName: "TEMPO").first {
                if let bpmStr = tempo.attribute(forName: "BPM")?.stringValue {
                    bpm = Double(bpmStr)
                }
            }

            // Parse musical key
            var key: String?
            if let info = entry.elements(forName: "MUSICAL_KEY").first {
                if let keyValue = info.attribute(forName: "VALUE")?.stringValue {
                    key = traktorKeyToCamelot(keyValue)
                }
            }
            // Also check INFO node for KEY
            if key == nil, let info = entry.elements(forName: "INFO").first {
                if let keyStr = info.attribute(forName: "KEY")?.stringValue, !keyStr.isEmpty {
                    key = keyStr
                }
            }

            let track = Track(
                title: title,
                artist: artist,
                bpm: bpm,
                key: key,
                filePath: filePath
            )

            // Use the file path as the lookup key (Traktor uses this in playlist entries)
            let entryKey = buildTraktorEntryKey(entry: entry)
            lookup[entryKey] = track
        }

        return lookup
    }

    private func buildTraktorEntryKey(entry: XMLElement) -> String {
        if let location = entry.elements(forName: "LOCATION").first {
            let dir = location.attribute(forName: "DIR")?.stringValue ?? ""
            let file = location.attribute(forName: "FILE")?.stringValue ?? ""
            let volume = location.attribute(forName: "VOLUME")?.stringValue ?? ""
            return "\(volume)\(dir)\(file)"
        }
        return entry.attribute(forName: "TITLE")?.stringValue ?? UUID().uuidString
    }

    private func parsePlaylistNodes(_ node: XMLElement, trackLookup: [String: Track]) -> [Playlist] {
        var playlists: [Playlist] = []

        // Traktor 4.5+ wraps children in <SUBNODES COUNT="N"> — look there first
        let childNodes: [XMLElement]
        if let subnodesWrapper = node.elements(forName: "SUBNODES").first {
            childNodes = subnodesWrapper.elements(forName: "NODE")
        } else {
            childNodes = node.elements(forName: "NODE")
        }

        for child in childNodes {
            let type = child.attribute(forName: "TYPE")?.stringValue ?? ""
            let name = child.attribute(forName: "NAME")?.stringValue ?? "Untitled"

            if type == "PLAYLIST" {
                // This is a leaf playlist node
                var tracks: [Track] = []
                if let playlistElem = child.elements(forName: "PLAYLIST").first {
                    for entry in playlistElem.elements(forName: "ENTRY") {
                        if let primaryKey = entry.elements(forName: "PRIMARYKEY").first {
                            let key = primaryKey.attribute(forName: "KEY")?.stringValue ?? ""
                            if let track = trackLookup[key] {
                                tracks.append(track)
                            } else {
                                let track = Track(
                                    title: key.components(separatedBy: "/").last ?? "Unknown",
                                    artist: "Unknown",
                                    filePath: key
                                )
                                tracks.append(track)
                            }
                        }
                    }
                }

                let playlist = Playlist(
                    name: name,
                    source: .traktor,
                    tracks: tracks,
                    sourceIdentifier: name
                )
                playlists.append(playlist)
            } else if type == "FOLDER" {
                let subPlaylists = parsePlaylistNodes(child, trackLookup: trackLookup)
                playlists.append(contentsOf: subPlaylists)
            }
        }

        return playlists
    }

    // MARK: - Write Operations

    /// Add a playlist to the Traktor collection.nml
    func addPlaylist(_ playlist: Playlist) throws {
        guard let doc = xmlDocument, let root = doc.rootElement() else {
            throw TraktorError.invalidXML
        }

        // Ensure PLAYLISTS node exists
        let playlistsNode: XMLElement
        if let existing = root.elements(forName: "PLAYLISTS").first {
            playlistsNode = existing
        } else {
            playlistsNode = XMLElement(name: "PLAYLISTS")
            root.addChild(playlistsNode)
        }

        // Find or create root NODE
        let rootNode: XMLElement
        if let existing = playlistsNode.elements(forName: "NODE").first {
            rootNode = existing
        } else {
            rootNode = XMLElement(name: "NODE")
            rootNode.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "FOLDER") as! XMLNode)
            rootNode.addAttribute(XMLNode.attribute(withName: "NAME", stringValue: "$ROOT") as! XMLNode)
            playlistsNode.addChild(rootNode)
        }

        // Create playlist node
        let plNode = XMLElement(name: "NODE")
        plNode.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "PLAYLIST") as! XMLNode)
        plNode.addAttribute(XMLNode.attribute(withName: "NAME", stringValue: playlist.name) as! XMLNode)

        let plContent = XMLElement(name: "PLAYLIST")
        plContent.addAttribute(XMLNode.attribute(withName: "ENTRIES", stringValue: String(playlist.tracks.count)) as! XMLNode)
        plContent.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "LIST") as! XMLNode)
        plContent.addAttribute(XMLNode.attribute(withName: "UUID", stringValue: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) as! XMLNode)

        // Add track entries
        for track in playlist.tracks {
            let entry = XMLElement(name: "ENTRY")
            let primaryKey = XMLElement(name: "PRIMARYKEY")
            primaryKey.addAttribute(XMLNode.attribute(withName: "TYPE", stringValue: "TRACK") as! XMLNode)
            primaryKey.addAttribute(XMLNode.attribute(withName: "KEY", stringValue: buildNMLKey(for: track)) as! XMLNode)
            entry.addChild(primaryKey)
            plContent.addChild(entry)
        }

        plNode.addChild(plContent)

        // Traktor 4.5+ uses <SUBNODES COUNT="N"> wrapper inside $ROOT
        let subnodesWrapper: XMLElement
        if let existing = rootNode.elements(forName: "SUBNODES").first {
            subnodesWrapper = existing
        } else {
            // Fallback: add directly to rootNode for older versions
            rootNode.addChild(plNode)
            return
        }

        subnodesWrapper.addChild(plNode)
        // Update SUBNODES COUNT attribute
        let newCount = subnodesWrapper.elements(forName: "NODE").count
        if let countAttr = subnodesWrapper.attribute(forName: "COUNT") {
            countAttr.stringValue = String(newCount)
        } else {
            subnodesWrapper.addAttribute(XMLNode.attribute(withName: "COUNT", stringValue: String(newCount)) as! XMLNode)
        }

        // Ensure tracks exist in COLLECTION
        try ensureTracksInCollection(playlist.tracks, root: root)

        // Write back to file
        try writeDocument()
        try load() // Reload
    }

    /// Remove a playlist from the Traktor collection.nml
    func removePlaylist(named name: String) throws {
        guard let doc = xmlDocument, let root = doc.rootElement() else {
            throw TraktorError.invalidXML
        }

        guard let playlistsNode = root.elements(forName: "PLAYLISTS").first,
              let rootNode = playlistsNode.elements(forName: "NODE").first else {
            return
        }

        removePlaylistNode(named: name, from: rootNode)
        try writeDocument()
        try load()
    }

    private func removePlaylistNode(named name: String, from node: XMLElement) {
        // Check inside SUBNODES wrapper first (Traktor 4.5+)
        let container: XMLElement
        if let subnodes = node.elements(forName: "SUBNODES").first {
            container = subnodes
        } else {
            container = node
        }

        for child in container.elements(forName: "NODE").reversed() {
            let childName = child.attribute(forName: "NAME")?.stringValue ?? ""
            let type = child.attribute(forName: "TYPE")?.stringValue ?? ""

            if type == "PLAYLIST" && childName == name {
                child.detach()
                // Update COUNT
                if let countAttr = container.attribute(forName: "COUNT") {
                    countAttr.stringValue = String(container.elements(forName: "NODE").count)
                }
                return
            } else if type == "FOLDER" {
                removePlaylistNode(named: name, from: child)
            }
        }
    }

    /// Rename a playlist in the Traktor collection
    func renamePlaylist(from oldName: String, to newName: String) throws {
        guard let doc = xmlDocument, let root = doc.rootElement() else {
            throw TraktorError.invalidXML
        }

        guard let playlistsNode = root.elements(forName: "PLAYLISTS").first,
              let rootNode = playlistsNode.elements(forName: "NODE").first else {
            return
        }

        renamePlaylistNode(from: oldName, to: newName, in: rootNode)
        try writeDocument()
        try load()
    }

    private func renamePlaylistNode(from oldName: String, to newName: String, in node: XMLElement) {
        let container: XMLElement
        if let subnodes = node.elements(forName: "SUBNODES").first {
            container = subnodes
        } else {
            container = node
        }

        for child in container.elements(forName: "NODE") {
            let childName = child.attribute(forName: "NAME")?.stringValue ?? ""
            let type = child.attribute(forName: "TYPE")?.stringValue ?? ""

            if type == "PLAYLIST" && childName == oldName {
                if let attr = child.attribute(forName: "NAME") {
                    attr.stringValue = newName
                }
                return
            } else if type == "FOLDER" {
                renamePlaylistNode(from: oldName, to: newName, in: child)
            }
        }
    }

    // MARK: - Helpers

    private func ensureTracksInCollection(_ tracks: [Track], root: XMLElement) throws {
        let collectionNode: XMLElement
        if let existing = root.elements(forName: "COLLECTION").first {
            collectionNode = existing
        } else {
            collectionNode = XMLElement(name: "COLLECTION")
            root.insertChild(collectionNode, at: 0)
        }

        // Get existing track keys
        var existingKeys = Set<String>()
        for entry in collectionNode.elements(forName: "ENTRY") {
            existingKeys.insert(buildTraktorEntryKey(entry: entry))
        }

        for track in tracks {
            let key = buildNMLKey(for: track)
            guard !existingKeys.contains(key) else { continue }

            let entry = XMLElement(name: "ENTRY")
            entry.addAttribute(XMLNode.attribute(withName: "TITLE", stringValue: track.title) as! XMLNode)
            entry.addAttribute(XMLNode.attribute(withName: "ARTIST", stringValue: track.artist) as! XMLNode)

            // Location
            let location = XMLElement(name: "LOCATION")
            let (volume, dir, file) = parseFilePathToNML(track.filePath)
            location.addAttribute(XMLNode.attribute(withName: "DIR", stringValue: dir) as! XMLNode)
            location.addAttribute(XMLNode.attribute(withName: "FILE", stringValue: file) as! XMLNode)
            location.addAttribute(XMLNode.attribute(withName: "VOLUME", stringValue: volume) as! XMLNode)
            location.addAttribute(XMLNode.attribute(withName: "VOLUMEID", stringValue: volume) as! XMLNode)
            entry.addChild(location)

            // Tempo
            if let bpm = track.bpm {
                let tempo = XMLElement(name: "TEMPO")
                tempo.addAttribute(XMLNode.attribute(withName: "BPM", stringValue: String(format: "%.6f", bpm)) as! XMLNode)
                entry.addChild(tempo)
            }

            // Musical Key
            if let key = track.key {
                let musicalKey = XMLElement(name: "MUSICAL_KEY")
                musicalKey.addAttribute(XMLNode.attribute(withName: "VALUE", stringValue: camelotToTraktorKey(key)) as! XMLNode)
                entry.addChild(musicalKey)
            }

            collectionNode.addChild(entry)
            existingKeys.insert(key)
        }

        // Update ENTRIES count
        if let entriesAttr = collectionNode.attribute(forName: "ENTRIES") {
            entriesAttr.stringValue = String(collectionNode.elements(forName: "ENTRY").count)
        } else {
            collectionNode.addAttribute(XMLNode.attribute(withName: "ENTRIES", stringValue: String(collectionNode.elements(forName: "ENTRY").count)) as! XMLNode)
        }
    }

    private func buildNMLKey(for track: Track) -> String {
        let (volume, dir, file) = parseFilePathToNML(track.filePath)
        return "\(volume)\(dir)\(file)"
    }

    private func parseFilePathToNML(_ path: String) -> (volume: String, dir: String, file: String) {
        let url = URL(fileURLWithPath: path)
        let file = url.lastPathComponent
        var dirPath = url.deletingLastPathComponent().path

        // Determine volume
        var volume = "Macintosh HD"
        if dirPath.hasPrefix("/Volumes/") {
            let components = dirPath.dropFirst("/Volumes/".count).split(separator: "/", maxSplits: 1)
            if let vol = components.first {
                volume = String(vol)
                dirPath = "/" + (components.count > 1 ? String(components[1]) : "")
            }
        }

        // Convert path to Traktor format: /:/Users/:/ etc.
        let traktorDir = dirPath.split(separator: "/").map { "/:\(String($0))" }.joined() + "/:"
        let finalDir = traktorDir.isEmpty ? "/:" : traktorDir

        return (volume, finalDir, file)
    }

    private func writeDocument() throws {
        guard let doc = xmlDocument else { throw TraktorError.invalidXML }
        // Write without pretty-print to preserve Traktor's expected compact format
        let xmlData = doc.xmlData(options: [.nodeCompactEmptyElement])
        let url = URL(fileURLWithPath: nmlPath)
        try xmlData.write(to: url)
    }

    // MARK: - Key Conversion

    /// Convert Traktor's numeric key value to Camelot notation
    private func traktorKeyToCamelot(_ value: String) -> String? {
        guard let intValue = Int(value) else { return value }
        // Traktor key values (0-23): 0=C major, 1=C# major, etc.
        // Even = major (B suffix), Odd after 11 = minor (A suffix)
        let camelotMap: [Int: String] = [
            0: "8B",  1: "3B",  2: "10B", 3: "5B",  4: "12B", 5: "7B",
            6: "2B",  7: "9B",  8: "4B",  9: "11B", 10: "6B", 11: "1B",
            12: "5A", 13: "12A", 14: "7A", 15: "2A", 16: "9A", 17: "4A",
            18: "11A", 19: "6A", 20: "1A", 21: "8A", 22: "3A", 23: "10A"
        ]
        return camelotMap[intValue] ?? value
    }

    /// Convert Camelot notation to Traktor's numeric key value
    private func camelotToTraktorKey(_ camelot: String) -> String {
        let reverseMap: [String: Int] = [
            "8B": 0,  "3B": 1,  "10B": 2, "5B": 3,  "12B": 4, "7B": 5,
            "2B": 6,  "9B": 7,  "4B": 8,  "11B": 9, "6B": 10, "1B": 11,
            "5A": 12, "12A": 13, "7A": 14, "2A": 15, "9A": 16, "4A": 17,
            "11A": 18, "6A": 19, "1A": 20, "8A": 21, "3A": 22, "10A": 23
        ]
        if let value = reverseMap[camelot.uppercased()] {
            return String(value)
        }
        return camelot
    }

    // MARK: - Public Path Accessor

    var filePath: String { nmlPath }

    // MARK: - Errors

    enum TraktorError: LocalizedError {
        case fileNotFound(String)
        case invalidXML

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Traktor collection.nml not found at: \(path)"
            case .invalidXML:
                return "Invalid or missing XML in collection.nml"
            }
        }
    }
}
