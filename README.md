# Crates

A menu bar record player for the Mac. Drop a link, get a record.

Drag a link from the address bar onto the menu bar icon, or onto the tray that
slides in from the right. The record spins while it records; then the FLAC is
filed in your crate with the art, title and source embedded. Click the icon to
browse your crates: play and scrub any record, drag it straight into Ableton
or Finder, sort by date, BPM or key, and file records into crates of your own.

For material you have the right to record. **Apple silicon, macOS 14 or later.**
Download: <https://ency.world/crates>

## What it talks to

The site the link points at, to fetch the audio. GitHub, once a day, to see
whether there is a newer version (it tells you; nothing installs itself). That
is all. Nothing is sent anywhere.

## Inside

Swift + AppKit + SwiftUI, no Xcode project. Bundled: [yt-dlp](https://github.com/yt-dlp/yt-dlp)
(fetches the audio), a static [FFmpeg](https://ffmpeg.org) (presses it to FLAC),
and [deno](https://deno.com) (yt-dlp's JavaScript runtime). BPM and key are
analysed in-app with Accelerate. See `THIRD-PARTY-LICENSES.md`.

## Build from source

    ./build.sh          # downloads the pinned tools into vendor/, builds build/Crates.app
    ./build.sh dmg      # …and packages build/Crates.dmg

Swift 5.10+. `swift run` also works for development and falls back to
Homebrew's yt-dlp, ffmpeg and deno. Releasing is described in `RELEASING.md`.

## Where things live

- Records folder: Settings… (default `~/Music/Crates`)
- Index, art, logs: `~/Library/Application Support/Crates/`
- Automation: `open "crates://record?url=<percent-encoded link>"`

MIT licensed.
