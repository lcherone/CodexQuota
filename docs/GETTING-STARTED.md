# Build and run

Codex Quota is a Mac menu-bar app. It needs macOS 14 or later and Swift 6, the toolchain that ships with current Xcode or the Command Line Tools.

From a checkout of this repository:

```sh
swift build --product CodexQuota
swift run CodexQuota
```

The binary is `.build/debug/CodexQuota`. You can launch that file directly. A usage figure appears in the menu bar. Click it to open the panel. Quit is on the footer.

## A double-clickable app

```sh
./scripts/build-app.sh
open build/CodexQuota.app
```

The script builds a release binary, wraps it as `build/CodexQuota.app`, and signs it ad hoc. `LSUIElement` in `Support/Info.plist` keeps the Dock icon hidden. The running process also uses the accessory activation policy, so a `swift run` launch hides the Dock icon too.

## What stays on this Mac

Each account has its own Codex home, created by the app. Sign-in opens in the browser and finishes in that home. Tokens are not copied into the library.

Readings, account names, and the Light, Dark, or System choice live in:

`~/Library/Application Support/CodexQuota/store.json`

The file is mode `0600`. The directory is mode `0700`. `CODEX_QUOTA_DIR` points the app at another directory. That is how a local smoke launch avoids a real library.

## Checks

```sh
swift run CodexQuotaChecks
```

The checks talk only to `Tests/Fixtures/mock_app_server.py`. They do not call OpenAI and they do not read a Codex home that already has a login. This Mac's command-line tools do not include XCTest, so the checks are a small executable rather than an XCTest bundle.

The pacing rules those checks lock are written up in [quota-app-plan.md](quota-app-plan.md).
