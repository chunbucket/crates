# Cuts

Menu bar record player for YouTube → FLAC. Drag a YouTube link (Safari address
bar, any browser, plain text) onto the shelf that slides in from the right, or
onto the menu bar icon. The record spins while yt-dlp cuts it, then the FLAC is
filed in your cuts folder with art, title and source URL embedded. Click the
icon for the collection; drag any row straight into Ableton or Finder.

## Build

    ./build.sh          # → build/Cuts.app  (downloads pinned yt-dlp/ffmpeg/deno on first run)
    ./build.sh dmg      # → build/Cuts-<version>.dmg

Swift 5.10+, macOS 14+, Apple silicon. No Xcode project; `swift run` works for
development and falls back to Homebrew's yt-dlp/ffmpeg/deno.

## Installing an unsigned build

Until the app is signed with a Developer ID, macOS will refuse to open a
downloaded copy. Once: System Settings › Privacy & Security › scroll to the
"Cuts was blocked" line › Open Anyway.

## Where things live

- Cuts folder: Settings… (default `~/Music/Cuts`)
- Index + art + logs: `~/Library/Application Support/Cuts/`
- Updated yt-dlp (Settings › Update): `~/Library/Application Support/Cuts/bin/`
- Automation: `open "cuts://cut?url=<percent-encoded YouTube URL>"`
