import SwiftUI

struct TimesView: View {
  @Environment(AppStore.self) private var store
  @State private var difficulty: ReplicaDifficulty = .medium
  @State private var pendingDeletion: ReplicaTimeRecord?

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      VStack(spacing: 20) {
        DifficultyTabs(selection: $difficulty)
          .padding(.top, 26)

        let records = store.records(for: difficulty)
        if records.isEmpty {
          Spacer()
          VStack(spacing: 14) {
            Image(systemName: "stopwatch")
              .font(.system(size: 42, weight: .ultraLight))
              .foregroundStyle(theme.foreground.opacity(0.54))
            Text("No times yet")
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
        }
      }
    }
    .navigationTitle("Top times")
    .navigationBarTitleDisplayMode(.inline)
    .replicaNavigationAppearance(theme: theme)
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

private struct DifficultyTabs: View {
  @Environment(AppStore.self) private var store
  @Binding var selection: ReplicaDifficulty

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(ReplicaDifficulty.allCases) { difficulty in
          Button {
            selection = difficulty
            store.haptic(.selection)
          } label: {
            Text(difficulty.title)
              .font(.rubik(12, weight: .medium))
              .foregroundStyle(
                selection == difficulty
                  ? store.theme.background : store.theme.foreground.opacity(0.78)
              )
              .padding(.horizontal, 15)
              .frame(height: 36)
              .background(
                Capsule().fill(
                  selection == difficulty
                    ? store.theme.foreground : store.theme.background.opacity(0.001)))
              .overlay {
                Capsule()
                  .stroke(
                    store.theme.muted.opacity(selection == difficulty ? 0 : 0.24),
                    lineWidth: ReplicaMetrics.thinStroke)
              }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
    }
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
      Text(record.seconds.clockString)
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
