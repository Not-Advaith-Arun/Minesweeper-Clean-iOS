import SwiftUI

@MainActor
struct GameView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var session: GameSessionController
  @State private var paletteExpanded = false
  @State private var showResult = false
  @State private var showEndControls = false
  @State private var showActionToggle = false
  @State private var restartTask: Task<Void, Never>?

  let difficulty: ReplicaDifficulty

  init(difficulty: ReplicaDifficulty, resume: Bool) {
    self.difficulty = difficulty
    _session = State(
      initialValue: GameSessionController(
        difficulty: difficulty, resume: resume, settings: .default))
  }

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      BoardRenderer(
        board: session.board,
        phase: session.phase,
        isLoading: session.isLoading,
        changedCoordinates: session.lastChangedCoordinates,
        actionCoordinate: session.lastActionCoordinate,
        theme: theme,
        showsBorders: store.settings.cellBorders,
        animationSpeed: reduceMotion ? 0 : store.settings.animationSpeed,
        longPressEnabled: store.settings.longPressEnabled,
        longPressDuration: store.settings.longPressDelayMilliseconds / 1_000,
        onTap: { column, row in
          session.primaryAction(column: column, row: row)
        },
        onLongPress: { column, row in
          session.secondaryAction(column: column, row: row)
        }
      )
      .ignoresSafeArea()
      .accessibilityLabel("\(difficulty.title) minesweeper board")
      .accessibilityIdentifier("game.board")

      GameStatusBar(
        session: session,
        paletteExpanded: $paletteExpanded,
        onClose: { leaveGame() }
      )

      if session.phase.isFinished, showEndControls, !showResult {
        GeometryReader { geometry in
          VStack(spacing: 0) {
            Spacer(minLength: 0)
            EndGameControls(
              currentDifficulty: difficulty,
              regionHeight: max(140, geometry.size.height * 0.25),
              onRestart: startNewGame
            )
          }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      } else if session.phase == .playing && showActionToggle
        && (store.settings.showActionToggle || !store.settings.longPressEnabled)
      {
        VStack {
          Spacer()
          ActionToggle(session: session)
        }
        .padding(.bottom, 10)
        // The Android control sits low on tall displays, but the same fixed
        // offset clips the capsule on compact 667-point iPhones.
        .offset(y: UIScreen.main.bounds.height < 750 ? 0 : 34)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
      }

      if showResult, session.phase == .won {
        Color.black.opacity(0.32).ignoresSafeArea()
          .transition(.opacity)
        ResultCard(
          session: session,
          onDismiss: {
            withAnimation(ReplicaMotion.dialogDismiss(speedPercent: store.settings.animationSpeed)) {
              showResult = false
            }
          }
        )
        .padding(24)
        .transition(
          .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .scale(scale: 0.98).combined(with: .opacity)
          )
        )
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .onAppear {
      session.updateSettings(store.settings)
      session.resumeTimerIfNeeded()
      if session.phase.isFinished { showEndControls = true }
      showActionToggle = session.phase == .playing
#if DEBUG
      if session.phase == .won,
        ProcessInfo.processInfo.environment["MINESWEEPER_UI_TEST_GAME_STATE"] == "won"
      {
        showResult = true
      }
#endif
    }
    .onChange(of: store.settings) { _, revised in session.updateSettings(revised) }
    .onChange(of: session.feedbackSequence) { _, _ in
      store.haptic(session.feedbackAction == .dig ? .reveal : .flag)
    }
    .onChange(of: session.phase) { previous, current in
      if current == .ready || current.isFinished {
        showActionToggle = false
      } else if current == .playing, previous == .ready {
        let delay = !reduceMotion && store.settings.animationSpeed > 0
          ? 0.78 * 100 / store.settings.animationSpeed : 0
        guard delay > 0 else {
          showActionToggle = true
          return
        }
        Task {
          try? await Task.sleep(for: .seconds(delay))
          guard session.phase == .playing else { return }
          withAnimation(ReplicaMotion.standard(speedPercent: store.settings.animationSpeed)) {
            showActionToggle = true
          }
        }
      } else if current == .playing {
        showActionToggle = true
      }
    }
    .onChange(of: session.phase) { previous, current in
      guard previous != current, current.isFinished else { return }
      if current == .won, let record = session.completionRecord {
        store.addRecord(record)
        store.haptic(.success)
      } else if current == .lost {
        store.haptic(.warning)
      }
      store.clearSavedGame(difficulty)
      showEndControls = false
      showResult = false
      let baseDelay = current == .won ? 0.70 : 0.72
      let delay = !reduceMotion && store.settings.animationSpeed > 0
        ? baseDelay * 100 / store.settings.animationSpeed : 0
      Task {
        try? await Task.sleep(for: .seconds(delay))
        guard session.phase == current else { return }
        withAnimation(ReplicaMotion.standard(speedPercent: store.settings.animationSpeed)) {
          showEndControls = true
        }
        if current == .won {
          withAnimation(ReplicaMotion.dialogPresent(speedPercent: store.settings.animationSpeed)) {
            showResult = true
          }
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        session.resumeTimerIfNeeded()
      case .inactive, .background:
        session.saveIfNeeded()
        store.registerSavedGame(session.savedSummary)
      @unknown default:
        break
      }
    }
    .onDisappear {
      restartTask?.cancel()
      session.saveIfNeeded()
      store.registerSavedGame(session.savedSummary)
    }
    .alert("Unable to continue", isPresented: errorBinding) {
      Button("OK") { session.dismissError() }
    } message: {
      Text(session.errorMessage ?? "An unexpected error occurred.")
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { session.errorMessage != nil },
      set: { if !$0 { session.dismissError() } }
    )
  }

  private func leaveGame() {
    session.saveIfNeeded()
    store.registerSavedGame(session.savedSummary)
    dismiss()
  }

  private func startNewGame(_ selected: ReplicaDifficulty) {
    restartTask?.cancel()
    showResult = false
    withAnimation(ReplicaMotion.dialogDismiss(speedPercent: store.settings.animationSpeed)) {
      showEndControls = false
    }

    let delay = !reduceMotion && store.settings.animationSpeed > 0
      ? 0.20 * 100 / store.settings.animationSpeed : 0
    restartTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      if selected == difficulty {
        session.restart()
      } else {
        store.replaceCurrentGame(with: selected)
      }
    }
  }
}

