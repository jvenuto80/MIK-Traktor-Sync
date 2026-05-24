# SyncDeck — MIK → Traktor Playlist Sync

A native macOS app that syncs playlists from **Mixed In Key** to **Traktor Pro 4**.

One-directional sync ensures the MIK database is never modified — only Traktor's `collection.nml` is written to.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **One-click playlist sync** — Push MIK playlists to Traktor with a single button
- **Auto-sync** — Watches the MIK database for changes and syncs automatically
- **Smart playlist ordering** — Reorder tracks by energy arc, Camelot key flow, or both for optimal DJ set flow
- **Pre-sync validation** — Checks all file paths exist before syncing to catch moved/deleted files
- **Playlist diff view** — See exactly what will change before syncing (additions/removals)
- **Sync history** — Browse past sync operations to see what changed over time
- **Backup browser** — View and restore previous `collection.nml` backups
- **Export** — Export playlists as NML, M3U, or CSV

## How It Works

1. Reads playlists from MIK's SQLite database (`Collection11.mikdb`)
2. Reads Traktor's `collection.nml` XML
3. Compares track lists and shows diffs
4. On sync: backs up the NML, then writes updated playlists

## Requirements

- macOS 13+
- Mixed In Key 11
- Traktor Pro 4.x

## Build

```bash
# Debug build + run
swift build && .build/debug/MIKTraktorSync

# Release .app bundle
./bundle.sh
open build/MIKTraktorSync.app

# Install to Applications
cp -r build/MIKTraktorSync.app /Applications/
```

## Project Structure

```
MIKTraktorSync/
├── App/                    # App entry point, AppState
├── Models/                 # Track, Playlist, MIKDatabase, TraktorCollection
├── Sync/                   # SyncEngine, DiffHistory
├── Views/                  # SwiftUI views (sidebar, track list, diff, history, validation, backups)
└── Utilities/              # BackupManager, FileWatcher, PlaylistExporter, SmartPlaylistOrderer, PreSyncValidator
```

## File Paths

| Source | Path |
|--------|------|
| MIK Database | `~/Library/Application Support/Mixedinkey/Collection11.mikdb` |
| Traktor NML | `~/Documents/Native Instruments/Traktor 4.x.x/collection.nml` |
| Backups | `~/Library/Application Support/MIKTraktorSync/backups/` |
| Sync History | `~/Library/Application Support/MIKTraktorSync/diff_history.json` |

## License

MIT
