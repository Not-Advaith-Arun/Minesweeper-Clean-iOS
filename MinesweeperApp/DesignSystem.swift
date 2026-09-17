import SwiftUI

enum RubikWeight {
  case light
  case regular
  case medium
  case semibold
  case bold
}

extension Font {
  static func rubik(_ size: CGFloat, weight: RubikWeight = .regular) -> Font {
    let name: String
    switch weight {
    case .light: name = "Rubik-Light"
    case .regular: name = "Rubik-Regular"
    case .medium, .semibold: name = "Rubik-Medium"
    case .bold: name = "Rubik-Bold"
    }
    return .custom(name, size: size)
  }
}

enum ReplicaSpacing {
  static let tiny: CGFloat = 6
  static let small: CGFloat = 10
  static let medium: CGFloat = 16
  static let large: CGFloat = 24
  static let huge: CGFloat = 36
}

enum ReplicaMetrics {
  static let horizontalInset: CGFloat = 36
  static let maxControlWidth: CGFloat = 302
  static let pillHeight: CGFloat = 40
  static let thinStroke: CGFloat = 1
}

@MainActor
enum ReplicaMotion {
  /// The source settles its major camera moves over roughly one second. Keep
  /// enough time between frames for the motion to read as a continuous glide
  /// on both 60 Hz and ProMotion displays.
  private static let polishCadence = 1.15

  static let firstRevealWave = 0.72
  static let firstFocusDelay = 0.22
  static let firstFocusDuration = 0.78
  static let firstControlsDelay = 1.02
  static let restartTransition = 0.96
  static let restartControlsDismiss = 0.20
  static let winGlyphFadeDelay = 0.54
  static let winGlyphFadeDuration = 0.40
  static let winResultDelay = 1.22
  static let replayCoverDuration = 0.74

  static func duration(_ base: Double, speedPercent: Double) -> Double {
    guard speedPercent > 0 else { return 0 }
    return base * durationScale(speedPercent: speedPercent)
  }

  static func durationScale(speedPercent: Double) -> Double {
    guard speedPercent > 0 else { return 0.01 }
    return polishCadence * 100 / min(200, max(5, speedPercent))
  }

  static func standard(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .smooth(duration: duration(0.24, speedPercent: speedPercent))
  }

  static func spring(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .spring(
      response: duration(0.32, speedPercent: speedPercent),
      dampingFraction: 0.82,
      blendDuration: duration(0.08, speedPercent: speedPercent)
    )
  }

  static func dialogPresent(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .smooth(duration: duration(0.22, speedPercent: speedPercent))
  }

  static func dialogDismiss(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .easeIn(duration: duration(0.18, speedPercent: speedPercent))
  }

  static var pressFeedback: Animation? {
    UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: 0.13)
  }
}

/// Keeps floating controls readable over clues even when glass is nearly clear.
struct BoardControlSurface: View {
  let theme: AppTheme

