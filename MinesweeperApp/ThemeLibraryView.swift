import SwiftUI

struct ThemeLibraryView: View {
  @Environment(AppStore.self) private var store
  private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

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
        .padding(16)
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
      ThemeSwatch(theme: theme, selected: selected)
      VStack(alignment: .leading, spacing: 3) {
        Text(theme.name)
          .font(.rubik(13, weight: .medium))
          .foregroundStyle(theme.foreground)
          .lineLimit(2)
        if theme.isAMOLED {
          Text("AMOLED")
            .font(.rubik(9, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(theme.muted)
        }
      }
      Spacer(minLength: 0)
      if selected {
        Image(systemName: "checkmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(theme.accent)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.surface))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(
        selected ? theme.accent : theme.muted.opacity(0.2), lineWidth: selected ? 2 : 1))
  }
}
