import SwiftUI

struct SettingsView: View {
  @Environment(AppStore.self) private var store
  @State private var showResetConfirmation = false

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      ScrollView {
        LazyVStack(spacing: 28) {
          SettingsGroup(title: "Board") {
            SettingsToggle(
              title: "Cell borders",
              detail: "Draw a fine line between cells",
              isOn: binding(\.cellBorders),
              identifier: "settings.cellBorders"
            )
            SettingsToggle(
              title: "Show action toggle",
              detail: store.settings.longPressEnabled
                ? "Keep dig and flag control on the board"
                : "Required while long press is disabled",
              isOn: binding(\.showActionToggle),
              identifier: "settings.actionToggle",
              disabled: !store.settings.longPressEnabled
            )
            SettingsPicker(title: "Default action", selection: binding(\.primaryAction))
          }

          SettingsGroup(title: "Controls") {
            SettingsToggle(
              title: "Long press",
              detail: "Use the opposite of the selected action",
              isOn: binding(\.longPressEnabled),
              identifier: "settings.longPress"
            )
            SettingsSlider(
              title: "Long-press delay",
              value: binding(\.longPressDelayMilliseconds),
              range: 100...500,
              step: 25,
              formatted: { "\(Int($0)) ms" },
              disabled: !store.settings.longPressEnabled
            )
            SettingsToggle(
              title: "Easy digging",
              detail: "Tap a completed clue to reveal neighbors",
              isOn: binding(\.easyDigging),
              identifier: "settings.easyDigging"
            )
            SettingsToggle(
              title: "Easy flagging",
              detail: "Tap a satisfied clue to place flags",
              isOn: binding(\.easyFlagging),
              identifier: "settings.easyFlagging"
            )
          }

          SettingsGroup(title: "Feedback") {
            SettingsSlider(
              title: "Animation speed",
              value: binding(\.animationSpeed),
              range: 0...150,
              step: 5,
              formatted: { "\(Int($0))%" }
            )
            SettingsToggle(
              title: "Vibration",
              detail: "Haptic feedback for game actions",
              isOn: binding(\.vibrationEnabled),
              identifier: "settings.vibration"
            )
            SettingsSlider(
              title: "Vibration intensity",
              value: binding(\.vibrationDurationMilliseconds),
              range: 5...200,
              step: 5,
              formatted: { "\(Int($0)) ms" },
              disabled: !store.settings.vibrationEnabled
            )
          }

          Button("Reset to defaults", role: .destructive) { showResetConfirmation = true }
            .font(.rubik(14, weight: .medium))
            .foregroundStyle(theme.mine)
            .padding(.vertical, 14)
            .accessibilityIdentifier("settings.reset")
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 42)
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .replicaNavigationAppearance(theme: theme)
    .alert("Reset settings?", isPresented: $showResetConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Reset", role: .destructive) { store.resetSettings() }
    } message: {
      Text("All gameplay and feedback settings will return to their defaults.")
    }
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>) -> Binding<Value> {
    Binding(
      get: { store.settings[keyPath: keyPath] },
      set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } }
    )
  }
}

private struct SettingsGroup<Content: View>: View {
  @Environment(AppStore.self) private var store
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      SectionHeader(title: title, theme: store.theme)
        .padding(.bottom, 10)
      VStack(spacing: 0) {
        content
      }
    }
  }
}

private struct SettingsToggle: View {
  @Environment(AppStore.self) private var store
  let title: String
  let detail: String
  @Binding var isOn: Bool
  let identifier: String
  var disabled = false

  var body: some View {
    Toggle(isOn: $isOn) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.rubik(16, weight: .regular))
        Text(detail).font(.rubik(12)).foregroundStyle(store.theme.muted.opacity(0.84))
      }
    }
    .toggleStyle(.switch)
    .tint(store.theme.accent)
    .foregroundStyle(store.theme.foreground.opacity(0.84))
    .opacity(disabled ? 0.48 : 1)
    .padding(.vertical, 13)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(store.theme.muted.opacity(0.14))
        .frame(height: ReplicaMetrics.thinStroke)
    }
    .accessibilityIdentifier(identifier)
    .disabled(disabled)
  }
}

private struct SettingsPicker: View {
  @Environment(AppStore.self) private var store
  let title: String
  @Binding var selection: PrimaryAction

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.rubik(16, weight: .regular))
      HStack(spacing: 8) {
        ForEach(PrimaryAction.allCases) { action in
          Button {
            selection = action
            store.haptic(.selection)
          } label: {
            Label(action.title, systemImage: action.symbol)
              .font(.rubik(13, weight: .regular))
              .foregroundStyle(
                selection == action ? store.theme.background : store.theme.foreground
              )
              .frame(maxWidth: .infinity, minHeight: 38)
              .background(
                Capsule().fill(
                  selection == action
                    ? store.theme.foreground : store.theme.background.opacity(0.01))
              )
              .overlay(
                Capsule().stroke(
                  store.theme.foreground.opacity(0.45), lineWidth: selection == action ? 0 : 1))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .foregroundStyle(store.theme.foreground.opacity(0.84))
    .padding(.vertical, 13)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(store.theme.muted.opacity(0.14))
        .frame(height: ReplicaMetrics.thinStroke)
    }
  }
}

private struct SettingsSlider: View {
  @Environment(AppStore.self) private var store
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let formatted: (Double) -> String
  var disabled = false

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Text(title).font(.rubik(16, weight: .regular))
        Spacer()
        Text(formatted(value))
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(store.theme.muted)
      }
      Slider(value: $value, in: range, step: step)
        .tint(store.theme.accent)
    }
    .foregroundStyle(store.theme.foreground.opacity(0.84))
    .disabled(disabled)
    .opacity(disabled ? 0.48 : 1)
    .padding(.vertical, 13)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(store.theme.muted.opacity(0.14))
        .frame(height: ReplicaMetrics.thinStroke)
    }
  }
}
