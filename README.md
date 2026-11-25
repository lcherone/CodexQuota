# CodexQuota

A menu-bar panel for pacing a Codex weekly allowance on Mac. It shows more than one account, each with its own Codex home. The status item shows today's slice as a percent of the week. The panel shows that figure, whether the day and week are ahead of an even pace, the accounts, and week history. System, Light, and Dark sit on the panel footer. The choice is kept in `store.json`.

Sign-in opens in the browser. Tokens stay in that account's Codex home. The library under `~/Library/Application Support/CodexQuota` stores readings, not tokens.

## Panel

Light and dark are the same layout. The status item stays in the menu bar. Click it to show or hide this panel.

![Codex Quota in light](docs/images/panel-light.png)

![Codex Quota in dark](docs/images/panel-dark.png)

The lower part of a full reading, including week stats and the theme control:

![Week stats and theme control](docs/images/weeks-dark.png)

Empty, before an account is added:

![Empty panel in light](docs/images/empty-light.png)

![Empty panel in dark](docs/images/empty-dark.png)

Week history, following the system appearance:

![Week history](docs/images/history-system.png)

Signed out, with the last reading kept:

![Signed out](docs/images/signed-out-dark.png)

A stopped server, with a reading old enough to mark stale:

![Stale reading and server error](docs/images/stale-error.png)

## Build

From `~/CodexQuota`:

```sh
swift build --product CodexQuota
```

The binary is `.build/debug/CodexQuota`.

Checks talk only to the local mock:

```sh
swift run CodexQuotaChecks
```

## Run

```sh
swift run CodexQuota
```

Or launch the binary from the build above. Quit from the bottom of the panel.

To bundle a `.app` (this also sets `LSUIElement`):

```sh
./scripts/build-app.sh
open build/CodexQuota.app
```
