# Codex Quota

A menu-bar app for pacing Codex weekly allowance. This is the decided design for the first version. There is no follow-up question left open in this plan.

## Stack

Swift 6 and SwiftUI on macOS 14, with an AppKit status item. The package is `CodexQuotaCore` (pacing, history, app-server client) and the `CodexQuota` executable (window and menu bar).

GPUI is not the UI. `~/testingapp` shows a GPUI 0.2.2 window and a CEF browser, and it does not create a menu-bar status item. This Mac has Swift and does not have `rustc` or `cargo`, so a GPUI app would not compile here. Login does not need that embedded browser.

The Dock icon stays hidden while the app is running. `LSUIElement` is true, and the process uses the accessory activation policy. The status item stays visible and shows the usage figure. Clicking it opens the main window, and clicking it again while that window is visible closes it. Closing the window leaves the status item running.

Build and test from `~/CodexQuota`:

```sh
swift run CodexQuotaChecks
./scripts/build-app.sh
```

`CodexQuotaChecks` talks only to the local mock in `Tests/Fixtures/mock_app_server.py`. It does not call OpenAI and it does not read a Codex home that already has a login. This Mac's command-line tools do not include XCTest, so the checks are a small executable rather than an XCTest bundle.

## Account model

Any number of accounts. Personal and Work are just the first two suggested names. Every account is an id, a label, and its own `CODEX_HOME`. The app creates that home at:

```text
~/Library/Application Support/CodexQuota/homes/<account-id>
```

That is the same model as `~/codex-router`: one Codex app-server process per account, `CODEX_HOME` pointed at that account's directory, and no reading or copying of token files. Codex Quota does not open `~/.codex` or `~/.ai-router` on its own. To reuse a home that is already signed in, change that account's `codexHome` in `store.json` to the absolute path (for example `~/.ai-router/work` expanded) and leave the directory alone. The app still will not scrape tokens out of it.

Login matches `codex-router`'s `AccountManager.login`:

1. Spawn `codex app-server --listen stdio://` with `CODEX_HOME` set. No `-c` overrides, so this app does not write feature flags into the home.
2. `initialize`, then the `initialized` notification.
3. `account/login/start` with:

```json
{
  "type": "chatgpt",
  "codexStreamlinedLogin": true,
  "useHostedLoginSuccessPage": true,
  "appBrand": "codex"
}
```

4. If the result is `type: chatgpt` and `authUrl` is `https`, open it with `NSWorkspace` (the external browser). Any other scheme is rejected.
5. Poll `account/read` with `refreshToken: false` until `account` is non-null, or until three minutes pass. A notification `account/login/completed` with `success: false` stops the wait.
6. One `account/read` with `refreshToken: true`, then the usage reads below.

Sign-out is `account/logout` for that home only. "Remove from this Mac" deletes a home only when it lives under the app's `homes` directory.

There are no credentials in the repo, the library, or the tests.

## Usage source

The read path matches `OpenDevEngine`'s `CodexProvider.inspect` and the generated app-server types in `~/codex-router`.

After `initialize`, the client sends:

```json
{
  "clientInfo": {"name": "codexquota", "title": "Codex Quota", "version": "0.1.0"},
  "capabilities": {"experimentalApi": true, "requestAttestation": false}
}
```

`requestAttestation` stays false. This app never calls `attestation/generate` and it declines every server request (approvals, tool calls) with JSON-RPC `-32601`. It does not start threads or turns.

Then, for a signed-in account:

| Method | Params | Fields that are used |
| --- | --- | --- |
| `account/read` | `{"refreshToken": false}` on a poll. `true` only once after a new sign-in. | `account.type`, `account.email`, `account.planType`. `account: null` means signed out. |
| `account/rateLimits/read` | `{}` | See the window rules below. |
| `account/usage/read` | `{}` (no `threadId`, so this is the account-wide read) | `summary.lifetimeTokens`, `summary.peakDailyTokens`, `dailyUsageBuckets[].startDate`, `dailyUsageBuckets[].tokens`. |

`GetAccountRateLimitsResponse` has `rateLimits` (the legacy single snapshot) and `rateLimitsByLimitId`. When the map is non-empty, its snapshots are searched first. The legacy snapshot is used only if that search has no weekly window.

Each snapshot has `primary` and `secondary` windows. A window is `usedPercent`, `windowDurationMins`, and `resetsAt`. Also read from the snapshot: `limitId`, `limitName`, `planType`, `rateLimitReachedType`.

