#if DEBUG
  import SwiftUI

  #Preview("Home · Pink Amoled") {
    NavigationStack { HomeView() }
      .environment(AppStore())
  }

  #Preview("Settings") {
    NavigationStack { SettingsView() }
      .environment(AppStore())
  }

  #Preview("Theme Library") {
    NavigationStack { ThemeLibraryView() }
      .environment(AppStore())
  }

  #Preview("Board Canvas") {
    let cells: [BoardCellVisual] = [
      .covered, .flagged, .revealed(1), .revealed(0),
      .revealed(2), .covered, .mine(triggered: false), .wrongFlag,
      .revealed(1), .revealed(1), .revealed(1), .covered,
    ]
    BoardRenderer(
      board: BoardPresentation(columns: 4, rows: 3, cells: cells),
      phase: .playing,
      isLoading: false,
      changedCoordinates: [],
      actionCoordinate: nil,
      fixedStartCoordinate: nil,
      isFixedStartEnabled: false,
      theme: ThemeCatalog.fallback,
      showsBorders: true,
      animationSpeed: 100,
      isReplayCovering: false,
      replayCoverSequence: 0,
      longPressEnabled: true,
      longPressDuration: 0.3,
      onTap: { _, _ in },
      onLongPress: { _, _ in }
    )
    .background(ThemeCatalog.fallback.background)
  }
#endif
