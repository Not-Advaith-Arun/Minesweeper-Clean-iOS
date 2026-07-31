import SwiftUI

struct ThemeLibraryView: View {
  @Environment(AppStore.self) private var store
  private let columns = [GridItem(.adaptive(minimum: 148), spacing: 14)]

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(ThemeCatalog.all) { candidate in
            Button {
              store.chooseTheme(candidate)
            } label: {
              ThemeCard(theme: candidate, selected: candidate.id == store.themeID)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("theme.\(candidate.id)")
          }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 42)
        .animation(
          ReplicaMotion.standard(speedPercent: store.settings.animationSpeed), value: store.themeID)
      }
    }
    .navigationTitle("Themes")
    .navigationBarTitleDisplayMode(.inline)
    .replicaNavigationAppearance(theme: theme)
  }
}

private struct ThemeCard: View {
  let theme: AppTheme
  let selected: Bool

  var body: some View {
    HStack(spacing: 12) {
      ThemeSwatch(theme: theme, selected: selected, compact: true)
      VStack(alignment: .leading, spacing: 3) {
        Text(theme.name)
          .font(.rubik(14, weight: .regular))
          .foregroundStyle(theme.foreground.opacity(0.84))
          .lineLimit(2)
        if theme.isAMOLED {
          Text("AMOLED")
            .font(.rubik(9, weight: .semibold))
            .foregroundStyle(theme.muted)
        }
      }
      Spacer(minLength: 0)
      if selected {
        Image(systemName: "checkmark")
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(theme.accent)
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.background))
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(
        selected ? theme.accent.opacity(0.68) : theme.muted.opacity(0.18),
        lineWidth: ReplicaMetrics.thinStroke))
  }
}
