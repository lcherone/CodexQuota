# Build and run

Codex Quota is a Mac menu-bar app for macOS 14 or later. Building requires Swift 6 (Xcode or Command Line Tools). Running requires a separately installed Codex CLI; the utility does not bundle it or require an API key.

## Install and open

From a checkout of this repository:

```sh
./scripts/install-app.sh
open "$HOME/Applications/CodexQuota.app"
```

The script builds a release app, verifies its signature, and copies it to `~/Applications`. No administrator access is needed. Open the app to show its panel. Click the menu-bar figure to toggle it, or open the app again in Finder to bring it back. Escape and clicks outside dismiss the panel. Quit is on the footer; Command-Q also quits.

To use a different installation directory:

```sh
./scripts/install-app.sh --destination /Applications
```

That directory must be writable. The default user Applications folder avoids a permission prompt. Startup controls are available when the app lives inside `/Applications` or `~/Applications`.

## Launch at login

Open **Settings** from the installed app’s footer and enable **Launch at login**. The app uses [macOS Service Management](https://developer.apple.com/documentation/servicemanagement/smappservice) to register itself as a login item. The checkbox reads the actual system state rather than a saved app preference. If macOS requires approval, use **Open Login Items** in Settings and allow Codex Quota in System Settings. Settings also contains quota alerts, the weekly threshold, and appearance. Back or Escape returns to the previous quota view; changes save automatically.

At login the app refreshes accounts in the background and leaves the panel closed. Opening it in Finder shows the panel. Turn the checkbox off to stop automatic startup; you can also manage it in System Settings → General → Login Items. Quitting stops the current session without disabling the next login launch.

## Bundle and ZIP

```sh
./scripts/build-app.sh
```

Outputs:

- `build/CodexQuota.app`: release executable, icon, and application metadata, signed ad hoc and verified.
- `build/CodexQuota.zip`: the same bundle archived with its resources for copying to another compatible Mac.

The build targets the Mac architecture it runs on, not a universal binary. This is a local build without Developer ID signing or notarization; it is not a published distribution release. The other Mac still needs macOS 14+ and the Codex CLI. `LSUIElement` and the runtime accessory policy keep the Dock icon hidden.

You can open the build directly, but move or install it into Applications before enabling startup:

```sh
open build/CodexQuota.app
./scripts/install-app.sh --no-build
```

The installer refuses to update a running Codex Quota process or replace an unrelated app/symlink. To update, quit the app, rerun the installer, then open the installed copy. Account data lives outside the bundle and is retained. Check Launch at login after updating; macOS can ask for approval again when signed code changes.

## Development

```sh
swift build --product CodexQuota
swift run CodexQuota
```

The binary is `.build/debug/CodexQuota`. Startup registration is disabled for unbundled development launches. `--background` leaves the panel closed, useful for testing a background launch:

```sh
open -a "$HOME/Applications/CodexQuota.app" --args --background
```

Quit any running instance first; opening an existing instance brings its panel back.

## Codex CLI discovery

The app checks `CODEX_BIN`, then `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `/usr/bin/codex`, and finally `PATH`. An installed app or login item does not inherit your shell startup configuration. Put Codex in one of those standard locations if it only works from a terminal. `CODEX_BIN` is useful for a development launch with a custom executable.

## Uninstall

Disable **Launch at login**, quit, then move CodexQuota.app from Applications to the Trash. This keeps your readings and account homes. Removing an account inside the app deletes that account's app-created Codex home and its recorded history, after confirmation.

## What stays on this Mac

Each account has its own Codex home, created by the app. Sign-in opens in the browser and finishes in that home. Tokens are not copied into the library.

Readings, account names, and the Light, Dark, or System choice live in:

`~/Library/Application Support/CodexQuota/store.json`

The file is mode `0600`. The directory is mode `0700`. `CODEX_QUOTA_DIR` points the app at another directory. That is how a local smoke launch avoids a real library.

## Checks

```sh
swift run CodexQuotaChecks
```

The checks use `Tests/Fixtures/mock_app_server.py` and controlled model dependencies. They do not call OpenAI and they do not read a Codex home that already has a login. The project uses an executable check suite rather than an XCTest bundle.

The pacing rules those checks lock are written up in [quota-app-plan.md](quota-app-plan.md).

For UI examples, see the [feature guide and gallery](FEATURES.md). For isolated demo data and documentation assets, use the [showcase workflow](SHOWCASE.md#capture-safe-demo-material).
