# iOS replica implementation specification

## 1. Product definition

Build a private, offline iPhone recreation of **Minesweeper — The Clean One** by Dustland Design. The fidelity baseline is Android package `ee.dustland.android.minesweeper`, version `1.21.3` (version code `95`), as listed on Google Play on 2026-07-30. This repository is a personal study/recreation; it is not affiliated with or endorsed by Dustland Design.

The first release is:

- iPhone only, portrait only, iOS 17 or newer.
- English only.
- Bundle identifier `com.xylo.MinesweeperCleanReplica`.
- Completely offline after installation.
- Free of ads, analytics, consent SDKs, account systems, in-app purchases, review prompts, and external promotion.
- Distributed by private Xcode installation, not an app store.

The source screenshots are catalogued in [references/README.md](references/README.md), and the audited color data is in [references/THEME_CATALOG.md](references/THEME_CATALOG.md). Static screenshots establish layout and appearance. A side-by-side 60 fps Android screen recording is the final authority where animation or an interaction is not visible in the screenshots.

## 2. User experience

### App flow

1. Launch into the home screen with the current theme already applied.
2. Swipe or tap arrows to choose one of six difficulties.
3. Start a new game, or resume the saved game for that difficulty when one exists.
4. If New Game would replace unfinished progress, show the original confirmation message and Cancel/New game actions.
5. Play using tap/long-press and the optional dig/flag toggle. Pan and pinch operate on the board without moving the overlay controls.
6. A loss reveals the mines and the error state. A win records the result and presents the five best results for the difficulty with the new result highlighted.
7. Post-game controls occupy the lower quarter: Start new game plus the same difficulty selector.
8. The home footer opens Settings, Themes, Times, and About.

### Home screen

- Center a square mine/gear mark above the controls. It is 40% of the bounded content width and keeps a 1:1 ratio.
- Bound the centered content region to 460 pt wide and 580 pt high. On smaller phones it fills the available safe-area size.
- Place the logo 40 pt above the difficulty selector. The selector is 40 pt high with 50 pt horizontal margins and 10/5 pt horizontal/vertical internal padding.
- Put New Game 20 pt below the selector and Resume 20 pt below New Game. Each is 40 pt high, uses a 1 pt outline, and has 50 pt horizontal margins. Hide Resume when the selected difficulty has no resumable game.
- Pin a 40 pt footer 15 pt above the safe-area bottom. Give the four icon actions equal widths with 10 pt side margins. Order: Settings, Themes (shopping-cart position in the Android reference), Times, About.
- Keep the Android visual proportions but extend every interactive hit region invisibly to at least 44×44 pt.

### Game screen

- Draw the board edge to edge behind the overlays. The board, covered-cell shape, clue digits, flag, mine, and optional grid lines must all use the selected theme.
- Center the header in the safe-area top. Its reserved space is 46 pt high with a 10 pt outer top margin. The mine icon/count sits above a 12 pt elapsed-time label.
- Format time as `M:SS` below one hour and `H:MM:SS` thereafter. The mine counter is `mineCount - flagsPlaced`; it may become negative to match unrestricted flagging.
- Place the floating action toggle 20 pt above the safe-area bottom. It consists of two 46×46 pt icon buttons, 6 pt vertical/outer padding, 8 pt between buttons, 1 pt outline, and a 30 pt capsule radius. The selected half uses the theme highlight state.
- The palette action expands into a horizontal outlined capsule of circular theme swatches as shown in `user-reference-theme-strip.png`. Swatches are 28 pt visual circles in 40 pt hit regions; the current swatch gets a high-contrast ring. The capsule scrolls horizontally, keeps the palette button anchored at the trailing edge, and collapses after a selection or outside tap.
- Changing theme during play animates all visible colors and leaves the board, elapsed time, viewport, action mode, and game phase untouched.
- At game end, replace the action toggle with controls in the lower 25% of the screen (minimum height 140 pt): a 40 pt Start new game button and a 40 pt difficulty selector separated by 10 pt.

### Board gestures and actions