  var body: some View {
    Capsule(style: .continuous)
      .fill(theme.background.opacity(0.90))
      .overlay {
        Capsule(style: .continuous)
          .stroke(theme.foreground.opacity(0.18), lineWidth: 1)
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// Fallback chrome for iOS 17–25. Native Liquid Glass is applied directly to
/// interactive controls below when the iOS 26 API is available.
struct SemiMatteCapsuleSurface: View {
  let theme: AppTheme
  var emphasized = false

  var body: some View {
    Capsule(style: .continuous)
      .fill(semiMatteFill(theme: theme, emphasized: emphasized))
      .overlay {
        Capsule(style: .continuous)
          .stroke(semiMatteStroke(theme: theme, emphasized: emphasized), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(theme.usesLightBackground ? 0.05 : 0.18), radius: 3, y: 2)
  }
}

struct SemiMatteRoundedSurface: View {
  let theme: AppTheme
  var cornerRadius: CGFloat = 18
  var emphasized = false

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(semiMatteFill(theme: theme, emphasized: emphasized))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(semiMatteStroke(theme: theme, emphasized: emphasized), lineWidth: 1)
      }
      .shadow(color: Color.black.opacity(theme.usesLightBackground ? 0.05 : 0.18), radius: 3, y: 2)
  }
}

struct SemiMatteCircleSurface: View {
  let theme: AppTheme
  var emphasized = false

  var body: some View {
    Circle()
      .fill(semiMatteFill(theme: theme, emphasized: emphasized))
      .overlay {
        Circle().stroke(
          semiMatteStroke(theme: theme, emphasized: emphasized),
          lineWidth: 1
        )
      }
      .shadow(color: Color.black.opacity(theme.usesLightBackground ? 0.05 : 0.18), radius: 3, y: 2)
  }
}

private func semiMatteFill(theme: AppTheme, emphasized: Bool) -> Color {
  if emphasized { return theme.accent.opacity(theme.usesLightBackground ? 0.18 : 0.22) }
  return theme.usesLightBackground ? Color.black.opacity(0.075) : Color.white.opacity(0.10)
}

private func semiMatteStroke(theme: AppTheme, emphasized: Bool) -> Color {
  emphasized
    ? theme.accent.opacity(0.34)
    : theme.foreground.opacity(theme.usesLightBackground ? 0.13 : 0.16)
}

extension View {
  /// Apple applies glass after a control's size and appearance modifiers. This
  /// keeps the effect attached to the interactive content itself rather than
  /// to an empty background view that can disappear over a flat theme.
  @ViewBuilder
  func adaptiveGlassCapsule(
    theme: AppTheme,
    emphasized: Bool = false,
    enabled: Bool = true,
    isInteractive: Bool = true
  ) -> some View {
    if enabled {
      if #available(iOS 26.0, *) {
        if emphasized {
          if isInteractive {
            glassEffect(
              .regular.tint(theme.accent.opacity(0.20)).interactive(),
              in: Capsule(style: .continuous)
            )
          } else {
            glassEffect(
              .regular.tint(theme.accent.opacity(0.20)),
              in: Capsule(style: .continuous)
            )
          }
        } else {
          let tint = theme.foreground.opacity(theme.usesLightBackground ? 0.065 : 0.10)
          if isInteractive {
            glassEffect(
              .regular.tint(tint).interactive(),
              in: Capsule(style: .continuous)
            )
          } else {
            glassEffect(
              .regular.tint(tint),
              in: Capsule(style: .continuous)
            )
          }
        }
      } else {
        background(SemiMatteCapsuleSurface(theme: theme, emphasized: emphasized))
      }
    } else {
      self
    }
  }

  @ViewBuilder
  func adaptiveGlassRounded(
    theme: AppTheme,
    cornerRadius: CGFloat,
    emphasized: Bool = false
  ) -> some View {
    if #available(iOS 26.0, *) {
      if emphasized {
        glassEffect(
          .regular.tint(theme.accent.opacity(0.20)).interactive(),
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
      } else {
        glassEffect(
          .regular.tint(
            theme.foreground.opacity(theme.usesLightBackground ? 0.065 : 0.10)
          ).interactive(),
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
      }
    } else {
      background(
        SemiMatteRoundedSurface(
          theme: theme,
          cornerRadius: cornerRadius,
          emphasized: emphasized
        )
      )
    }
  }

  @ViewBuilder
  func adaptiveGlassCircle(theme: AppTheme, emphasized: Bool = false) -> some View {
    if #available(iOS 26.0, *) {
      if emphasized {
        glassEffect(
          .regular.tint(theme.accent.opacity(0.20)).interactive(),
          in: Circle()
        )
      } else {
        glassEffect(
          .regular.tint(
            theme.foreground.opacity(theme.usesLightBackground ? 0.065 : 0.10)
          ).interactive(),
          in: Circle()
        )
      }
    } else {
      background(SemiMatteCircleSurface(theme: theme, emphasized: emphasized))
    }
  }
}

struct CleanButtonStyle: ButtonStyle {
  let theme: AppTheme
  var filled = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(15, weight: .medium))
      .foregroundStyle(theme.foreground)
      .frame(maxWidth: .infinity, minHeight: 42)
      .padding(.horizontal, 18)
      .background {
        RoundedRectangle(cornerRadius: 21, style: .continuous)
          .fill(theme.accent.opacity(filled ? 0.14 : 0.055))
      }
      .adaptiveGlassRounded(
        theme: theme,
        cornerRadius: 21,
        emphasized: filled || configuration.isPressed
      )
      .scaleEffect(configuration.isPressed ? 0.975 : 1)
      .opacity(configuration.isPressed ? 0.92 : 1)
      .animation(ReplicaMotion.pressFeedback, value: configuration.isPressed)
  }
}

struct AndroidPillButtonStyle: ButtonStyle {
  let theme: AppTheme
  var filled = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(14, weight: .regular))
      .foregroundStyle(theme.foreground.opacity(filled ? 0.94 : 0.82))
      .frame(maxWidth: .infinity, minHeight: ReplicaMetrics.pillHeight)
      .padding(.horizontal, 20)
      .background {
        Capsule(style: .continuous)
          .fill(theme.accent.opacity(filled ? 0.14 : 0.055))
      }
      .adaptiveGlassCapsule(
        theme: theme,
        emphasized: filled || configuration.isPressed
      )
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.92 : 1)
      .animation(ReplicaMotion.pressFeedback, value: configuration.isPressed)
  }
}

