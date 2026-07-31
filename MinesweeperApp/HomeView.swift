import SwiftUI

struct HomeView: View {
  @Environment(AppStore.self) private var store

  private var theme: AppTheme { store.theme }

  var body: some View {
    @Bindable var store = store
    ZStack {
      ReplicaBackground(theme: theme)
      VStack(spacing: 0) {
        HStack {
          Spacer()
          Button {
            store.navigation.append(.themes)
          } label: {
            Image(systemName: "paintpalette.fill")
              .font(.system(size: 27, weight: .regular))
              .foregroundStyle(theme.foreground.opacity(0.76))
              .frame(width: 48, height: 48)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Themes")
          .accessibilityIdentifier("home.quickThemes")
        }
        .padding(.horizontal, 25)
        .padding(.top, 42)

        Spacer(minLength: 80)

        MineLogo(theme: theme, size: 154)
          .accessibilityLabel("Minesweeper")

        Spacer(minLength: 42)

        DifficultyCarousel(selection: $store.selectedDifficulty)
          .frame(height: 44)
          .frame(maxWidth: ReplicaMetrics.maxControlWidth)

        VStack(spacing: 22) {
          Button("New Game") { store.beginNewGame(for: store.selectedDifficulty) }
            .buttonStyle(AndroidPillButtonStyle(theme: theme))
            .disabled(!store.persistenceReady)
            .opacity(store.persistenceReady ? 1 : 0.62)
            .accessibilityIdentifier("home.newGame")

          if let saved = store.savedGames[store.selectedDifficulty] {
            Button {
              store.resume(store.selectedDifficulty)
            } label: {
              HStack(spacing: 8) {
                Text("Resume")
                Text(saved.elapsedSeconds.clockString)
                  .monospacedDigit()
                  .font(.rubik(16, weight: .regular))
                  .foregroundStyle(theme.muted.opacity(0.72))
              }
            }
            .buttonStyle(AndroidPillButtonStyle(theme: theme))
            .accessibilityIdentifier("home.resume")
          }
        }
        .frame(maxWidth: ReplicaMetrics.maxControlWidth)
        .padding(.top, 10)
        .padding(.horizontal, ReplicaMetrics.horizontalInset)

        Spacer(minLength: 48)

        HomeActionBar()
          .padding(.horizontal, 58)
          .padding(.bottom, 46)
      }
    }
    .foregroundStyle(theme.foreground.opacity(0.78))
    .toolbar(.hidden, for: .navigationBar)
    .alert("Start a new game?", isPresented: $store.showReplacementWarning) {
      Button("Cancel", role: .cancel) { store.pendingDifficulty = nil }
      Button("Replace", role: .destructive) { store.confirmReplacement() }
    } message: {
      Text("Your unfinished \(store.pendingDifficulty?.title ?? "") game will be replaced.")
    }
  }
}

private struct DifficultyCarousel: View {
  @Environment(AppStore.self) private var store
  @Binding var selection: ReplicaDifficulty

  var body: some View {
    let theme = store.theme
    HStack(spacing: 14) {
      Button {
        move(-1)
      } label: {
        Image(systemName: "chevron.left").frame(width: 34, height: 34)
      }
      .buttonStyle(.plain)
      .opacity(0)
      .accessibilityHidden(true)

      TabView(selection: $selection) {
        ForEach(ReplicaDifficulty.allCases) { difficulty in
          Text(difficulty.title)
            .font(.rubik(20, weight: .regular))
            .foregroundStyle(theme.foreground.opacity(0.78))
            .tag(difficulty)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(maxWidth: 168)

      Button {
        move(1)
      } label: {
        Image(systemName: "chevron.right")
          .font(.system(size: 31, weight: .light))
          .frame(width: 44, height: 44)
          .foregroundStyle(theme.foreground.opacity(0.54))
      }
      .buttonStyle(.plain)
    }
    .foregroundStyle(theme.foreground.opacity(0.78))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Difficulty: \(selection.title), \(selection.size.columns) by \(selection.size.rows), \(selection.size.mines) mines"
    )
    .accessibilityIdentifier("home.difficulty")
  }

  private func move(_ offset: Int) {
    guard let index = ReplicaDifficulty.allCases.firstIndex(of: selection) else { return }
    let count = ReplicaDifficulty.allCases.count
    withAnimation(ReplicaMotion.standard(speedPercent: store.settings.animationSpeed)) {
      selection = ReplicaDifficulty.allCases[(index + offset + count) % count]
    }
    store.haptic(.selection)
  }
}

private struct HomeActionBar: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    HStack {
      homeAction(symbol: "gearshape", label: "Settings") { store.navigation.append(.settings) }
      Spacer()
      homeAction(symbol: "bag", label: "Themes") { store.navigation.append(.themes) }
      Spacer()
      homeAction(symbol: "list.bullet", label: "Times") { store.navigation.append(.times) }
      Spacer()
      homeAction(symbol: "info.circle", label: "About") { store.showAbout = true }
    }
  }

  private func homeAction(symbol: String, label: String, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 28, weight: .regular))
        .frame(width: 48, height: 48)
        .foregroundStyle(store.theme.foreground.opacity(0.72))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityIdentifier("home.\(label.lowercased())")
  }
}

struct QuickThemeBar: View {
  @Environment(AppStore.self) private var store
  @Binding var isExpanded: Bool

  var body: some View {
    HStack(spacing: 9) {
      if isExpanded {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 13) {
            ForEach(ThemeCatalog.all) { theme in
              Button {
                store.chooseTheme(theme)
              } label: {
                ThemeSwatch(theme: theme, selected: theme.id == store.themeID, compact: true)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(theme.name)
              .accessibilityAddTraits(theme.id == store.themeID ? .isSelected : [])
            }
          }
          .padding(.horizontal, 7)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
      } else {
        Spacer(minLength: 0)
      }

      Button {
        withAnimation(ReplicaMotion.spring(speedPercent: store.settings.animationSpeed)) {
          isExpanded.toggle()
        }
      } label: {
        Image(systemName: isExpanded ? "xmark" : "paintpalette.fill")
      }
      .buttonStyle(RoundIconButtonStyle(theme: store.theme, size: 43, filled: true))
      .accessibilityLabel(isExpanded ? "Close theme picker" : "Open theme picker")
    }
    .frame(height: 48)
    .padding(.leading, isExpanded ? 5 : 0)
    .padding(.trailing, 3)
    .background {
      if isExpanded {
        Capsule(style: .continuous)
          .fill(store.theme.surface.opacity(0.86))
          .overlay(Capsule().stroke(store.theme.muted.opacity(0.4), lineWidth: 1))
      }
    }
  }
}

struct ThemeSwatch: View {
  let theme: AppTheme
  let selected: Bool
  var compact = false

  var body: some View {
    ZStack {
      Circle()
        .fill(theme.background)
        .overlay(alignment: .bottomTrailing) {
          Circle().fill(theme.accent).frame(width: compact ? 14 : 20)
        }
      Circle()
        .stroke(
          selected ? theme.accent : theme.foreground.opacity(0.18), lineWidth: selected ? 3 : 1
        )
        .padding(selected ? -3 : 0)
    }
    .frame(width: compact ? 25 : 43, height: compact ? 25 : 43)
  }
}
