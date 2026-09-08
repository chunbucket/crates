# Cuts

A menu bar record player for the Mac that turns a YouTube link into a FLAC in
your sample folder.

Drag a link from the address bar onto the menu bar icon, or onto the tray that
slides in from the right. The record spins while it cuts; then the file is
filed with the art, title and source link embedded. Click the icon for the
shelf: play and scrub any cut, drag it straight into Ableton or Finder, retry
one that failed.

**Apple silicon, macOS 14 or later.** Download: <https://ency.world/cuts>

## What it talks to

YouTube, to fetch the audio. GitHub, once a day, to see whether there is a
newer version (it tells you; nothing installs itself). That is all. Nothing is
sent anywhere.

## Inside

Swift + AppKit + SwiftUI, no Xcode project. Bundled: [yt-dlp](https://github.com/yt-dlp/yt-dlp)
(does the download), a static [FFmpeg](https://ffmpeg.org) (presses it to FLAC),
and [deno](https://deno.com) (yt-dlp's JavaScript runtime for YouTube's
challenges). See `THIRD-PARTY-LICENSES.md`.

## Build from source

    ./build.sh          # downloads the pinned tools into vendor/, builds build/Cuts.app
    ./build.sh dmg      # …and packages build/Cuts.dmg

Swift 5.10+. `swift run` also works for development and falls back to
Homebrew's yt-dlp, ffmpeg and deno. Releasing is described in `RELEASING.md`.

## Where things live

- Cuts folder: Settings… (default `~/Music/Cuts`)
- Index, art, logs: `~/Library/Application Support/Cuts/`
- Automation: `open "cuts://cut?url=<percent-encoded YouTube URL>"`

MIT licensed.