- Start with an automatically fitted board. The entire Easy board should fit when practical; larger boards use the largest scale that keeps cells legible while centering the board.
- Pinch from 0.65× to 3.5×, preserving the content point under the pinch centroid. Double tap is not a zoom gesture because it could conflict with play.
- Pan with bounded rubber-band overscroll equal to at most 20% of the viewport. Settle to valid bounds when the gesture ends.
- A touch is a cell action only when movement stays under 8 pt and scale change stays under 2%. Hit-test after applying the exact inverse viewport transform.
- Tap invokes the selected primary action. Long press invokes its secondary action. With Dig selected: tap digs and long press flags. With Flag selected: tap flags and long press digs.
- Default long-press recognition is 300 ms. Cancel it on pan, pinch, app deactivation, or if the finger leaves the original cell.
- A successful secondary action emits one haptic. Invalid/no-op actions do not.

### Game rules

- Defer finalized mine placement until the first dig. Exclude the first cell and its in-bounds neighbors, so the opening is always a zero region.
- Reveal zero regions with an iterative breadth-first flood fill. Reveal their numbered boundary but never automatically reveal a flagged cell.
- Digging a mine loses immediately. Reveal every mine, distinguish the detonated mine, and show incorrect flags.
- Win when every non-mine cell is revealed. Flags are not required for win detection.
- Easy digging (chording): tapping a revealed clue in Dig mode reveals every adjacent unflagged closed cell when adjacent flags equal the clue.
- Easy flagging: tapping a revealed clue in Flag mode flags every adjacent closed cell when the number of closed neighbors equals the clue. Never remove existing flags in this operation.
- Generator output must be solvable from the protected first opening without guessing. Validate using clue saturation, subset deductions, constraint-component enumeration, and probability-0/1 deductions. Reject and regenerate a board if the verifier stops with unresolved cells.
- Generate asynchronously. Enter the screen immediately in `readyForFirstTap`; after the opening tap, show a nonblocking board-local progress state only if validation exceeds 100 ms. Target first reveal under 150 ms using a persisted queue of random candidate streams per difficulty.

### Difficulty presets

The constructor order in the Android reference is columns, rows, mines. Use these exact values and stable persistence identifiers:

| Identifier | Display name | Columns | Rows | Mines | Cells |
|---|---|---:|---:|---:|---:|
| `beginner` | Beginner | 12 | 22 | 12 | 264 |
| `easy` | Easy | 7 | 10 | 10 | 70 |
| `medium` | Medium | 12 | 22 | 40 | 264 |
| `hard` | Hard | 18 | 32 | 100 | 576 |
| `huge` | Huge | 27 | 48 | 220 | 1,296 |
| `extreme` | Extreme | 18 | 32 | 150 | 576 |

### Settings

Use a vertically scrolling titled screen. Each item has a title, optional description, and right-aligned switch/control. Preserve the 75 pt separation evident in the Android layout while allowing text to grow for accessibility.

| Setting | Type/range | Default | Dependency and behavior |
|---|---|---|---|
| Cell borders | Boolean | Off | Adds the theme separator to every cell edge. |
| Show action toggle | Boolean | On | Forced on and disabled while Long press is off. Restore the user's prior value when Long press returns. |
| Default action | Dig / Flag | Dig | Sets the initial selected action for every newly opened game. |
| Long press | Boolean | On | Enables the secondary action. |
| Long-press delay | 100–500 ms, 25 ms step | 300 ms | Enabled only while Long press is on. |
| Easy digging | Boolean | On | Enables Dig-mode chording. |
| Easy flagging | Boolean | Off | Enables Flag-mode automatic neighbor flagging. |
| Animation speed | 0–150%, 5% step | 100% | Multiplies durations by `100 / value`; 0 disables nonessential animation. |
| Vibration | Boolean | On | Master haptic switch. |
| Vibration intensity | 5–200 ms, 5 ms step | 50 ms | Map duration to the nearest suitable `UIImpactFeedbackGenerator` intensity; iOS cannot guarantee literal motor duration. |

### Themes

