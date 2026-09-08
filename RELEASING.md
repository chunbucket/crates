# Releasing Cuts

One-time setup (needs a paid Apple Developer account):

1. Xcode › Settings › Accounts › your Apple ID › **Manage Certificates…** › **+** › *Developer ID Application*.
2. Find its name: `security find-identity -v -p codesigning` — the line that says
   `Developer ID Application: Your Name (TEAMID)`.
3. Make an app-specific password at appleid.apple.com › Sign-In and Security.
4. Store it for notarytool:
   `xcrun notarytool store-credentials cuts --apple-id you@example.com --team-id TEAMID --password <app-specific>`

Every release:

```
./build.sh bump 0.3.1        # writes Resources/Info.plist; then describe the change in CHANGELOG.md
git commit -am "0.3.1"
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=cuts ./build.sh release
```

`release` refuses a dirty tree, builds and notarizes `build/Cuts.dmg`, checks
Gatekeeper accepts it, tags `v0.3.1`, pushes, and publishes a GitHub release
with the DMG attached and the CHANGELOG section as notes. The download link on
the site never changes: `…/releases/latest/download/Cuts.dmg`.

Rehearsal without a certificate: `UNSIGNED=1 ./build.sh release --draft` makes
a draft release (invisible; `latest` ignores drafts) you can inspect and delete.
