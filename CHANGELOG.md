# Changelog

Release notes are lifted from here by `./build.sh release`: everything under a
version heading, up to the next one.

## 0.3.0

First public build.

- Drop a link onto the menu bar icon or the tray; the record spins while it
  records and the FLAC is filed with art, title and source embedded.
- Crates: an All crate and an Unsorted crate, plus your own. Drag a record onto
  a crate or use its menu. Sort by date, BPM or key; filter sorted/unsorted.
- Every record is analysed for BPM and key after it files.
- Play and scrub any record, drag it straight into Ableton or Finder, retry a
  failed one, remove it (optionally trashing the file).
- Self-contained: yt-dlp, ffmpeg and deno ship inside the app. Update yt-dlp
  from Settings when a site changes something.
- Settings: records folder, launch at login, what "remove" does with the file.
- Checks GitHub once a day for a newer release and says so in the menu.
