# Contributing to Codex Quota

Thanks for taking a look. Start with the [README](README.md) for the product and the [feature guide](docs/FEATURES.md) for the current behaviour.

## Report a bug or suggest a change

Use the [issue tracker](https://github.com/lcherone/CodexQuota/issues). Include:

- What you expected and what happened.
- macOS, Swift and Codex CLI versions, where relevant.
- The steps that reproduce it and whether it happens after a fresh launch.
- A screenshot or error message with account identities, directories and conversation content removed.

For a substantial feature or visual change, discuss the scope in an issue first. Never post sign-in tokens, API keys or a real Codex home. If a report requires sensitive details, ask the maintainer for an appropriate private channel before sharing them; this repository does not currently publish a dedicated security contact.

## Run the app and checks

Requirements: macOS 14+, Swift 6, and the separately installed Codex CLI for live use.

```sh
swift build --product CodexQuota
swift run CodexQuota
swift run CodexQuotaChecks
```

The check executable uses an offline stand-in and controlled model dependencies. It does not contact OpenAI, open sign-in browsers, deliver notifications or read existing signed-in homes. The repository has an executable check suite rather than an XCTest bundle; no CI coverage percentage is claimed.

For a bundled build, installation, updates and CLI discovery, use [Build and run](docs/GETTING-STARTED.md).

## Where things live

| Path | Responsibility |
| --- | --- |
| `Sources/CodexQuota/` | SwiftUI/AppKit panel, Settings, menu bar and macOS integration. |
| `Sources/CodexQuotaModel/` | Account workflows and observable application state. |
| `Sources/CodexQuotaCore/` | Provider protocol, parsing, pacing, formatting and local history. |
| `Sources/CodexQuotaChecks/` | Mock-backed checks and isolated model workflows. |
| `Tests/Fixtures/` | Offline Codex app-server stand-in used by the checks. |
| `scripts/` | Build/install helpers and documentation asset tooling. |

Keep behavioural changes focused. Extend the relevant checks where a changed behaviour needs protection, and report the exact checks run. Do not weaken the suite to make a change pass.

## UI changes

Inspect the current app before changing it. Verify the affected controls in light and dark appearance, preserve missing/partial-data states, and include genuine screenshots for review. Keep Settings, keyboard focus, Escape cancellation and scrolling usable.

Use [the isolated showcase workflow](docs/SHOWCASE.md#capture-safe-demo-material) for documentation or PR screenshots. It gives the real app sample data without using the normal library. Do not replace real screenshots with generated UI.

## Before proposing a pull request

Keep the diff scoped and preserve unrelated work. Explain the user-visible change, why it helps, how it was checked and what remains unverified. Include the relevant test results and screenshots rather than describing everything as “fully tested”.

The repository has no license file yet. This guide does not introduce one or establish reuse or redistribution terms.