@MainActor
private struct GameStatusBar: View {
  @Environment(AppStore.self) private var store
  let session: GameSessionController
  @Binding var paletteExpanded: Bool
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        HStack {
          Button(action: onClose) {
            BackArrowIcon(color: store.theme.foreground.opacity(0.82))
              .frame(width: 54, height: 54)
              .background {
                Circle()
                  .fill(.ultraThinMaterial)
                  .overlay(Circle().fill(store.theme.accent.opacity(0.045)))
                  .overlay(Circle().stroke(Color.white.opacity(store.theme.isAMOLED ? 0.18 : 0.42), lineWidth: 0.8))
                  .frame(width: 46, height: 46)
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Back")
          .accessibilityIdentifier("game.back")

          Spacer()

          Button {
            withAnimation(ReplicaMotion.spring(speedPercent: store.settings.animationSpeed)) {
              paletteExpanded.toggle()
            }
          } label: {
            PaletteIcon(
              color: store.theme.foreground.opacity(0.82),
              holeColor: store.theme.background
            )
              .frame(width: 27, height: 27)
              .frame(width: 56, height: 56)
              .background {
                Circle()
                  .fill(.ultraThinMaterial)
                  .overlay(Circle().fill(store.theme.accent.opacity(0.045)))
                  .overlay(Circle().stroke(Color.white.opacity(store.theme.isAMOLED ? 0.18 : 0.42), lineWidth: 0.8))
                  .frame(width: 46, height: 46)
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Theme picker")
        }
        .padding(.horizontal, 1)
        .padding(.top, 9)
        .opacity(paletteExpanded ? 0 : 1)
        .accessibilityHidden(paletteExpanded)

        VStack(spacing: 1) {
          if session.phase.isFinished {
            Text(gameTimeString(session.elapsedSeconds))
              .font(.rubik(14, weight: .regular))
              .monospacedDigit()
              .frame(height: 45)
              .accessibilityIdentifier("game.timer")
          } else {
            HStack(spacing: 3) {
              MineLogo(theme: store.theme, size: 19, tint: store.theme.foreground)
              Text("\(session.remainingMineCount)")
                .font(.rubik(14, weight: .medium))
                .monospacedDigit()
                .accessibilityIdentifier("game.mines")
            }
            .frame(height: 27)

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
              Text(session.elapsedSeconds == 0 ? "" : gameTimeString(session.elapsedSeconds))
                .font(.rubik(12, weight: .regular))
                .monospacedDigit()
                .accessibilityIdentifier("game.timer")
            }
            .frame(height: 18)
          }
        }
        .padding(.top, 14)
        .opacity(session.phase == .ready ? 0.42 : 1)
        .opacity(paletteExpanded ? 0 : 1)
        .accessibilityHidden(paletteExpanded)

        if paletteExpanded {
          QuickThemeBar(isExpanded: $paletteExpanded)
            .padding(.horizontal, 8)
            .padding(.top, 9)
            .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
        }
      }
      .frame(height: 76)

      Spacer()
    }
    .foregroundStyle(store.theme.foreground)
    .ignoresSafeArea(edges: .bottom)
  }

  private func gameTimeString(_ seconds: Int) -> String {
    seconds.androidDurationString
  }
}

@MainActor
private struct ActionToggle: View {
  @Environment(AppStore.self) private var store
  let session: GameSessionController

