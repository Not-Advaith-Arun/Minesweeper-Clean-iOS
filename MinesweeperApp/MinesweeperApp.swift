import SwiftUI

@main
struct MinesweeperReplicaApp: App {
  @State private var store = AppStore()

  var body: some Scene {
    WindowGroup {
      AppRootView()
        .environment(store)
        .preferredColorScheme(store.theme.isAMOLED ? .dark : nil)
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
    .task { await store.hydrateFromDisk() }
  }
}
