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

          SettingsSlider(
            title: "Animation speed",
            value: binding(\.animationSpeed),
            range: 0...200,
            step: 5,
            formatted: { $0 == 0 ? "Off" : "\(Int($0))%" },
            identifier: "settings.animationSpeed"
          )
          .padding(.top, 42)

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
            .buttonStyle(GlassDestructivePillButtonStyle(theme: theme))
            .padding(.top, 42)
            .accessibilityIdentifier("settings.reset")
        }
          .padding(.horizontal, 30)
          .padding(.top, 22)
          .padding(.bottom, 42)
          .frame(maxWidth: 620)
          .frame(maxWidth: .infinity)
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
      .fixedSize(horizontal: false, vertical: true)
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: String
  @Binding var selection: PrimaryAction

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.rubik(16, weight: .regular))
        .fixedSize(horizontal: false, vertical: true)
      let layout = dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
      layout {
        ForEach(PrimaryAction.allCases) { action in
          Button {
            selection = action
            store.haptic(.selection)
          } label: {
            Label(action.title, systemImage: action.symbol)
              .font(.rubik(13, weight: .regular))
              .foregroundStyle(
                store.theme.foreground.opacity(selection == action ? 1 : 0.76)
              )
              .fixedSize(horizontal: false, vertical: true)
              .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
              .padding(.horizontal, 12)
              .frame(maxWidth: .infinity, minHeight: 44)
              .contentShape(Rectangle())
              .background {
                Capsule(style: .continuous)
                  .fill(
                    selection == action
                      ? store.theme.covered.opacity(0.32)
                      : store.theme.accent.opacity(0.025)
                  )
              }
              .adaptiveGlassCapsule(
                theme: store.theme,
                emphasized: selection == action
              )
              .overlay {
                Capsule(style: .continuous)
                  .stroke(
                    selection == action ? store.theme.accent.opacity(0.64) : .clear,
                    lineWidth: 1
                  )
              }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selection == action ? .isSelected : [])
          .accessibilityIdentifier("settings.primaryAction.\(action.rawValue)")
        }
      }
    }
    .foregroundStyle(store.theme.foreground.opacity(0.84))
  }
}

private struct SettingsSlider: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var valueFontSize = 12.0
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let formatted: (Double) -> String
  var identifier: String? = nil
  var disabled = false

  var body: some View {
    VStack(spacing: 6) {
      let layout = dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        : AnyLayout(HStackLayout())
      layout {
        Text(title)
          .font(.rubik(16, weight: .regular))
          .fixedSize(horizontal: false, vertical: true)
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Text(formatted(value))
          .font(.system(size: valueFontSize, weight: .medium, design: .monospaced))
          .foregroundStyle(store.theme.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Slider(value: $value, in: range, step: step)
        .tint(store.theme.accent)
        .accessibilityLabel(title)
        .accessibilityValue(formatted(value))
        .accessibilityIdentifier(identifier ?? "settings.slider.\(title)")
    }
    .foregroundStyle(store.theme.foreground.opacity(0.84))
    .disabled(disabled)
    .opacity(disabled ? 0.48 : 1)
  }
}
