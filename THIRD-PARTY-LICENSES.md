# Third-party software bundled in Cuts.app

Cuts runs these as separate processes; none are linked into the app.

## yt-dlp
`Contents/MacOS/yt-dlp_macos/` — official standalone macOS build.
License: The Unlicense (public domain). Source: https://github.com/yt-dlp/yt-dlp
Bundled with it: the yt-dlp-ejs challenge scripts (same project) and a
PyInstaller-packaged CPython runtime (PSF License).

## Deno
`Contents/MacOS/deno` — JavaScript runtime yt-dlp uses for YouTube's challenges.
License: MIT. Source: https://github.com/denoland/deno

## FFmpeg
`Contents/MacOS/ffmpeg` — static build by Martin Riedl (https://ffmpeg.martin-riedl.de),
configured with `--enable-gpl --enable-version3`.
License: GNU GPL v3. FFmpeg source: https://ffmpeg.org/download.html · build
scripts and exact configuration: https://ffmpeg.martin-riedl.de (versions.txt
next to each download). Full license text: https://www.gnu.org/licenses/gpl-3.0.txt
