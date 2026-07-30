import UIKit

enum HapticEvent {
  case selection
  case reveal
  case flag
  case warning
  case success
}

@MainActor
final class Haptics {
  static let shared = Haptics()

  private let selection = UISelectionFeedbackGenerator()
  private let lightImpact = UIImpactFeedbackGenerator(style: .light)
  private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
  private let notification = UINotificationFeedbackGenerator()

  func play(_ event: HapticEvent, durationMilliseconds: Double) {
    let normalized = CGFloat(min(1, max(0.15, durationMilliseconds / 100)))
    switch event {
    case .selection:
      selection.selectionChanged()
    case .reveal:
      lightImpact.impactOccurred(intensity: normalized)
    case .flag:
      rigidImpact.impactOccurred(intensity: normalized)
    case .warning:
      notification.notificationOccurred(.warning)
    case .success:
      notification.notificationOccurred(.success)
    }
  }
}
