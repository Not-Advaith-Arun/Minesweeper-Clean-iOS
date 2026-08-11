import SwiftUI

struct AboutView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      ScrollView {
        VStack(spacing: 12) {
        MineLogo(theme: theme, size: 70)
        VStack(spacing: 4) {
          Text(AppConstants.replicaName)
            .font(.rubik(21, weight: .regular))
          Text(AppConstants.appSubtitle.uppercased())
            .font(.rubik(11, weight: .medium))
            .foregroundStyle(theme.muted)
        }

        Text(
          "Private, non-commercial recreation inspired by “Minesweeper — The Clean One.” Not affiliated with or endorsed by Dustland Design. Original product name and visual references belong to their respective owner."
        )
        .font(.rubik(12, weight: .regular))
        .multilineTextAlignment(.center)
        .foregroundStyle(theme.foreground.opacity(0.72))
        .frame(maxWidth: 310)
        .fixedSize(horizontal: false, vertical: true)

        Text("Plays entirely offline")
          .font(.rubik(12, weight: .regular))
          .foregroundStyle(theme.muted)

        Text("Reference v1.22.1  •  Rubik (OFL 1.1)  •  Material Design Icons (Apache 2.0)")
          .font(.rubik(10))
          .multilineTextAlignment(.center)
          .foregroundStyle(theme.muted)
          .frame(maxWidth: 310)
          .fixedSize(horizontal: false, vertical: true)

        Button("Done") { dismiss() }
          .buttonStyle(AndroidPillButtonStyle(theme: theme))
          .frame(maxWidth: ReplicaMetrics.maxControlWidth)
          .padding(.top, 4)
          .accessibilityIdentifier("about.done")

        }
        .padding(.vertical, 16)
      }
      .padding(.horizontal, ReplicaMetrics.horizontalInset)
      .foregroundStyle(theme.foreground.opacity(0.78))
    }
  }
}
