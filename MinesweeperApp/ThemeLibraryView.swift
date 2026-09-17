import SwiftUI

struct ThemeLibraryView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var columns: [GridItem] {
    dynamicTypeSize.isAccessibilitySize
      ? [GridItem(.flexible())]
      : [GridItem(.adaptive(minimum: 148), spacing: 14)]
  }

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
            .accessibilityLabel(candidate.name)
            .accessibilityAddTraits(candidate.id == store.themeID ? .isSelected : [])
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let theme: AppTheme
  let selected: Bool

  var body: some View {
    HStack(spacing: 8) {
      ThemeSwatch(theme: theme, selected: selected, compact: true)
      Text(theme.name)
        .font(.rubik(13, weight: .regular))
        .foregroundStyle(theme.foreground.opacity(0.84))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "checkmark")
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(theme.accent)
        .frame(width: 13)
        .opacity(selected ? 1 : 0)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .contentShape(Rectangle())
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
