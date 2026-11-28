# Brand and showcase assets

[← Back to the project](../README.md)

## Direction

**Pace the week, one slice a day.** Codex Quota is a quiet native utility for people working with a weekly Codex allowance. Its presentation should feel useful and calm: readable numbers, a clear daily share, and enough context to decide when to keep going or ease off.

The existing incomplete-ring mark is retained. Seven equal blocks extend that idea into the hero and social preview, echoing the quota-day slices without pretending to be another application control. There are no invented testimonials, usage claims or popularity metrics.

| Role | Colour |
| --- | --- |
| Brand emerald | `#145245` |
| Cream | `#F5F0E3` |
| Deep background | `#10221D` |
| Mint highlight | `#64CE9A` |

The app keeps its own adaptive surface, ink, emerald meter and amber warning colours. Artwork uses system sans-serif typography with explicit SVG fallback fonts. Native icons remain SF Symbols. Do not embed a font file or replace the app icon merely to change a README graphic.

## Asset map

| Asset | Purpose |
| --- | --- |
| `assets/branding/mark.svg`, `mark.png` | Existing icon-only identity; PNG is 512 × 512. |
| `assets/branding/wordmark-light.svg`, `wordmark-dark.svg` | Scalable wordmarks with explicit foreground colours. |
| `assets/branding/wordmark-light.png`, `wordmark-dark.png` | Raster wordmark exports, 960 × 160. |
| `assets/branding/hero-light.png`, `hero-dark.png` | README artwork with a genuine app capture, 1600 × 900. |
| `assets/branding/hero-light.svg`, `hero-dark.svg` | Editable hero sources, with the same screenshot embedded. |
| `assets/branding/hero.png` | Light hero alias for existing links. |
| `assets/branding/badge-*.svg` | Local, factual platform/build badges; no hosted badge service. |
| `assets/branding/social-preview.png`, `social-preview.svg` | Social artwork, 1280 × 640; PNG is well below 1 MB. |
| `assets/screenshots/overview-*.png`, `usage-*.png`, `statistics-*.png` | Real app captures for pacing, token history and statistics. |
| `assets/screenshots/limits-*.png`, `credits-light.png` | Quota windows and optional credit/monthly-limit details. |
| `assets/screenshots/activity-*.png`, `conversation-*.png`, `workspace-light.png` | Real conversation, estimate and Workspace views. |
| `assets/screenshots/settings-*.png` | Actual styled checkboxes and appearance choices. |
| `assets/demos/product-tour.gif` | A 400 × 640, seven-frame, approximately 15-second tour assembled from real captures. |

Screenshot variants use `light` and `dark` suffixes. The older `panel-*`, `stats-*`, `empty-light` and `signed-out-dark` captures predate the redesign and are retained as historical files; the current showcase does not embed them. The earlier design boards are likewise not product screenshots.

## Capture safe demo material

Requirements for this documentation workflow: macOS, Swift, Python 3, and the built app bundle. These are authoring tools, not new application dependencies.

```sh
./scripts/build-app.sh
python3 scripts/readme-demo.py
```

The second command prints the paths to a temporary **Codex Quota Demo.app**, its library and its response data. Open that exact demo bundle in Finder or through computer use. It has a separate bundle identifier from the regular app and does not replace the installed app.

The helper:

1. Creates a fresh temporary directory and account homes.
2. Seeds reserved `example.com` identities, daily token records and quota windows.
3. Copies the built app without changing its production executable.
4. Wraps that copy with `CODEX_QUOTA_DIR` pointing to the temporary library and `CODEX_BIN` pointing to the offline responder.
5. Supplies sample conversations, estimates, credits and Workspace messages through the same protocol the real app consumes.

The responder contains no network client and does not launch the real Codex CLI. It never opens a login browser. Demo alerts start disabled; do not request OS notification permission or register the demo as a login item just to make a screenshot look populated. The startup checkbox is correctly disabled while this temporary app is outside Applications.

Capture the actual window at the consistent 400 × 640-point viewport. The saved captures are 800 × 1280 pixels at 2× density. Wait for refresh or details loading to finish; inspect every frame before accepting it. Show the main task rather than recording every route. Capture matching themes, and label optional backend data as examples.

