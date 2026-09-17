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
        // Use the active window, not the physical display. This keeps the
        // composition centered in iPad Split View and Stage Manager.
        let height = geometry.size.height
        let hasSavedGame = store.savedGames[store.selectedDifficulty] != nil
        let controlWidth = min(ReplicaMetrics.maxControlWidth, width - 72)
        // Keep the established tall-screen anchors, but let the controls flow
        // vertically on short screens so Resume cannot crowd the carousel.
        let preferredActionGap = height * (hasSavedGame ? 0.085 : 0.055)
          - (hasSavedGame ? 29 : 0) - 40
        let actionGap = max(12, preferredActionGap)
        let logoSize = min(144, max(96, height * 0.28 - 72))
        let controlsBottom = height * 0.445 + 20 + actionGap + (hasSavedGame ? 98 : 40)

        Button {
          store.navigation.append(.themes)
        } label: {
          PaletteIcon(
            color: theme.foreground.opacity(0.76),
            holeColor: theme.background
          )
            .frame(width: 27, height: 27)
        }
        .buttonStyle(RoundIconButtonStyle(theme: theme, size: 48))
        .accessibilityLabel("Themes")
        .accessibilityIdentifier("home.quickThemes")
        .position(x: width - 32, y: height * 0.083)

        MineLogo(theme: theme, size: logoSize)
          .accessibilityLabel("Minesweeper")
          .position(x: width / 2, y: height * 0.305)

        VStack(spacing: actionGap) {
          DifficultyCarousel(selection: $store.selectedDifficulty)
            .frame(height: 40)

          VStack(spacing: 18) {
            Button("New Game") { store.beginNewGame(for: store.selectedDifficulty) }
              .buttonStyle(AndroidPillButtonStyle(theme: theme, filled: true))
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
        }
        .frame(width: controlWidth)
        .frame(width: width)
        .padding(.top, height * 0.445 - 20)

        HomeActionBar()
          .frame(width: min(160, width - 110))
          .position(x: width / 2, y: max(height * 0.690, controlsBottom + 42))
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
        Image(systemName: "chevron.left")
          .font(.system(size: 31, weight: .light))
          .foregroundStyle(theme.foreground.opacity(0.54))
      }
      .buttonStyle(RoundIconButtonStyle(theme: theme, size: 44))
      .accessibilityLabel("Previous difficulty")
      .accessibilityIdentifier("home.previousDifficulty")

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
          .foregroundStyle(theme.foreground.opacity(0.54))
      }
      .buttonStyle(RoundIconButtonStyle(theme: theme, size: 44))
      .accessibilityLabel("Next difficulty")
      .accessibilityIdentifier("home.nextDifficulty")
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
      homeAction(asset: "FooterList", label: "Times") { store.navigation.append(.times) }
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
        .foregroundStyle(store.theme.foreground.opacity(0.72))
    }
    .buttonStyle(RoundIconButtonStyle(theme: store.theme, size: 48))
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
                  .frame(minWidth: 44, minHeight: 44)
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
        PaletteIcon(color: store.theme.foreground.opacity(0.90), holeColor: store.theme.background)
          .frame(width: 25, height: 25)
      }
      .buttonStyle(RoundIconButtonStyle(theme: store.theme, size: 44, filled: true))
      .accessibilityLabel(isExpanded ? "Close theme picker" : "Open theme picker")
    }
    .frame(height: 48)
    .padding(.leading, isExpanded ? 5 : 0)
    .padding(.trailing, 3)
    .background {
      if isExpanded { BoardControlSurface(theme: store.theme) }
    }
    .adaptiveGlassCapsule(
      theme: store.theme,
      emphasized: true,
      enabled: isExpanded,
      isInteractive: false
    )
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
