import SwiftUI

struct TimesView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
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
          Spacer()
          VStack(spacing: 14) {
            Image(systemName: "stopwatch")
              .font(.system(size: 42, weight: .ultraLight))
              .foregroundStyle(theme.foreground.opacity(0.54))
            Text("No times yet.")
              .font(.rubik(20, weight: .regular))
            Text("Complete a \(difficulty.title.lowercased()) game to set your first time.")
              .font(.rubik(13))
              .foregroundStyle(theme.muted.opacity(0.84))
              .multilineTextAlignment(.center)
          }
          .foregroundStyle(theme.foreground.opacity(0.78))
          .padding(.horizontal, 42)
          Spacer()
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

  private var deletionAlert: Binding<Bool> {
    Binding(
      get: { pendingDeletion != nil },
      set: { if !$0 { pendingDeletion = nil } }
    )
  }
}

private struct TimesDifficultySelector: View {
  @Environment(AppStore.self) private var store
  @Binding var selection: ReplicaDifficulty

  var body: some View {
    HStack(spacing: 18) {
      arrow("chevron.left", offset: -1)
      Text(selection.title)
        .font(.rubik(14, weight: .regular))
      .frame(width: 150)
      arrow("chevron.right", offset: 1)
    }
    .foregroundStyle(store.theme.foreground.opacity(0.82))
    .frame(height: 44)
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
  }
}

private struct TimeRow: View {
  @Environment(AppStore.self) private var store
  let rank: Int
  let record: ReplicaTimeRecord

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM yyyy"
    return formatter
  }()

  var body: some View {
    HStack(spacing: 14) {
      Text("\(rank)")
        .font(.rubik(13, weight: .regular))
        .foregroundStyle(store.theme.muted)
        .frame(width: 25)
      Text(record.seconds.androidDurationString)
        .font(.system(size: 20, weight: .regular, design: .monospaced))
        .foregroundStyle(store.theme.foreground.opacity(0.82))
      Spacer()
      Text(Self.dateFormatter.string(from: record.date))
        .font(.rubik(11))
        .foregroundStyle(store.theme.muted.opacity(0.84))
    }
    .padding(.vertical, 11)
  }
}