Recommended tour: Overview → Usage → scroll to statistics → Limits → Conversations → Settings → Overview. The GIF is a compact sequence of genuine states, not a fabricated or interpolated UI recording. The README keeps it inside a closed `<details>` section so motion is opt-in; the static gallery covers the same features.

When finished, quit the temporary demo. Its generated library and app remain in the printed temporary directory for inspection and normal temporary-file cleanup. Never copy a signed-in home or the regular library into a public asset folder.

## Regenerate the artwork

After updating the named screenshots:

```sh
swift -framework AppKit -framework ImageIO scripts/render-brand.swift "$PWD"
```

Run that command from the repository root. It generates the PNG/SVG hero and wordmarks, icon export, factual badges, social preview and GIF. The raw screenshot files remain unchanged; the hero fits the full window at its original aspect ratio and clips only the outer rounded presentation edge.

The PNGs are used in the README for predictable rendering. SVG sources use explicit colours and embedded screenshot data; they do not depend on remotely hosted images, scripts or fonts. The GIF is about 156 KB and individual screenshot PNGs are generally below 200 KB.

## Set the GitHub social preview

Use [social-preview.png](assets/branding/social-preview.png). In the repository’s **Settings → General → Social preview**, choose **Edit → Upload an image**. Saving this file in the repository does not configure that setting.

No GitHub settings were changed by this documentation work. See [GitHub’s social preview instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

## Research and editorial choices

The following references informed the presentation strategy, not the brand artwork or product claims:

- [PostHog](https://github.com/PostHog/posthog): organise capabilities around outcomes and keep project resources accessible.
- [Astro](https://github.com/withastro/astro): clear product positioning and a direct installation path.
- [zoxide](https://github.com/ajeetdsouza/zoxide): explain the everyday benefit quickly and use concrete examples.
- [Appwrite](https://github.com/Appwrite/appwrite): group related capabilities and provide deeper documentation separately.
- [Awesome README](https://github.com/matiassingers/awesome-readme): purposeful screenshots, demonstrations and clear project entry points.
- [GitHub README guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes): relative links, useful project context and section navigation.
- [GitHub advanced formatting](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting): supported tables and collapsed sections.

The main README intentionally keeps the complete provider-field inventory in [FEATURES.md](FEATURES.md), installation mechanics in [GETTING-STARTED.md](GETTING-STARTED.md), and the mathematics in [quota-app-plan.md](quota-app-plan.md). Contribution guidance lives in [CONTRIBUTING.md](../CONTRIBUTING.md). No new license, download service, community destination or release was invented.

## Verification record

The documentation was checked against the current source and real app. The public repository’s release list was read on 28 November 2026 and returned no published releases. The bundle metadata reports version 0.1.0 and macOS 14 minimum.

| Check | Result |
| --- | --- |
| Genuine, meaningful app captures | Passed: sample accounts, both themes, budgets, token chart, statistics, quota windows, credits, conversations, estimates, Workspace and Settings. |
| Isolation | Passed: separate temporary library, bundle identity and offline backend. Regular account data and OS settings were not changed. |
| Artwork | Passed: inspected light/dark heroes and social image; corrected the dark hero’s outer corner masking. No screenshot UI was invented or painted over. |
| Animation | Passed: seven genuine frames, 400 × 640, roughly 15 seconds, small file size; collapsed by default with static alternatives. |
| GitHub Markdown | Passed: rendered through GitHub’s Markdown API in GFM mode, preserving picture sources, tables and details. |
| Browser layout | Passed: locally inspected GitHub-rendered HTML with GitHub-style CSS at 1280 × 1000 and 390 × 844, light/dark. No page-level horizontal overflow or broken images; anchor navigation and the tour disclosure were checked. |
| Local files and anchors | Checked with the final documentation validation. |
| Publication | Not performed: no commit, push, release or social-preview upload. |

The GitHub API returns the rendered document body without the surrounding repository page. The local preview adds heading IDs and a GitHub-style article container to exercise navigation and layout. This verifies the rendered Markdown and assets, not an unpublished change on the live repository page. See [GitHub’s Markdown API](https://docs.github.com/en/rest/markdown/markdown).

Native demo captures and the browser preview were visually reviewed after rendering. The native app’s startup approval and notification delivery were not triggered for the showcase. The original application implementation’s verification is recorded separately in the local design QA report; this work does not claim new runtime behaviour or CI coverage.
