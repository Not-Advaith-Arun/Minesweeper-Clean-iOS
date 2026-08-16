# Minesweeper — private iOS recreation

An offline, ad-free iPhone and iPad portrait recreation of **Minesweeper — The Clean One** for personal use. It contains a pure Swift game engine, verified no-guess generation, per-difficulty autosaves and times, the full settings surface, 33 local themes, and a custom zoomable UIKit board renderer inside a SwiftUI application.

No backend is required. Saves, settings, themes, and the personal leaderboard are stored locally on the device; there are no accounts, API keys, hosted databases, or network calls.

Extreme uses a provided centre starting cell so its next board can be prepared off the interaction path. Every Extreme layout is independently verified no-guess, keeps a 350+ 3BV floor, and requires advanced subset or exact-constraint deductions. Layouts start as uniformly random mine placements and are repaired into solvable boards by solver-directed perturbation, so adjacent mines, runs, and 2×2 groups occur at their natural rates; a spectral and long-lag distribution check rejects anything carrying a repeated lattice.

## Requirements

- macOS with Xcode 26 or newer
- iOS 17 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A free or paid Apple developer account for device signing

## Run on an iPhone or iPad

1. Run `make generate`.
2. Open `Minesweeper.xcodeproj`.
3. Select the **Minesweeper** target, choose your signing team, and keep the private bundle identifier or replace it with your own unique identifier.
4. Connect your iPhone or iPad, select it as the run destination, and press Run.

Free Apple IDs normally require the app to be re-signed periodically. This repository contains no App Store, advertising, analytics, or purchase integration.

### Build on GitHub and install with Sideloadly

The private repository includes an `iOS CI and unsigned IPA` workflow for people developing from Linux or Windows. Every push to `main` runs the portable engine suite and the native unit/UI journeys on an iPhone 17 Pro Max simulator, then builds an unsigned device IPA without uploading any Apple ID, signing certificate, or provisioning profile. Test results and raw Xcode logs are retained separately for diagnosing failures.

1. Open the repository's **Actions** tab and select the newest successful `iOS CI and unsigned IPA` run.
2. Download the private `Minesweeper-unsigned-ipa` artifact and extract it.
3. Optionally verify `Minesweeper-unsigned.ipa` against the included SHA-256 file.
4. Connect and trust the iPhone or iPad on the Windows or macOS computer where Sideloadly is configured.
5. Enable Developer Mode on the device, drag the IPA into Sideloadly, select the device, and start the install.

The unsigned IPA artifact is retained for 14 days and remains visible only to accounts with access to the private repository. Sideloadly performs signing locally; GitHub never receives the Apple ID used for installation.

## Validation

Run the platform-independent engine suite with:

```sh
swift test
```

Run the 1,500-board no-guess stress gate (250 seeds for every difficulty) with:

```sh
make test-extended
```

On a Mac with an installed iPhone 16 Pro simulator, run the engine tests and the five feature journeys with:

```sh
make test-ios
```

Override the destination when needed, for example:

```sh
make test-ios SIMULATOR='platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'
```

Apple ships UIKit, Xcode, and the iOS Simulator only for macOS. On Linux, `make validate` executes the complete portable suite and parses every app/UI-test Swift source, but it cannot boot the app. See [the implementation and visual specification](docs/IOS_REPLICA_PLAN.md) for acceptance criteria and reference provenance.

## Status and provenance

The design target is Android v1.21.3 (June 2026). The project is a private clean-room recreation and is not affiliated with or endorsed by Dustland Design. Reference images remain the property of their respective owners and are retained only for personal design comparison.
