# Visual reference manifest

This folder contains internal design references for the private iOS recreation. These images are documentation inputs only: do not add them to the shipped app target or use the promotional artwork as app-store marketing.

## Sources

The four home-footer silhouettes are the 24 dp filled Material Icons
(`settings`, `shopping_cart`, `list`, and `info`) from Google's
`google/material-design-icons` repository. They are bundled as template SVGs
in `MinesweeperApp/Resources/Assets.xcassets` and covered by the existing
Apache 2.0 attribution in `Licenses/Material-Design-Icons-Apache-2.0.txt`.

- **Official listing:** [Minesweeper — The Clean One on Google Play](https://play.google.com/store/apps/details?id=ee.dustland.android.minesweeper&hl=en), package `ee.dustland.android.minesweeper`. Inspected 2026-07-30; the listing reported version `1.21.3` and an update date of 2026-06-19.
- **Package cross-check:** [APKCombo package page](https://apkcombo.com/minesweeper-the-clean-one/ee.dustland.android.minesweeper/). A locally inspected XAPK reported version name `1.21.3`, version code `95`, minimum SDK `32`, and target SDK `36`. APK, XAPK, DEX, and decompiled files are deliberately excluded from this repository.
- **User reference:** the screenshot supplied in the request, preserved verbatim as `images/user-reference-theme-strip.png`.
- **Typography:** Rubik font files found in the reference package and cross-checked against [Google Fonts Rubik](https://github.com/google/fonts/tree/main/ofl/rubik). The OFL is in `../../Licenses/Rubik-OFL-1.1.txt`.
- **Icons:** the reference uses Material-style 24 dp symbols. Recreated local vectors should follow the [Material Design Icons source](https://github.com/google/material-design-icons) and its Apache 2.0 license in `../../Licenses/Material-Design-Icons-Apache-2.0.txt`.

The exact theme catalog was recovered from the v1.21.3 theme definitions and converted from signed Android ARGB integers to `#AARRGGBB`; see [THEME_CATALOG.md](THEME_CATALOG.md). Layout measurements in the implementation specification were cross-checked against the package's XML layouts. This reverse-engineering evidence is recorded as facts, not copied application code.

## Files

| File | Dimensions | SHA-256 | What it establishes |
|---|---:|---|---|
| `images/user-reference-theme-strip.png` | 567×869 | `55b7a954e9fe3a980767535343d52c62c095e891c93b4282d2862659b2a1e97b` | In-game horizontal swatch strip, bright pink covered cells, bottom action capsule, board typography. |
| `images/google-play-01-home.png` | 1600×2844 | `bc8da4d9f092ec9169c10528af993f5423ac836227e335117ed69225a98ad97c` | Home hierarchy, centered logo, difficulty selector, New Game, footer icons. |
| `images/google-play-02-clean-play.png` | 1600×2844 | `2d5badfe54ad0d66f747de86341ef41d2ad3f3342cb16d0826ca78c0fe3e0be6` | Active board, revealed/covered relationship, flags, counter and palette location. |
| `images/google-play-03-themes.png` | 1600×2844 | `92944b13cdd2168ffe094563b050e07297cb1a89b210469385c340cc864eee51` | Theme strip expanded over an active board; AMOLED/pink contrast. |
| `images/google-play-04-post-game.png` | 1600×2844 | `a29f736b1eb2b6526d65cf47009c8a70a2f6429edf33c3548de248014eb6dd89` | Completed-board treatment and lower post-game New Game/difficulty controls. |
| `images/google-play-05-settings.png` | 1600×2844 | `db98a35ffc96713b54ab64d0028566bd24b87aabb4cb010c79ae1e74e5b2941f` | Titled settings layout, switch/slider styling, description typography. |
| `images/google-play-06-times.png` | 1600×2844 | `76a44fd70a5f05246a43d9ddd1597741541e8c5487b4c7bc7cbdb15c94642cc9` | Times/result dialog, highlight band, date/time formatting. |
| `images/google-play-contact-sheet.png` | 1020×1178 | `e9cbdac658fcf1fd8e0995270396f775780993f863296ca8d863949d2a965606` | Convenience overview of all six promotional images. |

## Screenshot captions

1. “Pretty puzzling.” — home screen.
2. “Clean looks & feel.” — blue active-game example.
3. “Gorgeous themes.” — pink AMOLED board and swatch strip.
4. “Smooth gameplay.” — orange completed game.
5. “Customization.” — light Settings screen.
6. “Compare your times.” — light leaderboard/result dialog.

The promotional screenshots use perspective transforms and include Android system chrome. Never measure final iOS x/y coordinates directly from the tilted phone plane. Use them for visual hierarchy and palette validation, and use the flat XML-derived point tokens in `../IOS_REPLICA_PLAN.md` for implementation geometry.

## Reproducing the Google Play files

Run `./fetch_google_play_references.sh /path/to/output`. The script downloads the six current originals at 1600×2844 and verifies their pinned hashes. If Google replaces an image, hash validation intentionally fails; inspect the listing and update both the image and manifest together.

The user-supplied screenshot cannot be reproduced from a public URL and is therefore not touched by the fetch script.
