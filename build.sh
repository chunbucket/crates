#!/bin/bash
# Build Cuts.app from the SPM package — no Xcode project needed.
#
#   ./build.sh fetch     download the pinned tools into vendor/ (sha256-checked)
#   ./build.sh           build + stage + sign → build/Cuts.app (fetches first if vendor/ is empty)
#   ./build.sh dmg       …then package → build/Cuts-<version>.dmg
#
# Signing is ad-hoc by default (runs on this Mac; other Macs need
# System Settings › Privacy & Security › Open Anyway). For a real release:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=cuts ./build.sh dmg
# where NOTARY_PROFILE is a keychain profile from `xcrun notarytool store-credentials`.
set -euo pipefail
cd "$(dirname "$0")"
source vendor.env

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP=build/Cuts.app
BIN="$APP/Contents/MacOS"
# yt-dlp's onedir tree mixes dylibs with zips/.py files. codesign treats
# everything under MacOS/ as code, so the tree lives under Resources/ (sealed
# by hash) with every Mach-O inside signed individually.
YTDLP="$APP/Contents/Resources/yt-dlp_macos"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# ---------- vendor ----------

fetch_one() { # url dest sha256
    local url=$1 dest=$2 sha=$3
    if [ -f "$dest" ] && echo "$sha  $dest" | shasum -a 256 -c --status; then return; fi
    echo "fetching $(basename "$dest")"
    curl -fsSL -o "$dest" "$url"
    echo "$sha  $dest" | shasum -a 256 -c --status || { echo "sha256 mismatch: $dest"; exit 1; }
}

fetch() {
    mkdir -p vendor
    fetch_one "$YTDLP_URL"  vendor/yt-dlp_macos.zip "$YTDLP_SHA256"
    fetch_one "$DENO_URL"   vendor/deno.zip         "$DENO_SHA256"
    fetch_one "$FFMPEG_URL" vendor/ffmpeg.zip       "$FFMPEG_SHA256"
    rm -rf vendor/yt-dlp_macos && mkdir -p vendor/yt-dlp_macos
    unzip -q vendor/yt-dlp_macos.zip -d vendor/yt-dlp_macos   # zip root = yt-dlp_macos + _internal/
    unzip -o -q vendor/ffmpeg.zip -d vendor
    unzip -o -q vendor/deno.zip -d vendor
    chmod +x vendor/deno vendor/ffmpeg vendor/yt-dlp_macos/yt-dlp_macos
    echo "vendor/ ready: yt-dlp $YTDLP_VERSION · ffmpeg $FFMPEG_VERSION · deno $DENO_VERSION"
}

# ---------- build ----------

# One pass over the tree: every Mach-O path into MACHOS, universal ones
# thinned to arm64 on the way (v1 is Apple-silicon only).
MACHOS=()
collect_machos() {
    local f kind
    while IFS= read -r -d '' f; do
        kind=$(file -b "$f")
        case "$kind" in
            *"Mach-O universal"*) lipo -thin arm64 "$f" -output "$f.thin" && mv "$f.thin" "$f"; MACHOS+=("$f") ;;
            *Mach-O*) MACHOS+=("$f") ;;
        esac
    done < <(find "$1" -type f -not -path "*.framework/*" -print0)
}

# The release zip stores the framework's symlinks as duplicate files, which
# codesign calls "ambiguous". Restore the standard layout so it signs as a
# framework (and drops two spare copies of the Python binary).
fix_framework() {
    local fw=$1 ver
    [ -d "$fw/Versions" ] || return 0
    ver=$(ls "$fw/Versions" | grep -v '^Current$' | head -1)
    rm -rf "$fw/Versions/Current" "$fw/Python" "$fw/Resources"
    ln -s "$ver" "$fw/Versions/Current"
    ln -s Versions/Current/Python "$fw/Python"
    ln -s Versions/Current/Resources "$fw/Resources"
}

# ENTITLEMENTS=<plist> sign target…  — hardened runtime, timestamp and
# entitlements only mean something with a real identity.
sign() {
    if [ "$SIGN_IDENTITY" = "-" ]; then
        codesign --force -s - "$@"
    else
        codesign --force --options runtime --timestamp ${ENTITLEMENTS:+--entitlements "$ENTITLEMENTS"} -s "$SIGN_IDENTITY" "$@"
    fi
}

build() {
    [ -x vendor/yt-dlp_macos/yt-dlp_macos ] && [ -x vendor/ffmpeg ] && [ -x vendor/deno ] || fetch

    swift build -c release
    lipo -info .build/release/Cuts | grep -q arm64 || { echo "expected an arm64 build"; exit 1; }

    rm -rf "$APP"
    mkdir -p "$BIN" "$APP/Contents/Resources"
    cp .build/release/Cuts "$BIN/Cuts"
    cp Resources/Info.plist "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
    plutil -replace CutsBundledYtdlp -string "$YTDLP_VERSION" "$APP/Contents/Info.plist"
    cp THIRD-PARTY-LICENSES.md "$APP/Contents/Resources/"

    cp -R vendor/yt-dlp_macos "$YTDLP"
    cp vendor/ffmpeg vendor/deno "$BIN/"
    fix_framework "$YTDLP/_internal/Python.framework"
    xattr -cr "$APP"

    # Sign inside-out: yt-dlp's dylibs in one batch, its Python.framework (as
    # a bundle), its executable, ffmpeg, deno, then the app. No --deep.
    collect_machos "$YTDLP/_internal"
    sign "${MACHOS[@]}"
    sign "$YTDLP/_internal/Python.framework"
    ENTITLEMENTS=Resources/entitlements.plist      sign "$YTDLP/yt-dlp_macos"
    sign "$BIN/ffmpeg"
    ENTITLEMENTS=Resources/entitlements-deno.plist sign "$BIN/deno"
    sign "$APP"
    codesign --verify --strict "$APP" "$YTDLP/yt-dlp_macos" "$YTDLP/_internal/Python.framework" "$BIN/ffmpeg" "$BIN/deno"

    echo "Built $APP · $(du -sh "$APP" | cut -f1) · signed as '$SIGN_IDENTITY' · yt-dlp $YTDLP_VERSION"
}

# ---------- dmg ----------

dmg() {
    build
    local stage=build/dmg out="build/Cuts-$VERSION.dmg"
    rm -rf "$stage" "$out"
    mkdir -p "$stage"
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -quiet -volname Cuts -srcfolder "$stage" -ov -format UDZO "$out"
    rm -rf "$stage"
    if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" != "-" ]; then
        xcrun notarytool submit "$out" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$out"
    fi
    echo "Packaged $out · $(du -sh "$out" | cut -f1)"
}

case "${1:-build}" in
    fetch) fetch ;;
    build) build ;;
    dmg)   dmg ;;
    *) echo "usage: ./build.sh [fetch|build|dmg]"; exit 2 ;;
esac
