import SwiftUI

struct HomeView: View {
  @Environment(AppStore.self) private var store

  private var theme: AppTheme { store.theme }

  var body: some View {
    @Bindable var store = store
    ZStack {
      ReplicaBackground(theme: theme)
      GeometryReader { geometry in
        let width = geometry.size.width
        let height = UIScreen.main.bounds.height

        Button {
          store.navigation.append(.themes)
        } label: {
          PaletteIcon(
            color: theme.foreground.opacity(0.76),
            holeColor: theme.background
          )
            .frame(width: 27, height: 27)
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Themes")
        .accessibilityIdentifier("home.quickThemes")
        .position(x: width - 32, y: height * 0.083)

        MineLogo(theme: theme, size: 144)
          .accessibilityLabel("Minesweeper")
          .position(x: width / 2, y: height * 0.305)

        DifficultyCarousel(selection: $store.selectedDifficulty)
          .frame(width: min(ReplicaMetrics.maxControlWidth, width - 72), height: 40)
          .position(x: width / 2, y: height * 0.445)

        VStack(spacing: 18) {
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
        .frame(width: min(ReplicaMetrics.maxControlWidth, width - 72))
        .position(x: width / 2, y: height * (store.savedGames[store.selectedDifficulty] == nil ? 0.500 : 0.530))

        HomeActionBar()
          .frame(width: min(286, width - 76))
          .position(x: width / 2, y: height * 0.690)
      }
      .ignoresSafeArea()
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
            .font(.rubik(14, weight: .regular))
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
      homeAction(asset: "FooterSettings", label: "Settings") { store.navigation.append(.settings) }
      Spacer()
      homeAction(asset: "FooterCart", label: "Themes") { store.navigation.append(.themes) }
      Spacer()
      homeAction(asset: "FooterList", label: "Times") { store.navigation.append(.times) }
      Spacer()
      homeAction(asset: "FooterInfo", label: "About") { store.showAbout = true }
    }
  }

  private func homeAction(asset: String, label: String, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      Image(asset)
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .frame(width: 19, height: 19)
        .frame(width: 48, height: 48)
        .foregroundStyle(store.theme.foreground.opacity(0.72))
        .background {
          Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(store.theme.accent.opacity(0.045)))
            .overlay(
              Circle().stroke(
                Color.white.opacity(store.theme.isAMOLED ? 0.20 : 0.48), lineWidth: 0.8)
            )
        }
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
          HStack(spacing: 0) {
            ForEach(ThemeCatalog.quickDisplayOrder) { theme in
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
        PaletteIcon(color: store.theme.background, holeColor: store.theme.covered)
          .frame(width: 25, height: 25)
      }
      .buttonStyle(RoundIconButtonStyle(theme: store.theme, size: 43, filled: true))
      .accessibilityLabel(isExpanded ? "Close theme picker" : "Open theme picker")
    }
    .frame(height: 48)
    .padding(.leading, isExpanded ? 5 : 0)
    .padding(.trailing, 3)
    .background {
      if isExpanded {
        GlassCapsuleSurface(theme: store.theme, emphasized: true)
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
        .overlay(Circle().stroke(theme.foreground.opacity(0.10), lineWidth: 1))
      Circle()
        .fill(theme.accent)
        .frame(width: compact ? 14 : 20, height: compact ? 14 : 20)
      if selected {
        Circle()
          .fill(theme.accent)
        Circle()
          .fill(theme.background)
          .frame(width: compact ? 18 : 29, height: compact ? 18 : 29)
      }
    }
    .frame(width: compact ? 28 : 43, height: compact ? 28 : 43)
    .frame(width: compact ? 40 : 43, height: compact ? 40 : 43)
    .contentShape(Rectangle())
  }
}
