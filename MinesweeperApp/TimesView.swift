import SwiftUI

struct TimesView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var difficulty: ReplicaDifficulty = .medium
  @State private var pendingDeletion: ReplicaTimeRecord?

  var body: some View {
    let theme = store.theme
    VStack(spacing: 20) {
        ReplicaScreenHeader(title: "Top times", theme: theme) { dismiss() }

        TimesDifficultySelector(selection: $difficulty)
          .padding(.top, 8)

        let records = store.records(for: difficulty)
        if records.isEmpty {
          if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
              emptyState
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
          } else {
            Spacer()
            emptyState
            Spacer()
          }
        } else {
          List {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
              TimeRow(rank: index + 1, record: record)
                .listRowBackground(theme.background)
                .listRowSeparatorTint(theme.muted.opacity(0.14))
                .swipeActions {
                  Button(role: .destructive) {
                    pendingDeletion = record
                  } label: {
                    Label("Delete", systemImage: "trash")
                  }
                }
            }
          }
          .scrollContentBackground(.hidden)
          .listStyle(.plain)
          .padding(.horizontal, 14)
          .frame(maxWidth: 680)
          .frame(maxWidth: .infinity)
        }
    }
    .background(ReplicaBackground(theme: theme))
    .toolbar(.hidden, for: .navigationBar)
    .alert("Delete this time?", isPresented: deletionAlert) {
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
      Button("Delete", role: .destructive) {
        if let pendingDeletion { store.deleteRecord(id: pendingDeletion.id) }
        pendingDeletion = nil
      }
    } message: {
      Text("Are you sure you want to delete this time?")
    }
  }

  private var emptyState: some View {
    VStack(spacing: 14) {
      Image(systemName: "stopwatch")
        .font(.system(size: 42, weight: .ultraLight))
        .foregroundStyle(store.theme.foreground.opacity(0.54))
      Text("No times yet.")
        .font(.rubik(20, weight: .regular))
      Text("Complete a \(difficulty.title.lowercased()) game to set your first time.")
        .font(.rubik(13))
        .foregroundStyle(store.theme.muted.opacity(0.84))
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .foregroundStyle(store.theme.foreground.opacity(0.78))
    .padding(.horizontal, 42)
  }

  private var deletionAlert: Binding<Bool> {
    Binding(
      get: { pendingDeletion != nil },
      set: { if !$0 { pendingDeletion = nil } }
    )
  }
}

private struct TimesDifficultySelector: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var selection: ReplicaDifficulty

  var body: some View {
    HStack(spacing: 18) {
      arrow("chevron.left", offset: -1)
      Text(selection.title)
        .font(.rubik(14, weight: .regular))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 150)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
      arrow("chevron.right", offset: 1)
    }
    .foregroundStyle(store.theme.foreground.opacity(0.82))
    .frame(minHeight: 44)
    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 24 : 0)
    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 480 : nil)
  }

  private func arrow(_ symbol: String, offset: Int) -> some View {
    Button {
      guard let index = ReplicaDifficulty.allCases.firstIndex(of: selection) else { return }
      let count = ReplicaDifficulty.allCases.count
      withAnimation(ReplicaMotion.standard(speedPercent: store.settings.animationSpeed)) {
        selection = ReplicaDifficulty.allCases[(index + offset + count) % count]
      }
      store.haptic(.selection)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 19, weight: .regular))
    }
    .buttonStyle(RoundIconButtonStyle(theme: store.theme, size: 44))
    .accessibilityLabel(offset < 0 ? "Previous difficulty" : "Next difficulty")
    .accessibilityIdentifier(offset < 0 ? "times.previousDifficulty" : "times.nextDifficulty")
  }
}

private struct TimeRow: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var durationFontSize = 20.0
  let rank: Int
  let record: ReplicaTimeRecord

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM yyyy"
    return formatter
  }()

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          Text("\(rank).")
            .font(.rubik(13, weight: .regular))
            .foregroundStyle(store.theme.muted)
          duration
          date
        }
        .fixedSize(horizontal: false, vertical: true)
      } else {
        HStack(spacing: 14) {
          Text("\(rank)")
            .font(.rubik(13, weight: .regular))
            .foregroundStyle(store.theme.muted)
            .frame(width: 25)
          duration
          Spacer()
          date
        }
      }
    }
    .padding(.vertical, 11)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("times.record.\(record.id.uuidString)")
  }

  private var duration: some View {
    Text(record.seconds.androidDurationString)
      .font(.system(size: durationFontSize, weight: .regular, design: .monospaced))
      .foregroundStyle(store.theme.foreground.opacity(0.82))
  }

  private var date: some View {
    Text(Self.dateFormatter.string(from: record.date))
      .font(.rubik(11))
      .foregroundStyle(store.theme.muted.opacity(0.84))
  }
}
