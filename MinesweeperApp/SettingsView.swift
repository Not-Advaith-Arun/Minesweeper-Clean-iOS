import SwiftUI

struct SettingsView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var showResetConfirmation = false

  var body: some View {
    let theme = store.theme
    VStack(spacing: 0) {
        ReplicaScreenHeader(title: "Settings", theme: theme) { dismiss() }
        ScrollView {
          LazyVStack(spacing: 0) {
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
          .padding(.top, 42)

          SettingsPicker(title: "Default action", selection: binding(\.primaryAction))
            .padding(.top, 42)

          SettingsToggle(
            title: "Long press",
            detail: "Use the opposite of the selected action",
            isOn: binding(\.longPressEnabled),
            identifier: "settings.longPress"
          )
          .padding(.top, 42)

          SettingsSlider(
            title: "Long-press delay",
            value: binding(\.longPressDelayMilliseconds),
            range: 100...500,
            step: 25,
            formatted: { "\(Int($0)) ms" },
            disabled: !store.settings.longPressEnabled
          )
          .padding(.top, 42)

          SettingsToggle(
            title: "Easy digging",
            detail: "Tap a completed clue to reveal neighbors",
            isOn: binding(\.easyDigging),
            identifier: "settings.easyDigging"
          )
          .padding(.top, 42)

          SettingsToggle(
            title: "Easy flagging",
            detail: "Tap a satisfied clue to place flags",
            isOn: binding(\.easyFlagging),
            identifier: "settings.easyFlagging"
          )
          .padding(.top, 42)

          SettingsSlider(
            title: "Animation speed",
            value: binding(\.animationSpeed),
            range: 0...150,
            step: 5,
            formatted: { "\(Int($0))%" }
          )
          .padding(.top, 42)

          SettingsToggle(
            title: "Vibration",
            detail: "Haptic feedback for game actions",
            isOn: binding(\.vibrationEnabled),
            identifier: "settings.vibration"
          )
          .padding(.top, 42)

          SettingsSlider(
            title: "Vibration intensity",
            value: binding(\.vibrationDurationMilliseconds),
            range: 5...200,
            step: 5,
            formatted: { "\(Int($0)) ms" },
            disabled: !store.settings.vibrationEnabled
          )
          .padding(.top, 42)

          Button("Reset to defaults", role: .destructive) { showResetConfirmation = true }
            .font(.rubik(14, weight: .medium))
            .foregroundStyle(theme.mine)
            .padding(.vertical, 14)
            .padding(.top, 42)
            .accessibilityIdentifier("settings.reset")
        }
          .padding(.horizontal, 30)
          .padding(.top, 22)
          .padding(.bottom, 42)
        }
    }
    .background(ReplicaBackground(theme: theme))
    .toolbar(.hidden, for: .navigationBar)
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
  }
}
