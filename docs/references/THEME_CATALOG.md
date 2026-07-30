# Theme catalog and exact color tokens

The Android v1.21.3 reference contains 30 fixed palettes plus two Android 12 dynamic-color entries. Values below are direct conversions of its signed 32-bit ARGB integers to `#AARRGGBB`.

## Token order

Each fixed palette has 20 color roles in this order:

`foregroundPrimary`, `foregroundSecondary`, `surfaceRoot`, `symbolPrimary`, `symbolSecondary`, `separator`, `cellCovered`, `cellFlagged`, `cellDetonated`, `cellPressed`, `cellRevealed`, `canvas`, then `clue1` through `clue8`.

The semantic names describe observed use in the Android renderer. Retain the ordered raw values in fixtures so visual regression tests can catch an accidental role mapping change.

## Standard themes

| Theme | Primary / secondary | Root / symbols (2) / separator | Covered / flagged / detonated / pressed / revealed / canvas | Clues 1–8 |
|---|---|---|---|---|
| Alpine | `FFBCD0E1` / `FF9FB7CD` | `FF0D151D` / `FF0D151D` / `FF0F171D` / `FF3B5368` | `FF41A3CD` / `FF808F9E` / `FFCF3F3F` / `FF55C2F0` / `FF384751` / `FF0D151D` | `FFBCD0E1` ×8 |
| Diletto | `FF7C7C7C` / `FF979797` | `FFF9F9F9` / `FF969696` / `FFA43434` / `FFD5D5D5` | `FFB8B19E` / `FFE1E1E1` / `FFD86E6E` / `FFAB9F73` / `FFD9D9D9` / `FFF9F9F9` | `FF7C7C7C` ×8 |
| Aurum | `FFD6D6D6` / `FFC6C6C6` | `FF191919` / `FF191919` / `FF111111` / `FF57554C` | `FF988D62` / `FF636363` / `FFD74157` / `FF9B915D` / `FF3F3D38` / `FF191919` | `FFD6D6D6` ×8 |
| Kawa | `FFC9D5C9` / `FFB6C1B6` | `FF090909` / `FF111111` / `FF090909` / `FF2A352A` | `FF349734` / `FF566056` / `FFB31E1E` / `FF2FA12F` / `FF2C362C` / `FF111111` | `FFC9D5C9` ×8 |
| Monokai | `FFC7C392` / `FF9F9C77` | `FF1B1B1B` / `FF1B1B1B` / `FF1B1B1B` / `FF644C63` | `FFB53462` / `FF61624F` / `FFD13434` / `FFF92571` / `FF582F56` / `FF1B1B1B` | `FFC7C392` ×8 |
| Laurel | `FFDCDCDC` / `FFC9C9C9` | `FF373B35` / `FF373B35` / `FF373B35` / `FF595F53` | `FFAFC99D` / `FF646862` / `FFCF7F7F` / `FFAFC99D` / `FF586053` / `FF383C36` | `FFDCDCDC` ×8 |
| Rossa | `FF797979` / `FF8F8F8F` | `FFFFFFFF` / `FFAFAFAF` / `FFA20F0F` / `FFE8E3E3` | `FFD7999E` / `FFE2E2E2` / `FFF26D6D` / `FFBB555D` / `FFE3E3E3` / `FFFFFFFF` | `FF797979` ×8 |
| Nennau | `FF7B7B7B` / `FF898989` | `FFF9F9F9` / `FFA1A1A1` / `FF963D3D` / `FFD5D5D5` | `FF7FABC7` / `FFE2E2E2` / `FFD86E6E` / `FF699FBF` / `FFD9D9D9` / `FFF9F9F9` | `FF7B7B7B` ×8 |
| Ambra | `FFE9E9E9` / `FFCFCFCF` | `FF333333` / `FF333333` / `FF431A0D` / `FF757474` | `FFD87F37` / `FF666666` / `FFB6350D` / `FFE7791E` / `FF606060` / `FF333333` | `FFE9E9E9` ×8 |

## AMOLED themes

`00000000` means transparent black in the Android table. The iOS renderer places those roles over an opaque `#000000` root.

