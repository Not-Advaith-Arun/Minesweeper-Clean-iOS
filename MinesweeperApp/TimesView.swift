import SwiftUI

struct TimesView: View {
  @Environment(AppStore.self) private var store
  @State private var difficulty: ReplicaDifficulty = .medium
  @State private var pendingDeletion: ReplicaTimeRecord?

  var body: some View {
    let theme = store.theme
    ZStack {
      ReplicaBackground(theme: theme)
      VStack(spacing: 14) {
        DifficultyTabs(selection: $difficulty)
          .padding(.top, 8)

        let records = store.records(for: difficulty)
        if records.isEmpty {
          Spacer()
          VStack(spacing: 12) {
            Image(systemName: "stopwatch")
              .font(.system(size: 38, weight: .light))
            Text("No times yet")
              .font(.rubik(18, weight: .medium))
            Text("Complete a \(difficulty.title.lowercased()) game to set your first time.")
              .font(.rubik(13))
              .foregroundStyle(theme.muted)
              .multilineTextAlignment(.center)
          }
          .foregroundStyle(theme.foreground)
          .padding(.horizontal, 42)
          Spacer()
        } else {
          List {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
              TimeRow(rank: index + 1, record: record)
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.muted.opacity(0.18))
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
                selection == difficulty ? store.theme.background : store.theme.foreground
              )
              .padding(.horizontal, 15)
              .frame(height: 34)
              .background(
                Capsule().fill(
                  selection == difficulty ? store.theme.foreground : store.theme.surface))
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
        .font(.rubik(13, weight: .semibold))
        .foregroundStyle(store.theme.muted)
        .frame(width: 25)
      Text(record.seconds.clockString)
        .font(.system(size: 20, weight: .medium, design: .monospaced))
        .foregroundStyle(store.theme.foreground)
      Spacer()
      Text(Self.dateFormatter.string(from: record.date))
        .font(.rubik(11))
        .foregroundStyle(store.theme.muted)
    }
    .padding(.vertical, 8)
  }
}