The weekly allowance is the window whose `windowDurationMins` is closest to 10080 and lies in 8640...11520 (six to eight days). A snapshot whose id or name is Codex wins over any other weekly window. `usedPercent` is clamped to 0...100, the same ceiling OpenDevEngine applies. The five-hour window (usually `primary` at 300 minutes) is not the pace. If a window of 60...720 minutes exists, the closest one to 300 minutes is shown as a single extra line and is not part of the math.

`resetsAt` below `1e11` is Unix seconds. `resetsAt` at or above `1e11` is Unix milliseconds. The OpenDevEngine fixture uses `1800000000`, which is seconds. Token counts are JSON numbers or integer strings. They are totals, never a remaining-token balance. OpenDevEngine is explicit that quota windows are not an invented token remainder, and this app keeps that split: percents pace the week, tokens are history.

The Codex binary is `CODEX_BIN`, then `~/.local/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `/usr/bin/codex`, then `which codex`. A set but unusable `CODEX_BIN` is an error, not a silent fallback.

RPC timeout is 30 seconds. The menu refreshes every 5 minutes. A reading older than 15 minutes is stale. Server error text is dropped; the window says which method was refused.

## Pacing

Timezone: `Europe/London`, including the reset label and the clock, whatever the Mac's zone is.

The weekly window is the half-open interval `[resetsAt - duration, resetsAt)`. `duration` is `windowDurationMins * 60` seconds. It is split into 7 equal real-time slices. A slice is not a London midnight-to-midnight day, so a clock change does not stretch it. The slice's name is the London calendar date of its midpoint, `yyyy-MM-dd`.

`now == resetsAt` is outside the window. The app asks for a refresh instead of inventing the next week.

Each slice's budget is `100 / 7` percent of the weekly allowance (14.2857...%). "Today" is the slice that contains `now`.

Today's weekly points, in order:

1. **Measured.** Last sample at or before the slice start, subtracted from the last sample inside the slice, for the same `resetsAt`. This is the authority.
2. **Partial.** No sample at or before the start, but two samples inside the slice. The difference is a minimum. It counts as ahead only when that minimum is already over the expected pace. Otherwise today stays unknown.
3. **Estimated.** No samples for that slice. If `dailyUsageBuckets` has this slice's London date, today's points are `usedPercent * todayTokens / sum(tokens for bucket dates that match a slice in this window)`. A missing bucket is not zero. Measured data wins when both exist.
4. **Unknown.** The hero stays on the weekly percent until another check lands in the window.

Expected points so far today are `(elapsed fraction of the slice) * (100 / 7)`. Tolerance is 0.5 weekly points. Above that, today is ahead. Below `expected - 0.5`, today is inside the slice. Between them, today is on the slice.

The week is on an even split by the same tolerance against `elapsed fraction of the whole window * 100`.

The rest of the week has room when `100 - usedPercent` is at least `futureFullSlices * (100 / 7)`. Future slices are the ones that have not started. On the last slice, the line says this is the last slice before the reset. Today can be ahead while later days still have a full slice left, and the window says both.

Samples for a different `resetsAt` belong to another week.

### Example

Reset Wednesday 25 November 2026, 17:00 Europe/London. In November that zone is GMT, so the instant is `2026-11-25T17:00:00Z`. Duration 10080 minutes. The window starts 18 November 2026, 17:00. Slice length is 86400 seconds.

| Slice | Interval (London) | Midpoint date |
| --- | --- | --- |
| 0 | 18 Nov 17:00 → 19 Nov 17:00 | 2026-11-19 |
| 1 | 19 Nov 17:00 → 20 Nov 17:00 | 2026-11-20 |
| 2 | 20 Nov 17:00 → 21 Nov 17:00 | 2026-11-21 |
| 3 | 21 Nov 17:00 → 22 Nov 17:00 | 2026-11-22 |
| 4 | 22 Nov 17:00 → 23 Nov 17:00 | 2026-11-23 |
| 5 | 23 Nov 17:00 → 24 Nov 17:00 | 2026-11-24 |
| 6 | 24 Nov 17:00 → 25 Nov 17:00 | 2026-11-25 |

Now is Tuesday 24 November 2026, 12:00 London. That is slice 5. Elapsed in the slice is 19/24. A sample at 23 November 17:00 says 55% used. The reading now says 62% used.

- Today's weekly points = 62 − 55 = 7.
- Today's share of the slice = 7 / (100/7) × 100 = 49%.
- Expected by 12:00 = (19/24) × (100/7) = 11.3095 points.
- 7 is below 11.3095 − 0.5, so today is inside the slice.
- Remaining = 38. One full slice is still ahead and costs 14.2857. 38 ≥ 14.2857, so the rest of the week has room.
- The window is 139/168 elapsed. An even split would be 82.738% used. 62% is behind that even split.

The menu shows `49%`. If those 7 points were 22 instead (40% at the slice start, 62% now), today would be 154% of the slice and the menu would show `154% over`, while 38 points would still leave room for the last slice.

## Local storage

`~/Library/Application Support/CodexQuota/store.json`, mode `0600`. The directory is mode `0700`. Writes are atomic. `CODEX_QUOTA_DIR` overrides the directory for a local smoke launch. The override is how the build check avoids touching a real library.

Version is `1`. A newer or older version stays unreadable and the app says so. A file that is not JSON is moved to `store.json.unreadable-<time>` and the app starts empty.

```json
{
  "version": 1,
  "selectedAccountId": "uuid",
  "accounts": [
    {
      "id": "uuid",
      "label": "Personal",
      "codexHome": "/Users/dev/Library/Application Support/CodexQuota/homes/uuid",
      "createdAt": "2026-11-24T23:00:00Z"
    }
  ],
  "samples": [
    {
      "accountId": "uuid",
      "sampledAt": "2026-11-24T12:00:00Z",
      "email": "person@example.com",
      "planType": "plus",
      "limitId": "codex",
      "limitName": "Codex",
      "usedPercent": 62,
      "windowDurationMins": 10080,
      "resetsAt": "2026-11-25T17:00:00Z",
      "reached": null,
      "lifetimeTokens": 1200,
      "peakDailyTokens": 300,
      "shortUsedPercent": 25,
      "shortDurationMins": 300,
      "dailyBuckets": [{ "startDate": "2026-11-24", "tokens": 700 }]
    }
  ]
}
```

Dates in the file are ISO-8601. `resetsAt` on the wire is the Unix number described above.

History is kept for 26 weeks, capped at 4000 samples. A new sample replaces the previous one for that account when it arrives within 2 minutes and the used percent, reset, and lifetime token count are unchanged, so the checked time moves without a duplicate row.

Week stats group samples by `resetsAt`. A finished week uses its highest `usedPercent`. The open week uses the latest sample. Recorded tokens keep, for each `startDate`, the count from the latest sample that mentioned it. Lifetime and peak day come from the latest sample that had them. The average week is the mean of those per-week percents.

## UI states

Light and dark follow the system appearance. The window is the product. The status item is the glance: `49%`, `154% over`, `62% wk` when today is still unknown, `Sign in` when the selected account needs ChatGPT, and `Quota` when there is nothing to show. Clicking that figure opens or closes the window.

| State | What you see |
| --- | --- |
| No accounts | Empty window. Add Personal, then Work, or any other name. |
| Added, never read | "Sign in to read this week", plus Sign in. |
| Signing in | The browser is open. The window waits up to three minutes. |
| Signed out | Sign-in is the primary card. The last reading stays visible as a last-week line. |
| Ready | Hero is today's slice percent. Copy says whether today is ahead, on, or inside the slice, and whether the week is ahead of or behind an even split. Seven columns, reset line, room line. |
| Estimated | Same layout, with "estimated from daily tokens". |
| Partial | Hero shows a minimum (`≥14%`) and does not call the day ahead unless that minimum already is. |
| No 7-day window | The account is signed in. The banner says the 7-day allowance was not included. Token stats can still update. |
| No reset time | Weekly percent shows. Today's slice stays hidden. |
| Limit reached | One sentence for the known `rateLimitReachedType` values (rate limit, workspace credits, workspace usage). Anything else is "The provider marked this allowance as reached." |
| Short window | One line, such as "Five-hour window 25% used." |
| Refreshing | The toolbar shows progress. Buttons wait. |
| Error | One calm sentence: missing CLI, timeout, app server stopped, unreadable response, or a refused method. The last good reading stays. |
| Stale | After 15 minutes: "This reading is getting old." |
| Library problem | The previous file was kept, or this version cannot read it. |

The stats card is lifetime tokens, peak day, recorded tokens, average week, and up to eight week bars. Removing an account confirms first, and only deletes a home the app created.

## Build sequence

1. Core types for the app-server JSON, the weekly-window parser, and London pacing. Locked with the numeric example above.
2. `store.json` history, 26-week retention, and `0600` writes.
3. Stdio session: `initialize`, `initialized`, the three reads, login, logout. `swift run CodexQuotaChecks` runs that against the mock, including the exact login and initialize fields.
4. SwiftUI window and AppKit status item, including empty, signed-out, stale, and error presentation.
5. `./scripts/build-app.sh` produces `build/CodexQuota.app`, signed ad hoc, with no Dock icon.
6. On this Mac, add an account and choose Sign in. The browser completes ChatGPT login into that account's home. Refresh reads the live allowance through the user's own Codex CLI. This repo does not do that step.
