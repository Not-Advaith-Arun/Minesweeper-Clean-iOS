import SwiftUI

@MainActor
struct GameView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var session: GameSessionController
  @State private var paletteExpanded = false
  @State private var showResult = false

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

      if store.settings.showActionToggle || !store.settings.longPressEnabled {
        VStack {
          Spacer()
          ActionToggle(session: session)
        }
        .padding(.bottom, 20)
      }

      if showResult, session.phase.isFinished {
        Color.black.opacity(0.32).ignoresSafeArea()
          .transition(.opacity)
        ResultCard(
          session: session,
          onRestart: {
            showResult = false
            session.restart()
          },
          onHome: { dismiss() }
        )
        .padding(24)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      session.updateSettings(store.settings)
      session.resumeTimerIfNeeded()
    }
    .onChange(of: store.settings) { _, revised in session.updateSettings(revised) }
    .onChange(of: session.feedbackSequence) { _, _ in
      store.haptic(session.feedbackAction == .dig ? .reveal : .flag)
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
      withAnimation(ReplicaMotion.spring(speedPercent: store.settings.animationSpeed)) {
        showResult = true
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
            Image(systemName: "chevron.left")
              .font(.system(size: 32, weight: .regular))
              .frame(width: 54, height: 54)
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
            Image(systemName: "paintpalette.fill")
              .font(.system(size: 29, weight: .semibold))
              .frame(width: 56, height: 56)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Theme picker")
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)

        VStack(spacing: 1) {
          HStack(spacing: 6) {
            MineLogo(theme: store.theme, size: 23)
            Text("\(session.remainingMineCount)")
              .font(.rubik(18, weight: .regular))
              .monospacedDigit()
              .accessibilityIdentifier("game.mines")
          }
          .frame(height: 27)

          TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(session.elapsedSeconds == 0 ? "" : gameTimeString(session.elapsedSeconds))
              .font(.rubik(14, weight: .regular))
              .monospacedDigit()
              .accessibilityIdentifier("game.timer")
          }
          .frame(height: 18)
        }
        .padding(.top, 14)
      }
      .frame(height: 76)

      if paletteExpanded {
        QuickThemeBar(isExpanded: $paletteExpanded)
          .padding(.horizontal, 12)
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      Spacer()
    }
    .foregroundStyle(store.theme.foreground)
    .ignoresSafeArea(edges: .bottom)
  }

  private func gameTimeString(_ seconds: Int) -> String {
    seconds < 60 ? "\(seconds)S" : seconds.clockString
  }
}

@MainActor
private struct ActionToggle: View {
  @Environment(AppStore.self) private var store
  let session: GameSessionController

  var body: some View {
    HStack(spacing: 0) {
      actionButton(.dig)
      actionButton(.flag)
    }
    .padding(5)
    .background(
      Capsule(style: .continuous)
        .fill(store.theme.background.opacity(0.94))
        .overlay(Capsule().stroke(store.theme.separator.opacity(0.9), lineWidth: 1))
    )
    .accessibilityIdentifier("game.actionToggle")
  }

  private func actionButton(_ mode: PrimaryAction) -> some View {
    Button {
      if session.actionMode != mode {
        session.setActionMode(mode)
        store.haptic(.selection)
      }
    } label: {
      Image(systemName: mode == .dig ? "gearshape.fill" : "flag.fill")
        .font(.system(size: 25, weight: .semibold))
        .frame(width: 52, height: 52)
        .foregroundStyle(session.actionMode == mode ? store.theme.background : store.theme.foreground)
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
private struct ResultCard: View {
  @Environment(AppStore.self) private var store
  let session: GameSessionController
  let onRestart: () -> Void
  let onHome: () -> Void

  private var title: String {
    if session.phase == .lost { return "Mine found" }
    let options = ["Clean sweep!", "Perfect!", "Nicely done!", "All clear!"]
    return options[session.elapsedSeconds % options.count]
  }

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: session.phase == .won ? "sparkles" : "burst.fill")
        .font(.system(size: 31, weight: .medium))
        .foregroundStyle(session.phase == .won ? store.theme.accent : store.theme.mine)

      VStack(spacing: 5) {
        Text(title)
          .font(.rubik(23, weight: .semibold))
        Text(session.phase == .won ? session.elapsedSeconds.clockString : "Try a fresh board")
          .font(.system(size: 14, weight: .medium, design: .monospaced))
          .foregroundStyle(store.theme.muted)
      }

      if session.phase == .won {
        let best = Array(store.records(for: session.difficulty).prefix(5))
        if !best.isEmpty {
          VStack(spacing: 6) {
            SectionHeader(title: "Best times", theme: store.theme)
            ForEach(Array(best.enumerated()), id: \.element.id) { index, record in
              HStack {
                Text("\(index + 1)").foregroundStyle(store.theme.muted)
                Text(record.seconds.clockString).monospacedDigit()
                Spacer()
                if record.id == session.completionRecord?.id {
                  Text("NEW").font(.rubik(9, weight: .bold))
                    .foregroundStyle(store.theme.accent)
                }
              }
              .font(.rubik(12, weight: .medium))
            }
          }
          .padding(12)
          .background(RoundedRectangle(cornerRadius: 13).fill(store.theme.background))
        }
      }

      HStack(spacing: 10) {
        Button("Home", action: onHome)
          .buttonStyle(CleanButtonStyle(theme: store.theme))
        Button("Play again", action: onRestart)
          .buttonStyle(CleanButtonStyle(theme: store.theme, filled: true))
      }
    }
    .foregroundStyle(store.theme.foreground)
    .padding(22)
    .frame(maxWidth: 360)
    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(store.theme.surface))
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(
        store.theme.muted.opacity(0.25), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.22), radius: 26, y: 12)
  }
}