- Expose the 30 fixed palettes and two Material You variants listed in [references/THEME_CATALOG.md](references/THEME_CATALOG.md). Nothing is paywalled.
- Preserve source ordering within the standard, AMOLED, and Retro groups. Put `Material You` first in the standard group and `Material You Amoled` first in AMOLED.
- On iOS, Material You is deterministic rather than wallpaper-derived. Seed it from the user's iOS accent color when available to the app; otherwise use `#6750A4`. Generate a Material 3 tonal palette and persist the resolved sRGB values, so the board never changes unexpectedly between launches.
- `Material You Amoled` uses the same generated foreground/accent roles with true-black root and revealed surfaces.
- Color transitions are sRGB interpolations between complete palettes. Do not crossfade screenshots or temporarily place both themes in the hierarchy.

### Times and dialogs

- Store successful results only. A result is difficulty, elapsed milliseconds, completion date, and a stable UUID.
- The Times screen follows the home difficulty selector and lists results fastest first; date ties sort oldest first. Show `No times yet.` when empty.
- Show at most five best times in the win dialog. Highlight the just-completed result even if an identical time exists. Use a rotating local heading from a small deterministic congratulation list; no network content.
- A swipe-to-delete or delete button opens `Are you sure you want to delete this time?` with Cancel/Delete.
- Use the source date presentation `d MMM yyyy` under the English locale. Display elapsed time to seconds in lists and retain milliseconds internally for stable ordering.
- Dialogs are centered, compact, themed cards with no blurred material. Buttons use the same outlined style as the home screen.

### About

Show app name, replica version, Rubik and Material icon attributions, and this notice:

> Private, non-commercial recreation inspired by “Minesweeper — The Clean One.” Not affiliated with or endorsed by Dustland Design. Original product name and visual references belong to their respective owner.

Do not copy the original developer copyright statement as though it applied to this project.

## 3. Visual system

### Typography

- Bundle the Rubik family and register it through `UIAppFonts`. Required faces: Light 300, Regular 400, Medium 500, Bold 700, with italic companions only if an audited screen uses them.
- Body and controls use Rubik Regular. Headings, selected difficulty, counters, and clue digits use Rubik Medium. Use Rubik Light for long descriptions where the reference does.
- Baseline sizes: body/button 14 pt, caption/timer 12 pt, screen title 24 pt, home difficulty 14 pt, clue digit at 42% of cell size clamped to 11–22 pt.
- Use tabular figures for time and counters. Do not substitute San Francisco except for text that Rubik cannot render.

### Geometry tokens

| Token | Value |
|---|---:|
| `contentMaxWidth` | 460 pt |
| `homeContentMaxHeight` | 580 pt |
| `controlHeight` | 40 pt |
| `minimumHitTarget` | 44 pt |
| `hairline` | 1 physical pixel, aligned to pixel grid |
| `buttonCornerRadius` | 20 pt |
| `toggleCornerRadius` | 30 pt |
| `screenHorizontalMargin` | 30 pt |
| `homeControlHorizontalMargin` | 50 pt |
| `footerBottomMargin` | 15 pt |
| `gameOverlayBottomMargin` | 20 pt |
| `dialogMaxWidth` | min(340 pt, viewport − 40 pt) |
| `cellCornerRadius` | 10% of rendered cell edge, 0 when borders are on |

Treat 1 Android dp as 1 iOS point at the baseline viewport. Respect safe areas rather than drawing Android status/navigation bars. Snapshot comparison crops those platform regions before calculating fidelity.

### Color tokens

Every palette supplies these roles; their exact Android values are catalogued separately:

| Role | Meaning |
|---|---|
| `foregroundPrimary` | Main text, arrows, normal icons, clue fallback. |
| `foregroundSecondary` | Secondary labels and subdued counters. |
| `surfaceRoot` | Root/menu/revealed-board base. |
| `symbolPrimary` | Primary mine/flag internal fill. |
| `symbolSecondary` | Secondary mine/flag internal fill. |
| `separator` | Cell borders, inactive outlines, subtle rules. |
| `cellCovered` | Closed, actionable cell. |
| `cellFlagged` | Background for a flagged closed cell. |
| `cellDetonated` | Mine hit/error background. |
| `cellPressed` | Press and reveal-transition fill. |
| `cellRevealed` | Open-cell fill/separator support. |
| `canvas` | Board and system-underlay canvas. |
| `clue1`…`clue8` | Digit colors. |

