# Changelog

Release notes are lifted from here by `./build.sh release`: everything under a
version heading, up to the next one.

## 0.3.0

First public build.

- Drag a YouTube link onto the menu bar icon or the tray; the record spins
  while it cuts and the FLAC is filed with art, title and source embedded.
- The shelf: play and scrub any cut, drag it straight into Ableton or Finder,
  retry a failed one, remove it (optionally trashing the file).
- Self-contained: yt-dlp, ffmpeg and deno ship inside the app. Update yt-dlp
  from Settings when YouTube changes something.
- Settings: cuts folder, launch at login, what "remove" does with the file.
- Checks GitHub once a day for a newer release and says so in the menu.
