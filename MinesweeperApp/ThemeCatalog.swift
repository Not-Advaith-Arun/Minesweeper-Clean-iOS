import SwiftUI

private let decodedRevealedSurface: [String: UInt32] = [
  "alpine": 0x384751,
  "diletto": 0xD9D9D9,
  "aurum": 0x3F3D38,
  "kawa": 0x2C362C,
  "monokai": 0x582F56,
  "laurel": 0x586053,
  "rossa": 0xE3E3E3,
  "nennau": 0xD9D9D9,
  "ambra": 0x606060,
  "amoled": 0x535353,
  "orange_amoled": 0x535353,
  "yellow_amoled": 0x535353,
  "red_amoled": 0x535353,
  "purple_amoled": 0x535353,
  "pink_amoled": 0x545454,
  "blue_amoled": 0x535353,
  "cyan_amoled": 0x535353,
  "green_amoled": 0x535353,
  "lime_amoled": 0x535353,
  "retro": 0x7F7F7F,
  "pink_retro": 0x7F7F7F,
  "purple_retro": 0x7F7F7F,
  "blue_retro": 0x7F7F7F,
  "cyan_retro": 0x7F7F7F,
  "army_retro": 0x7F7F7F,
  "retro_gray": 0x7F7F7F,
  "retro_dark": 0x474747,
  "retro_green_dark": 0x474747,
  "retro_pink_dark": 0x474747,
  "retro_cyan_amoled": 0x434343,
]

private let decodedFlaggedSurface: [String: UInt32] = [
  "alpine": 0x808F9E,
  "diletto": 0xE1E1E1,
  "aurum": 0x636363,
  "kawa": 0x566056,
  "monokai": 0x61624F,
  "laurel": 0x646862,
  "rossa": 0xE2E2E2,
  "nennau": 0xE2E2E2,
  "ambra": 0x666666,
  "amoled": 0x595959,
  "orange_amoled": 0x595959,
  "yellow_amoled": 0x595959,
  "red_amoled": 0x595959,
  "purple_amoled": 0x595959,
  "pink_amoled": 0x595959,
  "blue_amoled": 0x595959,
  "cyan_amoled": 0x595959,
  "green_amoled": 0x595959,
  "lime_amoled": 0x595959,
  "retro": 0x7B7B7B,
  "pink_retro": 0x7B7B7B,
  "purple_retro": 0x7B7B7B,
  "blue_retro": 0x7B7B7B,
  "cyan_retro": 0x7B7B7B,
  "army_retro": 0x7B7B7B,
  "retro_gray": 0x7B7B7B,
  "retro_dark": 0x545454,
  "retro_green_dark": 0x545454,
  "retro_pink_dark": 0x545454,
  "retro_cyan_amoled": 0x595959,
]

private let decodedSeparator: [String: UInt32] = [
  "alpine": 0x3B5368,
  "diletto": 0xD5D5D5,
  "aurum": 0x57554C,
  "kawa": 0x2A352A,
  "monokai": 0x644C63,
  "laurel": 0x595F53,
  "rossa": 0xE8E3E3,
  "nennau": 0xD5D5D5,
  "ambra": 0x757474,
  "amoled": 0x5A5A5A,
  "orange_amoled": 0x5A5A5A,
  "yellow_amoled": 0x5A5A5A,
  "red_amoled": 0x5A5A5A,
  "purple_amoled": 0x5A5A5A,
  "pink_amoled": 0x5A5A5A,
  "blue_amoled": 0x5A5A5A,
  "cyan_amoled": 0x5A5A5A,
  "green_amoled": 0x5A5A5A,
  "lime_amoled": 0x5A5A5A,
  "retro": 0x828282,
  "pink_retro": 0x828282,
  "purple_retro": 0x828282,
  "blue_retro": 0x828282,
  "cyan_retro": 0x828282,
  "army_retro": 0x828282,
  "retro_gray": 0x828282,
  "retro_dark": 0x575757,
  "retro_green_dark": 0x575757,
  "retro_pink_dark": 0x575757,
  "retro_cyan_amoled": 0x5A5A5A,
]