Android AMOLED palettes encode some black roles as transparent `#00000000` over a black window. Make the iOS root layer opaque black, then preserve clear only where compositing is intentional; this prevents accidental transparency over UIKit defaults.

### Icons

- Recreate mine, flag, gear/logo, settings, palette/cart, list, info, and navigation arrows as local vector paths. Use 24×24 Material-icon view boxes where the reference does.
- Use round line caps/joins and tint from semantic tokens. Never rasterize an icon at a single device scale.
- Include the Material Design Icons Apache 2.0 notice from `Licenses/` in the in-app acknowledgements.

## 4. Motion and feedback

Use `MotionTokens` so calibration changes never leak into view code. Initial values are implementation baselines and must be replaced by frame-counted Android measurements when recordings are captured.

| Motion | 100% duration | Curve/behavior |
|---|---:|---|
| Screen enter/exit | 300 ms | cubic ease-in-out, 12 pt translation + fade |
| Dialog present/dismiss | 220 / 180 ms | ease-out / ease-in, 0.96→1 scale |
| Palette expand/collapse | 240 / 180 ms | ease-in-out; trailing palette button remains anchored |
| Full theme transition | 450 ms | linear-light sRGB interpolation |
| Action selection | 180 ms | ease-in-out fill/icon interpolation |
| Flag placement | 180 ms | 0.78→1 spring, no overshoot above 1.05 |
| Single reveal | 180 ms | ease-out fill/scale |
| Flood reveal stagger | 12 ms per BFS ring | cap total cascade at 420 ms |
| Loss reveal | 420 ms | detonated cell first, remaining mines by distance |
| Win settle | 600 ms | final board settle before results dialog |
| Overscroll settle | 260 ms | critically damped spring |

- Apply animation speed to nonessential durations. At 0%, update immediately and retain only system-required state transitions.
- When Reduce Motion is enabled, behave like 0% for board cascades, parallax, scale, and screen translations regardless of the in-app value; retain short opacity changes up to 100 ms.
- Haptic events: secondary cell action, action-mode change, win, and mine hit. Use light, selection, success, and error feedback respectively. Honor the Vibration setting and avoid repeated feedback during flood fill.

## 5. Architecture and data

### Runtime structure

- SwiftUI owns navigation, home, settings, themes, times, dialogs, and overlay layout.
- A custom `UIView` embedded by `UIViewRepresentable` owns board drawing, gesture recognition, viewport transforms, and hit-testing. Render with Core Graphics using cached vector paths and a single invalidation per display frame.
- A `@MainActor GameViewModel` translates pure engine state into immutable render snapshots. Mine generation/verification runs in a cancellation-aware task off the main actor.
- No third-party runtime packages.

Required public model boundaries:

```swift
enum Difficulty: String, Codable, CaseIterable
struct BoardConfiguration: Hashable, Codable
enum CellVisibility: UInt8, Codable { case closed, revealed, flagged }
enum GamePhase: Codable { case readyForFirstTap, generating, playing, won, lost }
enum ActionMode: String, Codable { case dig, flag }
struct GameSettings: Codable, Equatable
struct ThemePalette: Codable, Equatable, Identifiable
struct GameSnapshot: Codable
struct TimeRecord: Codable, Identifiable

protocol BoardGenerating: Sendable
protocol GamePersisting: Sendable
protocol ThemeProviding: Sendable
protocol HapticsProviding
```

The engine API accepts row/column coordinates, never view points. It owns mine placement, adjacency, reveal, flag, chord, phase, counters, and timer state; no UIKit or SwiftUI types enter the engine target.

### Persistence