struct RoundIconButtonStyle: ButtonStyle {
  let theme: AppTheme
  var size: CGFloat = 46
  var filled = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(size * 0.4, weight: .regular))
      .foregroundStyle(theme.foreground.opacity(filled ? 0.94 : 0.82))
      .frame(width: size, height: size)
      .background {
        Circle().fill(theme.accent.opacity(filled ? 0.14 : 0.055))
      }
      .adaptiveGlassCircle(theme: theme, emphasized: filled || configuration.isPressed)
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(ReplicaMotion.pressFeedback, value: configuration.isPressed)
  }
}

struct GlassDestructivePillButtonStyle: ButtonStyle {
  let theme: AppTheme

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(14, weight: .medium))
      .foregroundStyle(theme.mine)
      .frame(maxWidth: .infinity, minHeight: ReplicaMetrics.pillHeight)
      .padding(.horizontal, 20)
      .background {
        Capsule(style: .continuous)
          .fill(theme.mine.opacity(configuration.isPressed ? 0.18 : 0.08))
      }
      .adaptiveGlassCapsule(theme: theme, emphasized: configuration.isPressed)
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.92 : 1)
      .animation(ReplicaMotion.pressFeedback, value: configuration.isPressed)
  }
}

struct MineLogo: View {
  let theme: AppTheme
  var size: CGFloat = 116
  var tint: Color? = nil
  var holeTint: Color? = nil

  var body: some View {
    ZStack {
      ForEach(0..<8, id: \.self) { index in
        RoundedRectangle(cornerRadius: size * 0.02, style: .continuous)
          .fill(tint ?? theme.accent)
          .frame(width: size * 0.17, height: size * 0.18)
          .offset(y: -size * 0.41)
          .rotationEffect(.degrees(Double(index) * 45))
      }
      Circle().fill(tint ?? theme.accent).frame(width: size * 0.82, height: size * 0.82)
      RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
        .fill(holeTint ?? theme.background)
        .frame(width: size * 0.15, height: size * 0.15)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// A compact, optically balanced mine for counters and segmented controls.
/// The large home mark deliberately has longer teeth; scaling it down made the
/// HUD look jagged and visually heavier than the adjacent number.
struct MineCounterIcon: View {
  let theme: AppTheme
  var size: CGFloat = 18
  var tint: Color? = nil
  var holeTint: Color? = nil

  var body: some View {
    let foreground = tint ?? theme.foreground
    ZStack {
      ForEach(0..<8, id: \.self) { index in
        Capsule(style: .continuous)
          .fill(foreground)
          .frame(width: size * 0.16, height: size * 0.25)
          .offset(y: -size * 0.37)
          .rotationEffect(.degrees(Double(index) * 45))
      }
      Circle()
        .fill(foreground)
        .frame(width: size * 0.67, height: size * 0.67)
      RoundedRectangle(cornerRadius: size * 0.035, style: .continuous)
        .fill(holeTint ?? theme.background)
        .frame(width: size * 0.16, height: size * 0.16)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct MineGlyph: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) * 0.27
    path.addEllipse(
      in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    for index in 0..<8 {
      let angle = CGFloat(index) * .pi / 4
      let start = CGPoint(
        x: center.x + cos(angle) * radius * 0.85, y: center.y + sin(angle) * radius * 0.85)
      let end = CGPoint(
        x: center.x + cos(angle) * radius * 1.7, y: center.y + sin(angle) * radius * 1.7)
      path.move(to: start)
      path.addLine(to: end)
    }
    return path
  }
}

struct ReplicaBackground: View {
  let theme: AppTheme
  var body: some View { theme.background.ignoresSafeArea() }
}

struct SectionHeader: View {
  let title: String
  let theme: AppTheme
  var body: some View {
    Text(title.uppercased())
      .font(.rubik(11, weight: .semibold))
      .tracking(1.1)
      .foregroundStyle(theme.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct BackArrowIcon: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 24
      var path = Path()
      // Material arrow_back geometry has balanced 4...20 bounds. The old
      // 12...24 path extended to the canvas edge and sat visibly right of the
      // circular button's optical center.
      path.move(to: CGPoint(x: 12 * scale, y: 4 * scale))
      path.addLine(to: CGPoint(x: 4 * scale, y: 12 * scale))
      path.addLine(to: CGPoint(x: 12 * scale, y: 20 * scale))
      path.move(to: CGPoint(x: 4 * scale, y: 12 * scale))
      path.addLine(to: CGPoint(x: 20 * scale, y: 12 * scale))
      context.stroke(
        path,
        with: .color(color),
        style: StrokeStyle(lineWidth: 2.15 * scale, lineCap: .round, lineJoin: .round)
      )
    }
    .frame(width: 34, height: 34)
    .accessibilityHidden(true)
  }
}

struct FlagIcon: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 24
      var flag = Path()
      flag.move(to: CGPoint(x: 14.4 * scale, y: 6 * scale))
      flag.addLine(to: CGPoint(x: 14 * scale, y: 4 * scale))
      flag.addLine(to: CGPoint(x: 5 * scale, y: 4 * scale))
      flag.addLine(to: CGPoint(x: 5 * scale, y: 21 * scale))
      flag.addLine(to: CGPoint(x: 7 * scale, y: 21 * scale))
      flag.addLine(to: CGPoint(x: 7 * scale, y: 14 * scale))
      flag.addLine(to: CGPoint(x: 12.6 * scale, y: 14 * scale))
      flag.addLine(to: CGPoint(x: 13 * scale, y: 16 * scale))
      flag.addLine(to: CGPoint(x: 20 * scale, y: 16 * scale))
      flag.addLine(to: CGPoint(x: 20 * scale, y: 6 * scale))
      flag.closeSubpath()
      context.fill(flag, with: .color(color))
    }
    .accessibilityHidden(true)
  }
}

/// Local 24×24 Material-style palette path used by the Android reference.
/// Keeping it local avoids SF Symbol silhouette and weight differences.
struct PaletteIcon: View {
  let color: Color
  let holeColor: Color

