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

enum ReplicaMotion {
  static func standard(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .easeInOut(duration: 0.24 * 100 / speedPercent)
  }

  static func spring(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .spring(response: 0.32 * 100 / speedPercent, dampingFraction: 0.76)
  }

  static func dialogPresent(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .easeOut(duration: 0.22 * 100 / speedPercent)
  }

  static func dialogDismiss(speedPercent: Double) -> Animation? {
    guard speedPercent > 0, !UIAccessibility.isReduceMotionEnabled else { return nil }
    return .easeIn(duration: 0.18 * 100 / speedPercent)
  }

  static var pressFeedback: Animation? {
    UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.12)
  }
}

/// Restrained glass used for interactive chrome. The board intentionally does
/// not use this treatment so clues and connected covered regions stay crisp.
struct GlassCapsuleSurface: View {
  let theme: AppTheme
  var emphasized = false

  var body: some View {
    Capsule(style: .continuous)
      // Material remains the base in every theme. AMOLED previously replaced
      // it with an opaque black fill, which made those controls read as ash
      // gray paint instead of glass.
      .fill(.ultraThinMaterial)
      .overlay {
        Capsule(style: .continuous)
          .fill(
            theme.isAMOLED
              ? Color.black.opacity(0.38)
              : theme.usesLightBackground
                ? Color.white.opacity(0.40) : Color.white.opacity(0.035)
          )
      }
      .overlay {
        Capsule(style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(
                  theme.isAMOLED ? 0.10 : theme.usesLightBackground ? 0.40 : 0.28),
                theme.accent.opacity(theme.isAMOLED ? (emphasized ? 0.13 : 0.07) : (emphasized ? 0.15 : 0.06)),
                theme.surface.opacity(
                  theme.isAMOLED ? 0.16 : theme.usesLightBackground ? 0.05 : 0.14),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      }
      .overlay {
        Capsule(style: .continuous)
          .stroke(
            LinearGradient(
              colors: [
                Color.white.opacity(theme.isAMOLED ? 0.28 : 0.72),
                theme.accent.opacity(theme.isAMOLED ? 0.24 : 0.30),
                theme.separator.opacity(0.20),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      }
      .shadow(color: theme.accent.opacity(emphasized ? 0.11 : 0.025), radius: 7, y: 3)
      .shadow(color: Color.black.opacity(theme.isAMOLED ? 0.24 : 0.045), radius: 5, y: 2)
  }
}

struct GlassRoundedSurface: View {
  let theme: AppTheme
  var cornerRadius: CGFloat = 18
  var emphasized = false

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(.ultraThinMaterial)
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(
            theme.isAMOLED
              ? Color.black.opacity(0.38)
              : theme.usesLightBackground
                ? Color.white.opacity(0.40) : Color.white.opacity(0.035)
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(
                  theme.isAMOLED ? 0.10 : theme.usesLightBackground ? 0.40 : 0.30),
                theme.accent.opacity(theme.isAMOLED ? (emphasized ? 0.13 : 0.07) : (emphasized ? 0.13 : 0.05)),
                theme.surface.opacity(
                  theme.isAMOLED ? 0.16 : theme.usesLightBackground ? 0.06 : 0.20),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(
            LinearGradient(
              colors: [
                Color.white.opacity(theme.isAMOLED ? 0.28 : 0.76),
                theme.accent.opacity(theme.isAMOLED ? 0.23 : 0.28),
                theme.separator.opacity(0.18),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
      }
      .shadow(color: theme.accent.opacity(emphasized ? 0.10 : 0.025), radius: 10, y: 5)
      .shadow(color: Color.black.opacity(theme.isAMOLED ? 0.28 : 0.07), radius: 8, y: 4)
  }
}

struct GlassCircleSurface: View {
  let theme: AppTheme
  var emphasized = false

  var body: some View {
    Circle()
      .fill(.ultraThinMaterial)
      .overlay {
        Circle().fill(
          theme.isAMOLED
            ? Color.black.opacity(0.38)
            : theme.usesLightBackground
              ? Color.white.opacity(0.40) : Color.white.opacity(0.035)
        )
      }
      .overlay {
        Circle().fill(
          LinearGradient(
            colors: [
              Color.white.opacity(
                theme.isAMOLED ? 0.11 : theme.usesLightBackground ? 0.40 : 0.30),
              theme.accent.opacity(emphasized ? 0.15 : 0.07),
              theme.surface.opacity(
                theme.isAMOLED ? 0.16 : theme.usesLightBackground ? 0.05 : 0.14),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      }
      .overlay {
        Circle().stroke(
          LinearGradient(
            colors: [
              Color.white.opacity(theme.isAMOLED ? 0.30 : 0.74),
              theme.accent.opacity(theme.isAMOLED ? 0.24 : 0.30),
              theme.separator.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
      }
      .shadow(color: theme.accent.opacity(emphasized ? 0.11 : 0.035), radius: 7, y: 3)
      .shadow(color: Color.black.opacity(theme.isAMOLED ? 0.26 : 0.06), radius: 5, y: 2)
  }
}

struct CleanButtonStyle: ButtonStyle {
  let theme: AppTheme
  var filled = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(15, weight: .medium))
      .foregroundStyle(filled ? theme.background : theme.foreground)
      .frame(maxWidth: .infinity, minHeight: 42)
      .padding(.horizontal, 18)
      .background {
        GlassRoundedSurface(
          theme: theme,
          cornerRadius: 21,
          emphasized: filled || configuration.isPressed
        )
        .overlay {
          RoundedRectangle(cornerRadius: 21, style: .continuous)
            .fill(filled ? theme.foreground.opacity(0.62) : Color.clear)
        }
      }
      .scaleEffect(configuration.isPressed ? 0.975 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(ReplicaMotion.pressFeedback, value: configuration.isPressed)
  }
}

struct AndroidPillButtonStyle: ButtonStyle {
  let theme: AppTheme
  var filled = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(14, weight: .regular))
      .foregroundStyle(filled ? theme.background : theme.foreground.opacity(0.78))
      .frame(maxWidth: .infinity, minHeight: ReplicaMetrics.pillHeight)
      .padding(.horizontal, 20)
      .background {
        GlassCapsuleSurface(
          theme: theme,
          emphasized: filled || configuration.isPressed
        )
        .overlay {
          Capsule(style: .continuous)
            .fill(filled ? theme.foreground.opacity(0.62) : Color.clear)
        }
      }
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.62 : 1)
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
      .foregroundStyle(filled ? theme.background : theme.foreground.opacity(0.76))
      .frame(width: size, height: size)
      .background {
        GlassCircleSurface(theme: theme, emphasized: filled || configuration.isPressed)
          .overlay {
            Circle().fill(filled ? theme.foreground.opacity(0.46) : Color.clear)
          }
      }
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
        GlassCapsuleSurface(theme: theme, emphasized: configuration.isPressed)
          .overlay {
            Capsule(style: .continuous)
              .fill(theme.mine.opacity(configuration.isPressed ? 0.18 : 0.08))
          }
      }
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.72 : 1)
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
      .toolbarColorScheme(theme.isAMOLED ? .dark : nil, for: .navigationBar)
      .tint(theme.foreground)
  }
}