- `UserDefaults`: settings, selected theme ID, selected difficulty, per-difficulty viewport preference, and schema-independent UI preferences.
- `Application Support/Saves/v1/<difficulty>.json`: one atomic Codable game snapshot per difficulty.
- `Application Support/Times/v1/times.json`: all time records.
- `Application Support/BoardQueue/v1/<difficulty>.json`: candidate generator streams only; never treat them as a game in progress.
- Write through a sibling temporary file, `fsync`, then replace. Decode each difficulty separately so one corrupt save cannot remove the others.
- Every document includes `schemaVersion`, `createdAt`, and `updatedAt`. Unknown future versions are preserved but not loaded. Corrupt files are moved to a timestamped `.invalid` sibling before a clean replacement.
- Save after every successful cell action, on scene background, and on interruption. Do not count background time: persist elapsed active milliseconds and restart the monotonic clock only when an active game returns to foreground.

## 6. Accessibility and device behavior

- Add VoiceOver labels and values to every control. A board cell announces row, column, visibility, clue when revealed, and flag/mine state after game end. Expose custom Dig and Flag accessibility actions.
- Reading order is header, board, floating controls. The board uses an accessibility container with only on-screen cells materialized to avoid a 1,296-element startup cost.
- Support Dynamic Type through `accessibility3` on non-board screens; allow settings rows and dialogs to grow vertically. Clue sizing follows zoom instead of Dynamic Type so board geometry remains valid.
- Never encode cell meaning by color alone: flag and mine vectors remain visible, and digits are present for clues. Selected controls have shape/ring changes.
- Meet a 4.5:1 text contrast target where changing the reference does not destroy fidelity. If an audited theme falls below it, retain the reference color visually and add an optional `Increase Contrast` adaptation using system accessibility state.
- Keep all state when interrupted by a call, screen lock, memory warning, or scene transition. Cancel touches cleanly and pause the timer.

## 7. Validation and acceptance

### Automated tests

- Unit tests: adjacency at corners/edges/interior; exact mine counts; first-cell and neighbor exclusion; iterative flood fill; flag toggling; both chord actions; negative remaining-mine count; win/loss; tap/long-press routing; timer pause/resume; every settings dependency.
- Property tests: at least 250 generated boards per difficulty in normal CI and 1,000 per difficulty in the extended suite. Every board must match its dimensions/mines, protect the opening, and be fully solved by the deterministic verifier.
- Persistence tests: all six independent saves, atomic replacement failure, background timing, corrupt-file isolation, missing fields, v1 migration scaffolding, times ordering/ties/deletion, and palette persistence.
- UI tests: home navigation; difficulty swipe/arrows; replacement warning; new/resume; win/loss; palette expansion and in-game theme change; action toggle; long press; pan/pinch boundaries; settings dependencies; empty/populated Times; delete confirmation; About.

### Snapshot matrix

Capture at 375×667, 393×852, and 430×932 pt. Test home, active game, expanded palette, Settings, post-game win, post-game loss, Times empty/populated, and About. Include Alpine, Diletto, Amoled, Retro, and Material You.

For comparison, crop Android-only system bars and align the content viewport. Acceptance thresholds:

- Geometry: edges/baselines within 2 pt of annotated references.
- Color: mean ΔE2000 below 3 for flat semantic regions.
- Typography: Rubik face/weight exact; baseline within 1 pt and line wrap identical at the baseline viewport.
- Static pixel difference: below 1.5% outside text antialiasing masks.
- Motion: each measured transition within one frame at 60 fps; no intermediate flash of a stale theme.
- Accessibility: no unlabeled actionable element; all visual hit targets reach 44×44 pt.

### Performance gates

- p95 board render below 8.3 ms on a 120 Hz device and 16.7 ms on a 60 Hz device.
- No dropped gesture events while pinching/panning the Huge board.
- First screen from warm launch below 300 ms; New Game screen presentation below 150 ms; first verified reveal normally below 150 ms.
- Peak resident memory remains stable across 20 Huge-board restarts, with no growth from cached paths or accessibility elements.

### Final manual parity pass

Run the Android reference and iOS build side by side. Record the same scripted route at 60 fps: launch, change difficulty, start, first reveal, flag, chord, zoom/pan, expand theme strip, change theme, lose, restart, win, inspect times, modify each setting, and open About. Attach differences to the issue tracker with frame number, device/viewport, expected reference, actual iOS capture, and assigned token/component. The replica is complete only when every difference either meets the thresholds above or is documented as an unavoidable iOS platform adaptation.