  var body: some View {
    Canvas { context, size in
      let scale = min(size.width, size.height) / 24
      let origin = CGPoint(
        x: (size.width - 24 * scale) / 2,
        y: (size.height - 24 * scale) / 2
      )
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
      }

      var body = Path()
      body.move(to: point(12, 2))
      body.addCurve(to: point(2, 12), control1: point(6.49, 2), control2: point(2, 6.49))
      body.addCurve(to: point(12, 22), control1: point(2, 17.51), control2: point(6.49, 22))
      body.addCurve(to: point(14.5, 19.5), control1: point(13.38, 22), control2: point(14.5, 20.88))
      body.addCurve(to: point(13.86, 17.83), control1: point(14.5, 18.89), control2: point(14.27, 18.3))
      body.addCurve(to: point(13.73, 17.5), control1: point(13.78, 17.73), control2: point(13.73, 17.62))
      body.addCurve(to: point(14.23, 17), control1: point(13.73, 17.22), control2: point(13.95, 17))
      body.addLine(to: point(16, 17))
      body.addCurve(to: point(22, 11), control1: point(19.31, 17), control2: point(22, 14.31))
      body.addCurve(to: point(12, 2), control1: point(22, 6.04), control2: point(17.51, 2))
      body.closeSubpath()
      context.fill(body, with: .color(color))

      for (x, y, radius) in [(17.5, 11.5, 1.5), (14.5, 7.5, 1.5), (6.5, 11.5, 1.5), (9.5, 7.5, 1.5)] {
        context.fill(
          Path(ellipseIn: CGRect(
            x: origin.x + (x - radius) * scale,
            y: origin.y + (y - radius) * scale,
            width: radius * 2 * scale,
            height: radius * 2 * scale
          )),
          with: .color(holeColor)
        )
      }
    }
    .accessibilityHidden(true)
  }
}

struct ReplicaScreenHeader: View {
  let title: String
  let theme: AppTheme
  let dismiss: () -> Void

  var body: some View {
    ZStack {
      Text(title)
        .font(.rubik(20, weight: .medium))
        .foregroundStyle(theme.foreground)

      HStack {
        Button(action: dismiss) {
          BackArrowIcon(color: theme.foreground)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoundIconButtonStyle(theme: theme, size: 44))
        .accessibilityLabel("Back")
        .accessibilityIdentifier("replica.back")
        Spacer()
      }
    }
    .frame(height: 52)
    .padding(.horizontal, 18)
  }
}

extension View {
  func replicaNavigationAppearance(theme: AppTheme) -> some View {
    self
      .toolbarBackground(theme.background, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(theme.usesLightBackground ? .light : .dark, for: .navigationBar)
      .tint(theme.foreground)
  }
}