| Theme | Primary / secondary | Root / symbols (2) / separator | Covered / flagged / detonated / pressed / revealed / canvas | Clues 1–8 |
|---|---|---|---|---|
| Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FFD1D1D1` / `FF595959` / `FFC00B0B` / `FFFFFFFF` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Orange Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FFCA742D` / `FF595959` / `FFC00B0B` / `FFF5750B` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Yellow Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FFCFD162` / `FF595959` / `FFC00B0B` / `FFF7F70B` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Red Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FF983F3F` / `FF595959` / `FFF40D0D` / `FFE31D1D` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Purple Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FF8A4FA1` / `FF595959` / `FFC00B0B` / `FFB73DE3` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Pink Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FFC569B0` / `FF595959` / `FFC00B0B` / `FFF917C7` / `FF545454` / `00000000` | `FFF5F5F5` ×8 |
| Blue Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FF3285B1` / `FF595959` / `FFC00B0B` / `FF2563F1` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Cyan Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FF5EB3BF` / `FF595959` / `FFC00B0B` / `FF0BF3F3` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Green Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FF45A645` / `FF595959` / `FFC00B0B` / `FF11F311` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |
| Lime Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `00000000` / `00000000` / `FF5A5A5A` | `FF9EC45A` / `FF595959` / `FFC00B0B` / `FFC5F30F` / `FF535353` / `00000000` | `FFF5F5F5` ×8 |

## Retro themes

| Theme | Primary / secondary | Root / symbols (2) / separator | Covered / flagged / detonated / pressed / revealed / canvas | Clues 1–8 |
|---|---|---|---|---|
| Retro | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF512E2E` / `FF511B1B` / `FF828282` | `FF4C4C4C` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF465181`, `FF446B3E`, `FF974444`, `FF7C407F`, `FF2D2D2D`, `FF585858`, `FF753C54`, `FF4C8099` |
| Pink Retro | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF4C4C4C` / `FF511B1B` / `FF828282` | `FF8D4660` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF2D429F`, `FF27731A`, `FF9F2121`, `FF841B88`, `FF1A1A1A`, `FF585858`, `FF7A1B43`, `FF287BA2` |
| Purple Retro | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF4C4C4C` / `FF511B1B` / `FF828282` | `FF664463` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF2D429F`, `FF27731A`, `FF9F2121`, `FF841B88`, `FF1A1A1A`, `FF585858`, `FF7A1B43`, `FF287BA2` |
| Blue Retro | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF4C4C4C` / `FF511B1B` / `FF828282` | `FF575D75` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF2D429F`, `FF27731A`, `FF9F2121`, `FF841B88`, `FF1A1A1A`, `FF585858`, `FF7A1B43`, `FF287BA2` |
| Cyan Retro | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF4C4C4C` / `FF511B1B` / `FF828282` | `FF567675` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF2D429F`, `FF27731A`, `FF9F2121`, `FF841B88`, `FF1A1A1A`, `FF585858`, `FF7A1B43`, `FF287BA2` |
| Army Retro | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF4C4C4C` / `FF511B1B` / `FF828282` | `FF676C5B` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF465181`, `FF446B3E`, `FF974444`, `FF7C407F`, `FF2D2D2D`, `FF585858`, `FF753C54`, `FF4C8099` |
| Retro Gray | `FF464646` / `FF5C5C5C` | `FF9D9D9D` / `FF773333` / `FF511B1B` / `FF828282` | `FF6E6E6E` / `FF7B7B7B` / `FF9C3C3C` / `FF6B6B6B` / `FF7F7F7F` / `FF9D9D9D` | `FF465181`, `FF446B3E`, `FF974444`, `FF7C407F`, `FF2D2D2D`, `FF585858`, `FF753C54`, `FF4C8099` |
| Retro Dark | `FFADADAD` / `FF848484` | `FF212121` / `FF492525` / `FF212121` / `FF575757` | `FF525252` / `FF545454` / `FF793434` / `FF6B6B6B` / `FF474747` / `FF222121` | `FF5B75AF`, `FF4D7B45`, `FF9D4B4B`, `FF8F5191`, `FFB0B0B0`, `FF818181`, `FF954D6B`, `FF5F8FA7` |
| Retro Green Dark | `FFADADAD` / `FF848484` | `FF212121` / `FF492525` / `FF212121` / `FF575757` | `FF4A7B6C` / `FF545454` / `FF793434` / `FF6B6B6B` / `FF474747` / `FF222121` | `FF5B75AF`, `FF4D7B45`, `FF9D4B4B`, `FF8F5191`, `FFB0B0B0`, `FF818181`, `FF954D6B`, `FF5F8FA7` |
| Retro Pink Dark | `FFADADAD` / `FF848484` | `FF212121` / `FF492525` / `FF212121` / `FF575757` | `FF7A4A62` / `FF545454` / `FF793434` / `FF6B6B6B` / `FF474747` / `FF222121` | `FF5B75AF`, `FF4C7C45`, `FF9D4B4B`, `FF8E5091`, `FFB0B0B0`, `FF818181`, `FF954D6B`, `FF5F90A7` |
| Retro Cyan Amoled | `FFF5F5F5` / `FFB7B7B7` | `00000000` / `FF502020` / `00000000` / `FF5A5A5A` | `FF52737F` / `FF595959` / `FFC00B0B` / `FF11F311` / `FF434343` / `00000000` | `FF5B75AF`, `FF4C7C45`, `FF9D4B4B`, `FF8E5091`, `FFB0B0B0`, `FF818181`, `FF954D6B`, `FF5F90A7` |

## Dynamic themes on iOS

| Theme | iOS rule |
|---|---|
| Material You | Generate a light or dark Material 3 tonal palette from the persisted app accent seed (`#6750A4` fallback), following system appearance. Map primary/on-primary/surface/on-surface/outline/error roles to the 20 tokens, and use on-surface for all clue colors unless contrast requires the fixed Retro clue sequence. |
| Material You Amoled | Use the same seed and accent roles as Material You, but set `surfaceRoot` and `canvas` to opaque `#000000`; keep covered/flagged/error colors tonal and all foregrounds at 4.5:1 or better. |

Android obtains these roles from API 31 wallpaper resources and therefore has no single portable hexadecimal table. Persist the generated iOS palette—not only the seed—in the saved settings so screenshots, restores, and game resumes are deterministic.
