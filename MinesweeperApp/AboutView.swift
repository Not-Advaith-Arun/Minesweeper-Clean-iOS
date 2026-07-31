import SwiftUI

struct AboutView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      VStack(spacing: 22) {
        Spacer(minLength: 80)
        MineLogo(theme: theme, size: 104)
        VStack(spacing: 6) {
          Text(AppConstants.replicaName)
            .font(.rubik(24, weight: .regular))
          Text(AppConstants.appSubtitle.uppercased())
            .font(.rubik(11, weight: .medium))
            .foregroundStyle(theme.muted)
        }

        Text(
          "A private, ad-free recreation made for personal play. Not affiliated with or endorsed by Dustland Design."
        )
        .font(.rubik(14, weight: .regular))
        .multilineTextAlignment(.center)
        .foregroundStyle(theme.foreground.opacity(0.72))
        .frame(maxWidth: 310)

        Text("Plays entirely offline")
          .font(.rubik(12, weight: .regular))
          .foregroundStyle(theme.muted)

        Text("Reference v1.21.3  •  Rubik typeface  •  Material Symbols")
          .font(.rubik(10))
          .multilineTextAlignment(.center)
          .foregroundStyle(theme.muted)

        Button("Done") { dismiss() }
          .buttonStyle(AndroidPillButtonStyle(theme: theme))
          .frame(maxWidth: ReplicaMetrics.maxControlWidth)
          .padding(.top, 14)
          .accessibilityIdentifier("about.done")

        Spacer(minLength: 120)
      }
      .padding(.horizontal, ReplicaMetrics.horizontalInset)
      .foregroundStyle(theme.foreground.opacity(0.78))
    }
  }
}