struct AppTheme: Identifiable, Hashable {
  let id: String
  let name: String
  let background: Color
  let surface: Color
  let covered: Color
  let flagged: Color
  let separator: Color
  let accent: Color
  let foreground: Color
  let muted: Color
  let mine: Color
  let clueColors: [Color]
  let isAMOLED: Bool

  init(
    id: String,
    name: String,
    background: UInt32,
    surface: UInt32,
    covered: UInt32,
    accent: UInt32,
    foreground: UInt32,
    muted: UInt32,
    mine: UInt32 = 0xFF5252,
    clues: [UInt32] = [
      0x42A5F5, 0x66BB6A, 0xEF5350, 0x7E57C2, 0xAB47BC, 0x26A69A, 0x8D6E63, 0x78909C,
    ],
    isAMOLED: Bool = false
  ) {
    self.id = id
    self.name = name
    self.background = Color(hex: background)
    self.surface = Color(hex: decodedRevealedSurface[id] ?? surface)
    self.covered = Color(hex: covered)
    self.flagged = Color(hex: decodedFlaggedSurface[id] ?? surface)
    self.separator = Color(hex: decodedSeparator[id] ?? muted)
    self.accent = Color(hex: accent)
    self.foreground = Color(hex: foreground)
    self.muted = Color(hex: muted)
    self.mine = Color(hex: mine)
    self.clueColors = clues.map { Color(hex: $0) }
    self.isAMOLED = isAMOLED
  }

  func clue(_ value: Int) -> Color {
    clueColors.indices.contains(value - 1) ? clueColors[value - 1] : foreground
  }
}

