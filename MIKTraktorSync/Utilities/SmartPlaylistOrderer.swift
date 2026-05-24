import Foundation

/// Orders tracks for smooth DJ mixing based on energy arc and harmonic (Camelot) key flow.
/// Does NOT analyze tracks (that's MIK's job) — only reorders based on existing metadata.
struct SmartPlaylistOrderer {

    enum Strategy: String, CaseIterable {
        case energyArc = "Energy Arc"
        case keyFlow = "Key Flow (Camelot)"
        case energyAndKey = "Energy + Key"
    }

    /// Reorder tracks using the selected strategy
    static func order(tracks: [Track], strategy: Strategy) -> [Track] {
        switch strategy {
        case .energyArc:
            return orderByEnergyArc(tracks)
        case .keyFlow:
            return orderByKeyFlow(tracks)
        case .energyAndKey:
            return orderByEnergyAndKey(tracks)
        }
    }

    // MARK: - Energy Arc

    /// Classic DJ energy arc: start medium, build up, peak, then wind down
    private static func orderByEnergyArc(_ tracks: [Track]) -> [Track] {
        let sorted = tracks.sorted { ($0.energy ?? 5) < ($1.energy ?? 5) }
        guard sorted.count > 2 else { return sorted }

        // Split into low/mid/high energy groups
        let third = sorted.count / 3
        let low = Array(sorted.prefix(third))
        let mid = Array(sorted.dropFirst(third).prefix(third))
        let high = Array(sorted.dropFirst(third * 2))

        // Arc: mid intro → build to high → wind down through mid → end low
        var result: [Track] = []
        result.append(contentsOf: mid.prefix(mid.count / 2))  // warm up
        result.append(contentsOf: high)                         // peak
        result.append(contentsOf: mid.suffix(mid.count / 2))   // cool down
        result.append(contentsOf: low)                          // outro
        return result
    }

    // MARK: - Key Flow (Camelot Wheel)

    /// Order tracks to follow the Camelot wheel for harmonic mixing.
    /// Adjacent numbers (+1/-1) or same number different letter (A↔B) are compatible.
    private static func orderByKeyFlow(_ tracks: [Track]) -> [Track] {
        guard !tracks.isEmpty else { return [] }

        var remaining = tracks
        var ordered: [Track] = []

        // Start with first track
        ordered.append(remaining.removeFirst())

        while !remaining.isEmpty {
            let lastKey = ordered.last?.key
            // Find the best next track (harmonically compatible)
            if let lastKey = lastKey,
               let bestIdx = findBestHarmonicMatch(for: lastKey, in: remaining) {
                ordered.append(remaining.remove(at: bestIdx))
            } else {
                // No harmonic match found, just take the next one
                ordered.append(remaining.removeFirst())
            }
        }

        return ordered
    }

    // MARK: - Combined Energy + Key

    /// Order by energy arc, then within each energy tier, optimize for key flow
    private static func orderByEnergyAndKey(_ tracks: [Track]) -> [Track] {
        let sorted = tracks.sorted { ($0.energy ?? 5) < ($1.energy ?? 5) }
        guard sorted.count > 2 else { return orderByKeyFlow(sorted) }

        let third = sorted.count / 3
        let low = Array(sorted.prefix(third))
        let mid = Array(sorted.dropFirst(third).prefix(third))
        let high = Array(sorted.dropFirst(third * 2))

        // Apply key flow within each energy tier, then assemble arc
        var result: [Track] = []
        let midOrdered = orderByKeyFlow(mid)
        let highOrdered = orderByKeyFlow(high)
        let lowOrdered = orderByKeyFlow(low)

        result.append(contentsOf: midOrdered.prefix(midOrdered.count / 2))
        result.append(contentsOf: highOrdered)
        result.append(contentsOf: midOrdered.suffix(midOrdered.count / 2))
        result.append(contentsOf: lowOrdered)
        return result
    }

    // MARK: - Camelot Helpers

    /// Find the index of the best harmonically compatible track
    private static func findBestHarmonicMatch(for key: String, in tracks: [Track]) -> Int? {
        let compatible = compatibleKeys(for: key)

        // Priority 1: same key
        if let idx = tracks.firstIndex(where: { $0.key == key }) {
            return idx
        }
        // Priority 2: compatible key (+1, -1, or A↔B swap)
        if let idx = tracks.firstIndex(where: { compatible.contains($0.key ?? "") }) {
            return idx
        }
        return nil
    }

    /// Returns Camelot keys that mix well with the given key
    static func compatibleKeys(for key: String) -> Set<String> {
        guard let (number, letter) = parseCamelot(key) else { return [] }
        var keys = Set<String>()

        // Same position (identical key)
        keys.insert(key)
        // +1 semitone (energy boost)
        keys.insert("\(number == 12 ? 1 : number + 1)\(letter)")
        // -1 semitone (energy drop)
        keys.insert("\(number == 1 ? 12 : number - 1)\(letter)")
        // Inner/outer switch (A↔B, relative major/minor)
        keys.insert("\(number)\(letter == "A" ? "B" : "A")")

        return keys
    }

    /// Parse "8A" → (8, "A")
    private static func parseCamelot(_ key: String) -> (number: Int, letter: String)? {
        let upper = key.uppercased().trimmingCharacters(in: .whitespaces)
        guard upper.hasSuffix("A") || upper.hasSuffix("B") else { return nil }
        let letter = String(upper.last!)
        let numStr = String(upper.dropLast())
        guard let number = Int(numStr), number >= 1, number <= 12 else { return nil }
        return (number, letter)
    }
}
