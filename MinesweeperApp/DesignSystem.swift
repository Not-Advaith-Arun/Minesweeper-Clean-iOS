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
  static let pillHeight: CGFloat = 44
  static let thinStroke: CGFloat = 1
}

enum ReplicaMotion {
  static func standard(speedPercent: Double) -> Animation? {
    guard speedPercent > 0 else { return nil }
    return .easeInOut(duration: 0.24 * 100 / speedPercent)
  }

  static func spring(speedPercent: Double) -> Animation? {
    guard speedPercent > 0 else { return nil }
    return .spring(response: 0.32 * 100 / speedPercent, dampingFraction: 0.76)
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
        RoundedRectangle(cornerRadius: 21, style: .continuous)
          .fill(filled ? theme.foreground : theme.background.opacity(0.001))
          .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
              .stroke(
                theme.foreground.opacity(configuration.isPressed ? 0.55 : 0.82), lineWidth: 1.25)
          }
      }
      .scaleEffect(configuration.isPressed ? 0.975 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct AndroidPillButtonStyle: ButtonStyle {
  let theme: AppTheme
  var filled = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.rubik(19, weight: .regular))
      .foregroundStyle(filled ? theme.background : theme.foreground.opacity(0.78))
      .frame(maxWidth: .infinity, minHeight: ReplicaMetrics.pillHeight)
      .padding(.horizontal, 20)
      .background {
        Capsule(style: .continuous)
          .fill(filled ? theme.foreground : theme.background.opacity(0.001))
          .overlay {
            Capsule(style: .continuous)
              .stroke(
                theme.muted.opacity(configuration.isPressed ? 0.42 : 0.24),
                lineWidth: ReplicaMetrics.thinStroke)
          }
      }
      .opacity(configuration.isPressed ? 0.62 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
      .background(Circle().fill(filled ? theme.foreground : theme.background.opacity(0.001)))
      .overlay(Circle().stroke(theme.muted.opacity(0.24), lineWidth: filled ? 0 : 1))
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct MineLogo: View {
  let theme: AppTheme
  var size: CGFloat = 116

  var body: some View {
    ZStack {
      ForEach(0..<8, id: \.self) { index in
        Capsule(style: .continuous)
          .fill(theme.accent)
          .frame(width: size * 0.13, height: size * 0.42)
          .offset(y: -size * 0.34)
          .rotationEffect(.degrees(Double(index) * 45))
      }
      Circle().fill(theme.accent).frame(width: size * 0.67, height: size * 0.67)
      RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
        .fill(theme.background)
        .frame(width: size * 0.17, height: size * 0.17)
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

extension View {
  func replicaNavigationAppearance(theme: AppTheme) -> some View {
    self
      .toolbarBackground(theme.background, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(theme.isAMOLED ? .dark : nil, for: .navigationBar)
      .tint(theme.foreground)
  }
}