enum ThemeCatalog {
  // Values below are decoded from v1.21.3's ri2/mj1 theme table. Mapping:
  // background=f, surface=n (revealed), covered=j, accent=m, foreground=d, muted=e,
  // mine=l, clue colors=p...w.
  static let all: [AppTheme] = [
    .init(
      id: "alpine", name: "Alpine", background: 0x0D151D, surface: 0x0F171D, covered: 0x41A3CD,
      accent: 0x55C2F0, foreground: 0xBCD0E1, muted: 0x9FB7CD, mine: 0xCF3F3F,
      clues: [0xBCD0E1, 0xBCD0E1, 0xBCD0E1, 0xBCD0E1, 0xBCD0E1, 0xBCD0E1, 0xBCD0E1, 0xBCD0E1]),
    .init(
      id: "diletto", name: "Diletto", background: 0xF9F9F9, surface: 0xA43434, covered: 0xB8B19E,
      accent: 0xAB9F73, foreground: 0x7C7C7C, muted: 0x979797, mine: 0xD86E6E,
      clues: [0x7C7C7C, 0x7C7C7C, 0x7C7C7C, 0x7C7C7C, 0x7C7C7C, 0x7C7C7C, 0x7C7C7C, 0x7C7C7C]),
    .init(
      id: "aurum", name: "Aurum", background: 0x191919, surface: 0x111111, covered: 0x988D62,
      accent: 0x9B915D, foreground: 0xD6D6D6, muted: 0xC6C6C6, mine: 0xD74157,
      clues: [0xD6D6D6, 0xD6D6D6, 0xD6D6D6, 0xD6D6D6, 0xD6D6D6, 0xD6D6D6, 0xD6D6D6, 0xD6D6D6]),
    .init(
      id: "kawa", name: "Kawa", background: 0x090909, surface: 0x090909, covered: 0x349734,
      accent: 0x2FA12F, foreground: 0xC9D5C9, muted: 0xB6C1B6, mine: 0xB31E1E,
      clues: [0xC9D5C9, 0xC9D5C9, 0xC9D5C9, 0xC9D5C9, 0xC9D5C9, 0xC9D5C9, 0xC9D5C9, 0xC9D5C9]),
    .init(
      id: "monokai", name: "Monokai", background: 0x1B1B1B, surface: 0x1B1B1B, covered: 0xB53462,
      accent: 0xF92571, foreground: 0xC7C392, muted: 0x9F9C77, mine: 0xD13434,
      clues: [0xC7C392, 0xC7C392, 0xC7C392, 0xC7C392, 0xC7C392, 0xC7C392, 0xC7C392, 0xC7C392]),
    .init(
      id: "laurel", name: "Laurel", background: 0x373B35, surface: 0x373B35, covered: 0xAFC99D,
      accent: 0xAFC99D, foreground: 0xDCDCDC, muted: 0xC9C9C9, mine: 0xCF7F7F,
      clues: [0xDCDCDC, 0xDCDCDC, 0xDCDCDC, 0xDCDCDC, 0xDCDCDC, 0xDCDCDC, 0xDCDCDC, 0xDCDCDC]),
    .init(
      id: "rossa", name: "Rossa", background: 0xFFFFFF, surface: 0xA20F0F, covered: 0xD7999E,
      accent: 0xBB555D, foreground: 0x797979, muted: 0x8F8F8F, mine: 0xF26D6D,
      clues: [0x797979, 0x797979, 0x797979, 0x797979, 0x797979, 0x797979, 0x797979, 0x797979]),
    .init(
      id: "nennau", name: "Nennau", background: 0xF9F9F9, surface: 0x963D3D, covered: 0x7FABC7,
      accent: 0x699FBF, foreground: 0x7B7B7B, muted: 0x898989, mine: 0xD86E6E,
      clues: [0x7B7B7B, 0x7B7B7B, 0x7B7B7B, 0x7B7B7B, 0x7B7B7B, 0x7B7B7B, 0x7B7B7B, 0x7B7B7B]),
    .init(
      id: "ambra", name: "Ambra", background: 0x333333, surface: 0x431A0D, covered: 0xD87F37,
      accent: 0xE7791E, foreground: 0xE9E9E9, muted: 0xCFCFCF, mine: 0xB6350D,
      clues: [0xE9E9E9, 0xE9E9E9, 0xE9E9E9, 0xE9E9E9, 0xE9E9E9, 0xE9E9E9, 0xE9E9E9, 0xE9E9E9]),
    .init(
      id: "amoled", name: "Amoled", background: 0x000000, surface: 0x000000, covered: 0xD1D1D1,
      accent: 0xFFFFFF, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "orange_amoled", name: "Orange Amoled", background: 0x000000, surface: 0x000000,
      covered: 0xCA742D, accent: 0xF5750B, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "yellow_amoled", name: "Yellow Amoled", background: 0x000000, surface: 0x000000,
      covered: 0xCFD162, accent: 0xF7F70B, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "red_amoled", name: "Red Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x983F3F, accent: 0xE31D1D, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xF40D0D,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "purple_amoled", name: "Purple Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x8A4FA1, accent: 0xB73DE3, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "pink_amoled", name: "Pink Amoled", background: 0x000000, surface: 0x000000,
      covered: 0xC569B0, accent: 0xF917C7, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "blue_amoled", name: "Blue Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x3285B1, accent: 0x2563F1, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "cyan_amoled", name: "Cyan Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x5EB3BF, accent: 0x0BF3F3, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "green_amoled", name: "Green Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x45A645, accent: 0x11F311, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "lime_amoled", name: "Lime Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x9EC45A, accent: 0xC5F30F, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5, 0xF5F5F5],
      isAMOLED: true),
    .init(
      id: "retro", name: "Retro", background: 0x9D9D9D, surface: 0x511B1B, covered: 0x4C4C4C,
      accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x465181, 0x446B3E, 0x974444, 0x7C407F, 0x2D2D2D, 0x585858, 0x753C54, 0x4C8099]),
    .init(
      id: "pink_retro", name: "Pink Retro", background: 0x9D9D9D, surface: 0x511B1B,
      covered: 0x8D4660, accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x2D429F, 0x27731A, 0x9F2121, 0x841B88, 0x1A1A1A, 0x585858, 0x7A1B43, 0x287BA2]),
    .init(
      id: "purple_retro", name: "Purple Retro", background: 0x9D9D9D, surface: 0x511B1B,
      covered: 0x664463, accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x2D429F, 0x27731A, 0x9F2121, 0x841B88, 0x1A1A1A, 0x585858, 0x7A1B43, 0x287BA2]),
    .init(
      id: "blue_retro", name: "Blue Retro", background: 0x9D9D9D, surface: 0x511B1B,
      covered: 0x575D75, accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x2D429F, 0x27731A, 0x9F2121, 0x841B88, 0x1A1A1A, 0x585858, 0x7A1B43, 0x287BA2]),
    .init(
      id: "cyan_retro", name: "Cyan Retro", background: 0x9D9D9D, surface: 0x511B1B,
      covered: 0x567675, accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x2D429F, 0x27731A, 0x9F2121, 0x841B88, 0x1A1A1A, 0x585858, 0x7A1B43, 0x287BA2]),
    .init(
      id: "army_retro", name: "Army Retro", background: 0x9D9D9D, surface: 0x511B1B,
      covered: 0x676C5B, accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x465181, 0x446B3E, 0x974444, 0x7C407F, 0x2D2D2D, 0x585858, 0x753C54, 0x4C8099]),
    .init(
      id: "retro_gray", name: "Retro Gray", background: 0x9D9D9D, surface: 0x511B1B,
      covered: 0x6E6E6E, accent: 0x6B6B6B, foreground: 0x464646, muted: 0x5C5C5C, mine: 0x9C3C3C,
      clues: [0x465181, 0x446B3E, 0x974444, 0x7C407F, 0x2D2D2D, 0x585858, 0x753C54, 0x4C8099]),
    .init(
      id: "retro_dark", name: "Retro Dark", background: 0x212121, surface: 0x212121,
      covered: 0x525252, accent: 0x6B6B6B, foreground: 0xADADAD, muted: 0x848484, mine: 0x793434,
      clues: [0x5B75AF, 0x4D7B45, 0x9D4B4B, 0x8F5191, 0xB0B0B0, 0x818181, 0x954D6B, 0x5F8FA7]),
    .init(
      id: "retro_green_dark", name: "Retro Green Dark", background: 0x212121, surface: 0x212121,
      covered: 0x4A7B6C, accent: 0x6B6B6B, foreground: 0xADADAD, muted: 0x848484, mine: 0x793434,
      clues: [0x5B75AF, 0x4D7B45, 0x9D4B4B, 0x8F5191, 0xB0B0B0, 0x818181, 0x954D6B, 0x5F8FA7]),
    .init(
      id: "retro_pink_dark", name: "Retro Pink Dark", background: 0x212121, surface: 0x212121,
      covered: 0x7A4A62, accent: 0x6B6B6B, foreground: 0xADADAD, muted: 0x848484, mine: 0x793434,
      clues: [0x5B75AF, 0x4C7C45, 0x9D4B4B, 0x8E5091, 0xB0B0B0, 0x818181, 0x954D6B, 0x5F90A7]),
    .init(
      id: "retro_cyan_amoled", name: "Retro Cyan Amoled", background: 0x000000, surface: 0x000000,
      covered: 0x52737F, accent: 0x11F311, foreground: 0xF5F5F5, muted: 0xB7B7B7, mine: 0xC00B0B,
      clues: [0x5B75AF, 0x4C7C45, 0x9D4B4B, 0x8E5091, 0xB0B0B0, 0x818181, 0x954D6B, 0x5F90A7],
      isAMOLED: true),

    // Android generates these from the device palette. Stable local equivalents
    // keep the private iOS build deterministic and offline.
    .init(
      id: "material_you", name: "Material You", background: 0xF9F0FA, surface: 0xFFF7FF,
      covered: 0xE1BEE7, accent: 0x7A4E7D, foreground: 0x211A21, muted: 0x776D77),
    .init(
      id: "material_you_amoled", name: "Material You Amoled", background: 0x000000,
      surface: 0x090909, covered: 0x3B273D, accent: 0xD7B8D9, foreground: 0xF7EEF7, muted: 0x9E949E,
      isAMOLED: true),
  ]

  static let fallback = all[14]  // Pink Amoled, matching the supplied reference.
  static func theme(id: String) -> AppTheme { all.first { $0.id == id } ?? fallback }
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }
}
