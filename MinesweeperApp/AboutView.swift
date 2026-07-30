import SwiftUI

struct AboutView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      VStack(spacing: 18) {
        MineLogo(theme: theme, size: 76)
        VStack(spacing: 4) {
          Text(AppConstants.replicaName)
            .font(.rubik(24, weight: .semibold))
          Text(AppConstants.appSubtitle.uppercased())
            .font(.rubik(11, weight: .medium))
            .tracking(1.8)
            .foregroundStyle(theme.muted)
        }

        Text(
          "A private, ad-free recreation made for personal play. Not affiliated with or endorsed by Dustland Design."
        )
        .font(.rubik(14))
        .multilineTextAlignment(.center)
        .foregroundStyle(theme.foreground.opacity(0.82))
        .frame(maxWidth: 310)

        Text("Plays entirely offline")
          .font(.rubik(12, weight: .medium))
          .foregroundStyle(theme.muted)

        Text("Reference v1.21.3  •  Rubik typeface  •  Material Symbols")
          .font(.rubik(10))
          .multilineTextAlignment(.center)
          .foregroundStyle(theme.muted)

        Button("Done") { dismiss() }
          .buttonStyle(CleanButtonStyle(theme: theme, filled: true))
          .frame(maxWidth: 220)
          .accessibilityIdentifier("about.done")
      }
      .padding(28)
      .foregroundStyle(theme.foreground)
    }
  }
}
