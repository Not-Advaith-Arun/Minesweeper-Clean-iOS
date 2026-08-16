import SwiftUI

struct ThemeLibraryView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  private let columns = [GridItem(.adaptive(minimum: 148), spacing: 14)]

  var body: some View {
    let theme = store.theme
    VStack(spacing: 0) {
        ReplicaScreenHeader(title: "Themes", theme: theme) { dismiss() }
        ScrollView {
          LazyVGrid(columns: columns, spacing: 12) {
          ForEach(ThemeCatalog.displayOrder) { candidate in
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
          .padding(.top, 18)
          .padding(.bottom, 42)
          .animation(
            ReplicaMotion.standard(speedPercent: store.settings.animationSpeed), value: store.themeID)
        }
    }
    .background(ReplicaBackground(theme: theme))
    .toolbar(.hidden, for: .navigationBar)
  }
}

private struct ThemeCard: View {
  @Environment(AppStore.self) private var store
  let theme: AppTheme
  let selected: Bool

  var body: some View {
    HStack(spacing: 12) {
      ThemeSwatch(theme: theme, selected: selected, compact: true)
      VStack(alignment: .leading, spacing: 3) {
        Text(theme.name)
          .font(.rubik(13, weight: .regular))
          .foregroundStyle(theme.foreground.opacity(0.84))
          .lineLimit(2)
          .minimumScaleFactor(0.84)
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
    .background {
      SemiMatteRoundedSurface(theme: store.theme, cornerRadius: 7, emphasized: selected)
        .overlay {
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(theme.background.opacity(store.theme.isAMOLED ? 0.54 : 0.66))
        }
    }
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(
        selected ? theme.accent.opacity(0.68) : theme.muted.opacity(0.18),
        lineWidth: ReplicaMetrics.thinStroke))
  }
}
