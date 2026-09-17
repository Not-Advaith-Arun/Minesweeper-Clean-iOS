import SwiftUI

@main
struct MinesweeperReplicaApp: App {
  @State private var store = AppStore()

  var body: some Scene {
    WindowGroup {
      AppRootView()
        .environment(store)
        .preferredColorScheme(store.theme.usesLightBackground ? .light : .dark)
    }
  }
}

struct AppRootView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    @Bindable var store = store
    NavigationStack(path: $store.navigation) {
      HomeView()
        .navigationDestination(for: AppRoute.self) { route in
          switch route {
          case .game(let difficulty, let resume):
            GameView(difficulty: difficulty, resume: resume)
          case .settings:
            SettingsView()
          case .themes:
            ThemeLibraryView()
          case .times:
            TimesView()
          }
        }
    }
    .sheet(isPresented: $store.showAbout) {
      AboutView()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(store.theme.background)
    }
    .task {
      // Extreme's fixed opening lets its verified board begin warming as soon
      // as the app launches, rather than after the player taps New Game.
      await ExtremeReadyBoardPool.shared.warm()
      await store.hydrateFromDisk()
    }
  }
}