  var body: some View {
    HStack(spacing: 8) {
      actionButton(.dig)
      actionButton(.flag)
    }
    .padding(6)
    .background(GlassCapsuleSurface(theme: store.theme, emphasized: true))
    .accessibilityIdentifier("game.actionToggle")
  }

  private func actionButton(_ mode: PrimaryAction) -> some View {
    Button {
      if session.actionMode != mode {
        session.setActionMode(mode)
        store.haptic(.selection)
      }
    } label: {
      Group {
        if mode == .dig {
          MineLogo(
            theme: store.theme,
            size: 20,
            tint: session.actionMode == mode ? store.theme.background : store.theme.foreground,
            holeTint: session.actionMode == mode ? store.theme.covered : store.theme.background
          )
        } else {
          FlagIcon(
            color: session.actionMode == mode ? store.theme.background : store.theme.foreground
          )
          .frame(width: 20, height: 20)
        }
      }
        .frame(width: 46, height: 46)
        .background {
          if session.actionMode == mode {
            Circle().fill(store.theme.covered)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(mode.title)
    .accessibilityAddTraits(session.actionMode == mode ? .isSelected : [])
  }
}

@MainActor
private struct EndGameControls: View {
  @Environment(AppStore.self) private var store
  @State private var selection: ReplicaDifficulty
  let regionHeight: CGFloat
  let onRestart: (ReplicaDifficulty) -> Void

  init(
    currentDifficulty: ReplicaDifficulty,
    regionHeight: CGFloat,
    onRestart: @escaping (ReplicaDifficulty) -> Void
  ) {
    _selection = State(initialValue: currentDifficulty)
    self.regionHeight = regionHeight
    self.onRestart = onRestart
  }

  var body: some View {
    VStack(spacing: 10) {
      Button("Start new game") { onRestart(selection) }
        .buttonStyle(AndroidPillButtonStyle(theme: store.theme))
        .accessibilityIdentifier("game.startNew")

      HStack {
        difficultyArrow("chevron.left", offset: -1)
        Text(selection.title)
          .font(.rubik(14, weight: .medium))
          .frame(maxWidth: .infinity)
          .accessibilityIdentifier("game.endDifficulty")
        difficultyArrow("chevron.right", offset: 1)
      }
      .frame(height: 40)
    }
    .foregroundStyle(store.theme.foreground.opacity(0.84))
    .padding(.horizontal, 50)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, minHeight: regionHeight, alignment: .bottom)
    .background {
      LinearGradient(
        colors: [store.theme.background.opacity(0), store.theme.background.opacity(0.92)],
        startPoint: .top,
        endPoint: .center
      )
      .background(.ultraThinMaterial.opacity(0.38))
    }
  }

  private func difficultyArrow(_ symbol: String, offset: Int) -> some View {
    Button {
      guard let index = ReplicaDifficulty.allCases.firstIndex(of: selection) else { return }
      let count = ReplicaDifficulty.allCases.count
      withAnimation(ReplicaMotion.standard(speedPercent: store.settings.animationSpeed)) {
        selection = ReplicaDifficulty.allCases[(index + offset + count) % count]
      }
      store.haptic(.selection)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .regular))
        .frame(width: 44, height: 44)
    }
    .buttonStyle(.plain)
  }
}

@MainActor
private struct ResultCard: View {
  @Environment(AppStore.self) private var store
  let session: GameSessionController
  let onDismiss: () -> Void

  private var title: String {
    let options = ["Neat!", "Clean sweep!", "Perfect!", "Nicely done!", "All clear!"]
    return options[session.elapsedSeconds % options.count]
  }

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 5) {
        Text(title)
          .font(.rubik(23, weight: .semibold))
        Text("Difficulty: \(session.difficulty.title)")
          .font(.rubik(13, weight: .regular))
          .foregroundStyle(store.theme.muted)
      }

      let best = Array(store.records(for: session.difficulty).prefix(10))
      if !best.isEmpty {
        VStack(spacing: 2) {
          ForEach(Array(best.enumerated()), id: \.element.id) { index, record in
            HStack(spacing: 8) {
              Text("\(index + 1).")
              Text(Self.dateFormatter.string(from: record.date))
              Spacer()
              Text(record.seconds.androidDurationString).monospacedDigit()
            }
            .font(.rubik(12, weight: .regular))
            .foregroundStyle(
              record.id == session.completionRecord?.id
                ? store.theme.background
                : store.theme.foreground.opacity(0.84)
            )
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(
              record.id == session.completionRecord?.id
                ? store.theme.covered : Color.clear
            )
          }
        }
      }

      Button("Got it!", action: onDismiss)
        .buttonStyle(AndroidPillButtonStyle(theme: store.theme))
        .accessibilityIdentifier("game.dismissResult")
    }
    .foregroundStyle(store.theme.foreground)
    .padding(20)
    .frame(maxWidth: 360)
    .background(GlassRoundedSurface(theme: store.theme, cornerRadius: 9, emphasized: true))
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM yyyy"
    return formatter
  }()
}
