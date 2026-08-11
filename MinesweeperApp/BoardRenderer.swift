import SwiftUI
import UIKit
import MinesweeperCore

struct BoardRenderer: UIViewRepresentable {
  let board: BoardPresentation
  let phase: ReplicaGamePhase
  let isLoading: Bool
  let changedCoordinates: Set<CellCoordinate>
  let actionCoordinate: CellCoordinate?
  let theme: AppTheme
  let showsBorders: Bool
  let animationSpeed: Double
  let longPressEnabled: Bool
  let longPressDuration: TimeInterval
  let onTap: (Int, Int) -> Void
  let onLongPress: (Int, Int) -> Void

  func makeUIView(context: Context) -> BoardViewport {
    let viewport = BoardViewport()
    viewport.canvas.onTap = onTap
    viewport.canvas.onLongPress = onLongPress
    return viewport
  }

  func updateUIView(_ viewport: BoardViewport, context: Context) {
    viewport.canvas.onTap = onTap
    viewport.canvas.onLongPress = onLongPress
    viewport.canvas.longPressRecognizer.isEnabled = longPressEnabled
    viewport.canvas.longPressRecognizer.minimumPressDuration = longPressDuration
    viewport.update(
      board: board,
      phase: phase,
      isLoading: isLoading,
      changedCoordinates: changedCoordinates,
      actionCoordinate: actionCoordinate,
      palette: BoardPalette(theme: theme),
      showsBorders: showsBorders,
      animationSpeed: animationSpeed
    )
  }
}

struct BoardPalette {
  let background: UIColor
  let surface: UIColor
  let covered: UIColor
  let flagged: UIColor
  let separator: UIColor
  let accent: UIColor
  let foreground: UIColor
  let muted: UIColor
  let mine: UIColor
  let clues: [UIColor]

  var flagGlyph: UIColor {
    // Clean One normally lets the page/background color supply the dark flag
    // silhouette. Some themes, however, pair a dark background with an almost
    // equally dark flagged surface. Preserve the themed choice when it is
    // legible and fall back to the highest-contrast neutral when it is not.
    if background.contrastRatio(with: flagged) >= 3 { return background }
    return [foreground, UIColor.black, UIColor.white].max {
      $0.contrastRatio(with: flagged) < $1.contrastRatio(with: flagged)
    } ?? foreground
  }

  var coveredMineGlyph: UIColor {
    // Loss keeps ordinary mines on the covered field. Prefer the theme's
    // background silhouette when it remains readable (as in Kawa), otherwise
    // select the strongest neutral contrast so mines never disappear on light
    // or AMOLED covered colors.
    if background.contrastRatio(with: covered) >= 3 { return background }
    return [foreground, UIColor.black, UIColor.white].max {
      $0.contrastRatio(with: covered) < $1.contrastRatio(with: covered)
    } ?? UIColor.black
  }

  var gridLine: UIColor {
    // The decoded separator colors are intentionally close to the revealed
    // surface. Applying another low-alpha blend made them disappear entirely.
    // Nudge the decoded hue only as far as needed to retain the reference's
    // quiet cross-like cell separators in every light and dark palette.
    if separator.contrastRatio(with: surface) >= 1.18 { return separator }
    let target = foreground.contrastRatio(with: surface)
      >= background.contrastRatio(with: surface) ? foreground : background
    for amount in stride(from: CGFloat(0.04), through: 0.28, by: 0.04) {
      let candidate = separator.interpolated(to: target, progress: amount)
      if candidate.contrastRatio(with: surface) >= 1.18 { return candidate }
    }
    return separator.interpolated(to: target, progress: 0.28)
  }

  init(theme: AppTheme) {
    background = UIColor(theme.background)
    surface = UIColor(theme.surface)
    covered = UIColor(theme.covered)
    flagged = UIColor(theme.flagged)
    separator = UIColor(theme.separator)
    accent = UIColor(theme.accent)
    foreground = UIColor(theme.foreground)
    muted = UIColor(theme.muted)
    mine = UIColor(theme.mine)
    clues = theme.clueColors.map(UIColor.init)
  }

  func matches(_ other: BoardPalette) -> Bool {
    background.isEqual(other.background)
      && surface.isEqual(other.surface)
      && covered.isEqual(other.covered)
      && flagged.isEqual(other.flagged)
      && separator.isEqual(other.separator)
      && accent.isEqual(other.accent)
      && foreground.isEqual(other.foreground)
      && muted.isEqual(other.muted)
      && mine.isEqual(other.mine)
      && zip(clues, other.clues).allSatisfy { $0.isEqual($1) }
  }

  func interpolated(to other: BoardPalette, progress: CGFloat) -> BoardPalette {
    BoardPalette(
      background: background.interpolated(to: other.background, progress: progress),
      surface: surface.interpolated(to: other.surface, progress: progress),
      covered: covered.interpolated(to: other.covered, progress: progress),
      flagged: flagged.interpolated(to: other.flagged, progress: progress),
      separator: separator.interpolated(to: other.separator, progress: progress),
      accent: accent.interpolated(to: other.accent, progress: progress),
      foreground: foreground.interpolated(to: other.foreground, progress: progress),
      muted: muted.interpolated(to: other.muted, progress: progress),
      mine: mine.interpolated(to: other.mine, progress: progress),
      clues: zip(clues, other.clues).map { $0.interpolated(to: $1, progress: progress) }
    )
  }

  private init(
    background: UIColor, surface: UIColor, covered: UIColor, flagged: UIColor,
    separator: UIColor, accent: UIColor, foreground: UIColor, muted: UIColor,
    mine: UIColor, clues: [UIColor]
  ) {
    self.background = background
    self.surface = surface
    self.covered = covered
    self.flagged = flagged
    self.separator = separator
    self.accent = accent
    self.foreground = foreground
    self.muted = muted
    self.mine = mine
    self.clues = clues
  }
}

private extension UIColor {
  func interpolated(to other: UIColor, progress: CGFloat) -> UIColor {
    let amount = min(1, max(0, progress))
    var lhs: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    var rhs: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    getRed(&lhs.0, green: &lhs.1, blue: &lhs.2, alpha: &lhs.3)
    other.getRed(&rhs.0, green: &rhs.1, blue: &rhs.2, alpha: &rhs.3)
    return UIColor(
      red: lhs.0 + (rhs.0 - lhs.0) * amount,
      green: lhs.1 + (rhs.1 - lhs.1) * amount,
      blue: lhs.2 + (rhs.2 - lhs.2) * amount,
      alpha: lhs.3 + (rhs.3 - lhs.3) * amount
    )
  }

  func contrastRatio(with other: UIColor) -> CGFloat {
    let lighter = max(relativeLuminance, other.relativeLuminance)
    let darker = min(relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private var relativeLuminance: CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
    func linear(_ channel: CGFloat) -> CGFloat {
      channel <= 0.04045
        ? channel / 12.92
        : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
}

final class BoardViewport: UIScrollView, UIScrollViewDelegate {
  let canvas = BoardCanvasView()
  private var lastGridSize = CGSize.zero
  private var lastPhase: ReplicaGamePhase = .ready
  private var hasAppliedInitialZoom = false
  private var pendingFocusCoordinate: CellCoordinate?
  private var focusWorkItem: DispatchWorkItem?
  private var terminalWorkItem: DispatchWorkItem?
  private var isHoldingRevealTransform = false
  private var isTerminalFramed = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    delegate = self
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    bouncesZoom = true
    alwaysBounceVertical = true
    alwaysBounceHorizontal = true
    decelerationRate = .fast
    contentInsetAdjustmentBehavior = .never
    backgroundColor = .clear
    addSubview(canvas)
  }

  required init?(coder: NSCoder) { nil }

  func update(
    board: BoardPresentation,
    phase: ReplicaGamePhase,
    isLoading: Bool,
    changedCoordinates: Set<CellCoordinate>,
    actionCoordinate: CellCoordinate?,
    palette: BoardPalette,
    showsBorders: Bool,
    animationSpeed: Double
  ) {
    let gridSize = CGSize(
      width: CGFloat(board.columns) * BoardCanvasView.baseCellSize,
      height: CGFloat(board.rows) * BoardCanvasView.baseCellSize
    )
    if gridSize != lastGridSize {
      lastGridSize = gridSize
      canvas.frame = CGRect(origin: .zero, size: gridSize)
      contentSize = gridSize
      hasAppliedInitialZoom = false
    }
    let previousPhase = lastPhase
    if previousPhase != .ready, phase == .ready {
      // A new game can reuse the same board dimensions. Reset the viewport even
      // when `gridSize` did not change, otherwise the ready slab inherits the
      // previous round's zoom and pan position and its angled ends are clipped.
      focusWorkItem?.cancel()
      terminalWorkItem?.cancel()
      pendingFocusCoordinate = nil
      isHoldingRevealTransform = false
      isTerminalFramed = false
      hasAppliedInitialZoom = false
      contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }
    if previousPhase == .ready, phase == .playing {
      pendingFocusCoordinate = actionCoordinate
      isHoldingRevealTransform = true
      focusWorkItem?.cancel()
      if bounds.width > 0 {
        let revealScale = bounds.width / gridSize.width * 0.79
        setZoomScale(revealScale, animated: false)
        hasAppliedInitialZoom = true
      }
    }
    if !previousPhase.isFinished, phase.isFinished {
      focusWorkItem?.cancel()
      isHoldingRevealTransform = false
      terminalWorkItem?.cancel()
      let baseDelay = phase == .won ? 0.68 : 0.70
      let delay = animationSpeed > 0 && !UIAccessibility.isReduceMotionEnabled
        ? baseDelay * 100 / min(150, max(5, animationSpeed)) : 0
      let work = DispatchWorkItem { [weak self] in self?.applyTerminalFrame(animated: delay > 0) }
      terminalWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    } else if previousPhase.isFinished, !phase.isFinished {
      terminalWorkItem?.cancel()
      isTerminalFramed = false
      hasAppliedInitialZoom = false
    }
    lastPhase = phase
    canvas.update(
      board: board,
      phase: phase,
      isLoading: isLoading,
      changedCoordinates: changedCoordinates,
      actionCoordinate: actionCoordinate,
      palette: palette,
      showsBorders: showsBorders,
      animationSpeed: animationSpeed
    )
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, lastGridSize.width > 0 else { return }
    let fitWidth = bounds.width / lastGridSize.width
    let fitHeight = bounds.height / lastGridSize.height
    let readyScale = min(fitHeight, fitWidth * 0.79)
    let terminalScale = min(
      1.15,
      bounds.width * 0.90 / lastGridSize.width,
      bounds.height * 0.59 / lastGridSize.height
    )
    minimumZoomScale = lastPhase == .ready
      ? readyScale
      : (lastPhase.isFinished ? min(0.65, terminalScale) : 0.65)
    maximumZoomScale = max(minimumZoomScale, 3.5)
    if !hasAppliedInitialZoom {
      zoomScale = lastPhase == .ready
        ? readyScale
        : max(minimumZoomScale, min(maximumZoomScale, 1.15))
      hasAppliedInitialZoom = true
    } else if zoomScale < minimumZoomScale {
      zoomScale = minimumZoomScale
    }
    centerContent()
    applyPendingFocusIfNeeded()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cancelPendingFocus() }

  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    cancelPendingFocus()
  }

  private func centerContent() {
    let horizontal = max(0, (bounds.width - contentSize.width) / 2)
    let spareVertical = max(0, bounds.height - contentSize.height)
    let targetCenterY: CGFloat? = if lastPhase == .ready || isHoldingRevealTransform {
      bounds.height * 0.54
    } else if isTerminalFramed {
      // Easy's 7×10 board is width-limited at the terminal scale. Lower it
      // into the result composition so it does not leave a large, empty band
      // above the bottom controls. Taller presets retain the Android framing.
      lastGridSize.height <= Self.shortTerminalBoardHeight
        ? bounds.height * 0.56
        : bounds.height * 0.45
    } else {
      nil
    }
    let vertical = targetCenterY.map { max(0, $0 - contentSize.height / 2) }
      ?? spareVertical / 2
    let bottom = max(0, spareVertical - vertical)
    contentInset = UIEdgeInsets(
      top: vertical, left: horizontal, bottom: bottom, right: horizontal)
  }

  private static let shortTerminalBoardHeight: CGFloat = BoardCanvasView.baseCellSize * 10.5

  private func applyPendingFocusIfNeeded() {
    guard let coordinate = pendingFocusCoordinate, bounds.width > 0, bounds.height > 0 else { return }
    pendingFocusCoordinate = nil
    // The Android reference reveals at the fit-to-board scale, then settles at
    // roughly eight visible columns after the clearing wave has completed.
    let targetZoom = max(minimumZoomScale, min(maximumZoomScale, 1.29))
    let center = CGPoint(
      x: (CGFloat(coordinate.column) + 0.5) * BoardCanvasView.baseCellSize,
      y: (CGFloat(coordinate.row) + 0.5) * BoardCanvasView.baseCellSize
    )
    let focusDelay = UIAccessibility.isReduceMotionEnabled || canvas.animationSpeedPercent == 0
      ? 0
      : 0.66 * 100 / min(150, max(5, canvas.animationSpeedPercent))
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.isHoldingRevealTransform = false
      self.centerContent()
      let focusSize = CGSize(
        width: self.bounds.width / targetZoom,
        height: self.bounds.height / targetZoom
      )
      let maxOriginX = max(0, self.lastGridSize.width - focusSize.width)
      let maxOriginY = max(0, self.lastGridSize.height - focusSize.height)
      let focusRect = CGRect(
        x: min(max(0, center.x - focusSize.width / 2), maxOriginX),
        y: min(max(0, center.y - focusSize.height / 2), maxOriginY),
        width: focusSize.width,
        height: focusSize.height
      )
      let animated = !UIAccessibility.isReduceMotionEnabled && self.canvas.animationSpeedPercent > 0
      // UIScrollView's native zoom interpolation tracks the display refresh
      // rate and preserves the content point without the stepped transform
      // produced by wrapping a non-animated zoom call in UIView.animate.
      self.zoom(to: focusRect, animated: animated)
    }
    focusWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: work)
  }

  private func cancelPendingFocus() {
    focusWorkItem?.cancel()
    focusWorkItem = nil
    pendingFocusCoordinate = nil
    if isHoldingRevealTransform {
      isHoldingRevealTransform = false
      centerContent()
    }
  }

  private func applyTerminalFrame(animated: Bool) {
    guard bounds.width > 0, bounds.height > 0, lastGridSize.width > 0, lastPhase.isFinished else {
      return
    }
    isTerminalFramed = true
    let scale = min(
      1.15,
      bounds.width * 0.90 / lastGridSize.width,
      bounds.height * 0.59 / lastGridSize.height
    )
    minimumZoomScale = min(0.65, scale)
    let changes = {
      self.setZoomScale(scale, animated: false)
      self.centerContent()
      self.contentOffset = CGPoint(x: -self.contentInset.left, y: -self.contentInset.top)
      self.layoutIfNeeded()
    }
    if animated {
      UIView.animate(
        withDuration: 0.30 * 100 / min(150, max(5, canvas.animationSpeedPercent)),
        delay: 0,
        options: [.curveEaseInOut, .beginFromCurrentState],
        animations: changes
      )
    } else {
      changes()
    }
  }

  private func boundedOffset(_ offset: CGPoint) -> CGPoint {
    let minX = -contentInset.left
    let minY = -contentInset.top
    let maxX = max(minX, contentSize.width - bounds.width + contentInset.right)
    let maxY = max(minY, contentSize.height - bounds.height + contentInset.bottom)
    return CGPoint(
      x: min(max(offset.x, minX), maxX),
      y: min(max(offset.y, minY), maxY)
    )
  }
}

final class BoardCanvasView: UIView, UIGestureRecognizerDelegate {
  static let baseCellSize: CGFloat = 44

  var onTap: ((Int, Int) -> Void)?
  var onLongPress: ((Int, Int) -> Void)?
  private var board = BoardPresentation(columns: 1, rows: 1)
  private var phase: ReplicaGamePhase = .ready
  private var isLoading = false
  private var palette = BoardPalette(theme: ThemeCatalog.fallback)
  private var targetPalette = BoardPalette(theme: ThemeCatalog.fallback)
  private var paletteTransitionFrom: BoardPalette?
  private var paletteTransitionStartedAt: CFTimeInterval?
  private var hasReceivedPalette = false
  private var showsBorders = false
  private var animationSpeed = 100.0
  var animationSpeedPercent: Double { animationSpeed }
  private var revealStartedAt: [Int: CFTimeInterval] = [:]
  private var revealDurations: [Int: CFTimeInterval] = [:]
  private var initialRevealStartedAt: CFTimeInterval?
  private var initialRevealDuration: CFTimeInterval = 0
  private var initialRevealOrigin: CGPoint?
  private var restartSnapshot: UIImage?
  private var restartStartedAt: CFTimeInterval?
  private var restartDuration: CFTimeInterval = 0
  private var displayLink: CADisplayLink?
  // Every cell in a rendered frame must observe exactly the same animation
  // time. Sampling CACurrentMediaTime() independently for connected neighbors
  // can make a shared edge disagree for one frame as a reveal begins.
  private var renderTimestamp: CFTimeInterval?

  lazy var longPressRecognizer: UILongPressGestureRecognizer = {
    let recognizer = UILongPressGestureRecognizer(
      target: self, action: #selector(handleLongPress(_:)))
    recognizer.minimumPressDuration = 0.3
    recognizer.cancelsTouchesInView = true
    recognizer.delegate = self
    addGestureRecognizer(recognizer)
    return recognizer
  }()

  private lazy var tapRecognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    recognizer.delegate = self
    addGestureRecognizer(recognizer)
    return recognizer
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    isMultipleTouchEnabled = true
    isAccessibilityElement = true
    accessibilityIdentifier = "game.board"
    _ = tapRecognizer
    _ = longPressRecognizer
    tapRecognizer.require(toFail: longPressRecognizer)
  }

  required init?(coder: NSCoder) { nil }

  func update(
    board: BoardPresentation,
    phase: ReplicaGamePhase,
    isLoading: Bool,
    changedCoordinates: Set<CellCoordinate>,
    actionCoordinate: CellCoordinate?,
    palette: BoardPalette,
    showsBorders: Bool,
    animationSpeed: Double
  ) {
    let oldBoard = self.board
    let oldPhase = self.phase
    let beginsSameSizeRestart = oldPhase != .ready
      && phase == .ready
      && oldBoard.columns == board.columns
      && oldBoard.rows == board.rows
      && bounds.width > 0
      && bounds.height > 0
    let pendingRestartSnapshot: UIImage? = if beginsSameSizeRestart,
      animationSpeed > 0,
      !UIAccessibility.isReduceMotionEnabled
    {
      UIGraphicsImageRenderer(bounds: bounds).image { renderer in
        layer.render(in: renderer.cgContext)
      }
    } else {
      nil
    }
    self.board = board
    self.phase = phase
    self.isLoading = isLoading
    self.showsBorders = showsBorders
    self.animationSpeed = animationSpeed
    let now = CACurrentMediaTime()
    updatePalette(to: palette, at: now)
    let distanceScale = Self.durationScale(for: animationSpeed)
    if let pendingRestartSnapshot {
      restartSnapshot = pendingRestartSnapshot
      restartStartedAt = now
      restartDuration = 0.88 * distanceScale
    } else if phase != .ready {
      restartSnapshot = nil
      restartStartedAt = nil
      restartDuration = 0
    }
    let startsInitialReveal: Bool = {
      guard oldPhase == .ready, phase == .playing, let actionCoordinate,
        actionCoordinate.column >= 0, actionCoordinate.column < board.columns,
        actionCoordinate.row >= 0, actionCoordinate.row < board.rows
      else { return false }
      if case .revealed = board[actionCoordinate.column, actionCoordinate.row] { return true }
      return false
    }()
    if startsInitialReveal,
      animationSpeed > 0,
      !UIAccessibility.isReduceMotionEnabled,
      let actionCoordinate
    {
      initialRevealStartedAt = now
      initialRevealDuration = 0.62 * distanceScale
      initialRevealOrigin = CGPoint(
        x: (CGFloat(actionCoordinate.column) + 0.5) * Self.baseCellSize,
        y: (CGFloat(actionCoordinate.row) + 0.5) * Self.baseCellSize
      )
    } else if phase == .ready {
      initialRevealStartedAt = nil
      initialRevealOrigin = nil
      initialRevealDuration = 0
    }
    for coordinate in changedCoordinates {
      let index = coordinate.row * board.columns + coordinate.column
      guard board.cells.indices.contains(index) else { continue }
      if oldBoard.cells.indices.contains(index), oldBoard.cells[index] != board.cells[index] {
        // The first opening is one continuous touch-origin surface wipe. Its
        // final topology is rendered underneath the old ready slab, so adding
        // per-cell clearing overlays here would reintroduce the checkerboard
        // intermediate that the global mask is specifically replacing.
        if startsInitialReveal { continue }
        let delay: Double
        if phase == .lost, case .mine = board.cells[index], let actionCoordinate {
          let dx = Double(coordinate.column - actionCoordinate.column)
          let dy = Double(coordinate.row - actionCoordinate.row)
          let radial = hypot(dx, dy) * 0.018
          let jitter = Double((coordinate.row * 17 + coordinate.column * 29) % 23) / 1_000
          // A radial wave avoids the mechanical diagonal bands produced by a
          // Chebyshev schedule. The deterministic micro-jitter keeps nearby
          // mines from appearing on exactly the same display frame.
          delay = min(0.38, radial) + (dx == 0 && dy == 0 ? 0 : 0.07 + jitter)
        } else {
          let distance = actionCoordinate.map {
            max(abs(coordinate.row - $0.row), abs(coordinate.column - $0.column))
          } ?? 0
          delay = min(0.30, Double(distance) * 0.012)
        }
        revealStartedAt[index] = now + delay * distanceScale
        // Flags in the reference settle within roughly two 30-fps frames.
        // Reveals and mine cascades retain their longer surface morph.
        switch board.cells[index] {
        case .flagged, .wrongFlag:
          revealDurations[index] = 0.07 * distanceScale
        case .covered, .revealed, .flaggedMine, .mine:
          revealDurations[index] = 0.24 * distanceScale
        }
      }
    }
    accessibilityLabel = "Minesweeper board, \(board.columns) columns by \(board.rows) rows"
    maintainDisplayLink()
    setNeedsDisplay()
  }


  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    renderTimestamp = CACurrentMediaTime()
    defer { renderTimestamp = nil }
    context.setFillColor(palette.background.cgColor)
    context.fill(rect)

    if phase == .ready {
      if !drawRestartTransition(context: context) {
        drawReadyBoard(in: bounds)
      }
      return
    }

    // Paint one continuous revealed surface beneath every cell, then composite
    // rounded covered regions above it. Using the covered color as the base
    // makes an isolated covered cell appear square because its rounded corners
    // reveal the same color underneath; it also creates colored pinholes at
    // four-cell junctions when borders are enabled.
    context.saveGState()
    let boardRadius = Self.baseCellSize * 0.09
    UIBezierPath(roundedRect: bounds, cornerRadius: boardRadius).addClip()
    context.setFillColor(palette.surface.cgColor)
    context.fill(bounds)
    defer { context.restoreGState() }

    let firstColumn = max(0, Int(floor(rect.minX / Self.baseCellSize)))
    let lastColumn = min(board.columns - 1, Int(ceil(rect.maxX / Self.baseCellSize)))
    let firstRow = max(0, Int(floor(rect.minY / Self.baseCellSize)))
    let lastRow = min(board.rows - 1, Int(ceil(rect.maxY / Self.baseCellSize)))
    guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn {
        drawCell(board[column, row], column: column, row: row, context: context)
      }
    }

    // Repaint stable covered regions after the revealed surface. Their
    // rounded union supplies the complementary (concave) rounding at every
    // revealed/covered boundary without exposing the canvas underneath.
    palette.covered.setFill()
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn {
        switch board[column, row] {
        case .covered, .mine(triggered: false): break
        case .revealed, .flagged, .flaggedMine, .mine(triggered: true), .wrongFlag:
          continue
        }
        let cellRect = CGRect(
          x: CGFloat(column) * Self.baseCellSize,
          y: CGFloat(row) * Self.baseCellSize,
          width: Self.baseCellSize,
          height: Self.baseCellSize
        )
        drawConnectedCover(
          in: cellRect,
          fillRect: cellRect,
          radius: Self.baseCellSize * 0.09,
          column: column,
          row: row,
          scale: 1
        )
      }
    }
    drawConcaveCoverCutouts(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow
    )
    drawFlagRegions(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow
    )
    drawCoveredMineGlyphs(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow
    )
    drawInitialRevealOverlay(context: context)
  }

  private func drawCell(_ cell: BoardCellVisual, column: Int, row: Int, context: CGContext) {
    let rect = CGRect(
      x: CGFloat(column) * Self.baseCellSize,
      y: CGFloat(row) * Self.baseCellSize,
      width: Self.baseCellSize,
      height: Self.baseCellSize
    )
    let index = row * board.columns + column
    let inset = showsBorders
      ? rect.insetBy(dx: 0.55, dy: 0.55)
      : rect.insetBy(dx: Self.baseCellSize * 0.08, dy: Self.baseCellSize * 0.08)
    let radius: CGFloat = Self.baseCellSize * 0.09
    let progress = revealProgress(for: index)
    let revealScale = numberScale(for: progress)

    switch cell {
    case .covered:
      // The shared covered slab is already underneath this cell. Keeping it
      // intact avoids fractional-pixel grid seams when the canvas is scaled.
      break
    case .revealed(let count):
      palette.surface.setFill()
      drawConnectedCover(
        in: rect,
        fillRect: rect,
        radius: Self.baseCellSize * 0.09,
        column: column,
        row: row,
        scale: 1,
        matchesNeighbor: { [self] column, row in
          visuallyRevealed(column: column, row: row)
        }
      )
      drawGridLine(in: rect, column: column, row: row, context: context)
      if count > 0 { drawNumber(count, in: rect, scale: revealScale) }
      drawClearingOverlay(in: rect, progress: progress)
    case .flagged, .flaggedMine:
      // Flags are composited as a final region-wide pass. That lets both the
      // dark moat and the flagged surface share one clean orthogonal topology
      // instead of leaving a square revealed-cell outline behind.
      break
    case .mine(let triggered):
      if !triggered {
        // Ordinary mines retain the connected covered-color field beneath
        // them and are composited in one final glyph pass after that field.
        break
      }
      if progress <= 0 {
        palette.covered.setFill()
        drawConnectedCover(
          in: rect,
          fillRect: inset,
          radius: radius,
          column: column,
          row: row,
          scale: 1
        )
        break
      }
      // Ordinary mines float cleanly on the shared revealed surface. Only the
      // detonated mine receives an inverse, inset rounded plate; a full-cell
      // fill created the harsh square blocks visible in the old loss screen.
      palette.mine.setFill()
      UIBezierPath(roundedRect: inset, cornerRadius: radius).fill()
      drawMine(
        in: rect,
        color: palette.background,
        holeColor: palette.mine,
        scale: numberScale(for: progress)
      )
      // The detonated inverse tile and its mine glyph appear atomically in the
      // source. Leaving the generic clearing overlay here put a shrinking
      // covered-color square on top of the red tile for several frames.
    case .wrongFlag:
      break
    }

    if showsBorders {
      context.setStrokeColor(palette.separator.cgColor)
      context.setLineWidth(0.7)
      context.stroke(inset)
    }
  }

  /// Flags replace covered cells with a muted inset surface surrounded by a
  /// slim revealed-color moat. Rendering the whole group after the covered
  /// pass keeps that moat rounded against unrevealed cells and lets adjacent
  /// orthogonal flags read as one deliberate visual region.
  private func drawFlagRegions(
    firstColumn: Int,
    lastColumn: Int,
    firstRow: Int,
    lastRow: Int
  ) {
    let radius = Self.baseCellSize * 0.09
    let tileInset = Self.baseCellSize * 0.08

    // A flag placed in the unrevealed slab needs the covered color beneath the
    // rounded moat corners. A flag already surrounded by revealed cells keeps
    // the shared revealed surface beneath it.
    palette.covered.setFill()
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn where isFlagLike(column: column, row: row) {
        drawFlagCoveredBackdrop(column: column, row: row, radius: radius)
      }
    }

    // Outer revealed-color moat.
    palette.surface.setFill()
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn where isFlagLike(column: column, row: row) {
        let rect = cellRect(column: column, row: row)
        drawConnectedCover(
          in: rect,
          fillRect: rect,
          radius: radius,
          column: column,
          row: row,
          scale: 1,
          matchesNeighbor: { [self] column, row in isFlagLike(column: column, row: row) }
        )
      }
    }
    // Inset flagged surface. Unlike covered cells, flags merge only across a
    // shared horizontal or vertical edge; diagonal flags remain distinct.
    palette.flagged.setFill()
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn where isFlagLike(column: column, row: row) {
        let rect = cellRect(column: column, row: row)
        drawConnectedCover(
          in: rect,
          fillRect: rect.insetBy(dx: tileInset, dy: tileInset),
          radius: radius,
          column: column,
          row: row,
          scale: 1,
          matchesNeighbor: { [self] column, row in isFlagLike(column: column, row: row) }
        )
      }
    }
    // Glyphs and the short placement morph sit above the completed topology.
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn where isFlagLike(column: column, row: row) {
        let rect = cellRect(column: column, row: row)
        let index = row * board.columns + column
        let progress = revealProgress(for: index)
        guard progress > 0 else {
          if case .flaggedMine = board[column, row] {
            drawFlag(in: rect, color: palette.flagGlyph, scale: 0.55)
            continue
          }
          if case .wrongFlag = board[column, row] {
            drawFlag(in: rect, color: palette.flagGlyph, scale: 0.55)
            continue
          }
          // Keep a scheduled flag completely covered until its turn. The
          // reference then reveals the tile and glyph together in one frame,
          // avoiding a blank-gray intermediate as the center clears.
          drawClearingOverlay(in: rect, progress: 0)
          continue
        }
        if case .flaggedMine = board[column, row] {
          drawMine(
            in: rect,
            color: palette.flagGlyph,
            holeColor: palette.flagged,
            scale: 0.62
          )
        } else {
          drawFlag(
            in: rect,
            color: palette.flagGlyph,
            scale: 0.55
          )
        }
        if case .wrongFlag = board[column, row] { drawCross(in: rect) }
        if showsBorders {
          guard let context = UIGraphicsGetCurrentContext() else { continue }
          context.setStrokeColor(palette.separator.cgColor)
          context.setLineWidth(0.7)
          context.stroke(rect.insetBy(dx: 0.55, dy: 0.55))
        }
      }
    }
  }

  private func drawCoveredMineGlyphs(
    firstColumn: Int,
    lastColumn: Int,
    firstRow: Int,
    lastRow: Int
  ) {
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn {
        guard case .mine(triggered: false) = board[column, row] else { continue }
        let index = row * board.columns + column
        let progress = revealProgress(for: index)
        guard progress > 0 else { continue }
        drawMine(
          in: cellRect(column: column, row: row),
          color: palette.coveredMineGlyph,
          holeColor: palette.covered,
          scale: numberScale(for: progress)
        )
      }
    }
  }

  private func drawReadyBoard(in rect: CGRect) {
    drawReadySlab(in: rect)
    drawReadyPrompt(in: rect, alpha: 1)
  }

  private func drawReadySlab(in boardRect: CGRect) {
    palette.covered.setFill()
    UIBezierPath(
      roundedRect: boardRect,
      cornerRadius: min(boardRect.width, boardRect.height) * 0.012
    ).fill()
  }

  private func drawReadyPrompt(in rect: CGRect, alpha: CGFloat) {
    guard alpha > 0 else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      // The ready board is fitted to the viewport, so derive type from canvas
      // width as well. This keeps the rendered prompt the same size on Easy,
      // Medium and the taller boards instead of making it huge on Easy.
      .font: UIFont(name: "Rubik-Regular", size: rect.width * 0.045)
        ?? UIFont.systemFont(ofSize: rect.width * 0.045, weight: .regular),
      .foregroundColor: palette.background.withAlphaComponent(0.56 * alpha),
    ]
    // Normal board generation completes within a frame. Retain the Android
    // prompt instead of flashing a one-frame loading label before the reveal.
    let string = NSString(string: "Tap to begin.")
    let size = string.size(withAttributes: attributes)
    string.draw(
      at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
      withAttributes: attributes
    )
  }

  /// Reveals the already-composited final board through one circular wave
  /// centered on the first touch. Intersecting that wave with the final cell
  /// topology yields the same connected growing landmass as the reference;
  /// cells that remain covered simply stay covered beneath the mask.
  private func drawInitialRevealOverlay(context: CGContext) {
    guard let startedAt = initialRevealStartedAt,
      let origin = initialRevealOrigin,
      initialRevealDuration > 0
    else { return }

    let elapsed = (renderTimestamp ?? CACurrentMediaTime()) - startedAt
    let progress = CGFloat(min(1, max(0, elapsed / initialRevealDuration)))
    guard progress < 1 else { return }

    // Hold for just over one display frame so the press reads before the
    // surface begins opening, then grow the radius smoothly to the farthest
    // board corner.
    let waveDelay: CGFloat = 0.07
    let waveProgress = Self.smoothStep(
      min(1, max(0, (progress - waveDelay) / (1 - waveDelay)))
    )
    let corners = [
      CGPoint(x: bounds.minX, y: bounds.minY),
      CGPoint(x: bounds.maxX, y: bounds.minY),
      CGPoint(x: bounds.minX, y: bounds.maxY),
      CGPoint(x: bounds.maxX, y: bounds.maxY),
    ]
    let maximumRadius = corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max()
      ?? hypot(bounds.width, bounds.height)
    let revealRadius = (maximumRadius + Self.baseCellSize * 0.12) * waveProgress

    context.saveGState()
    let remainingSlab = UIBezierPath(rect: bounds)
    remainingSlab.append(UIBezierPath(
      ovalIn: CGRect(
        x: origin.x - revealRadius,
        y: origin.y - revealRadius,
        width: revealRadius * 2,
        height: revealRadius * 2
      )
    ))
    context.addPath(remainingSlab.cgPath)
    context.clip(using: .evenOdd)
    drawReadySlab(in: bounds)
    context.restoreGState()

    // The ready prompt remains stable during the earliest part of the wave,
    // then fades as the opening reaches the middle of the board.
    let promptProgress = Self.smoothStep(min(1, progress / 0.62))
    drawReadyPrompt(in: bounds, alpha: 1 - promptProgress)

    // A compact filled ripple matches the visible press acknowledgement in
    // the source frames without obscuring numbers beneath it.
    let rippleEnd: CGFloat = 0.24
    if progress < rippleEnd {
      let rippleProgress = Self.smoothStep(progress / rippleEnd)
      let rippleRadius = Self.baseCellSize * (0.10 + 0.18 * rippleProgress)
      context.saveGState()
      context.setFillColor(
        palette.foreground.withAlphaComponent(0.72 * (1 - rippleProgress)).cgColor
      )
      context.fillEllipse(in: CGRect(
        x: origin.x - rippleRadius,
        y: origin.y - rippleRadius,
        width: rippleRadius * 2,
        height: rippleRadius * 2
      ))
      context.restoreGState()
    }
  }

  /// Fades the completed board into the background, introduces the compact
  /// center pulse visible in the source, then grows the fresh ready slab from
  /// that point. Keeping all three stages in the canvas avoids a one-frame
  /// jump through the fully-sized ready board when the session is replaced.
  @discardableResult
  private func drawRestartTransition(context: CGContext) -> Bool {
    guard let startedAt = restartStartedAt,
      let snapshot = restartSnapshot,
      restartDuration > 0
    else { return false }

    let elapsed = (renderTimestamp ?? CACurrentMediaTime()) - startedAt
    let progress = CGFloat(min(1, max(0, elapsed / restartDuration)))
    guard progress < 1 else { return false }

    if progress < 0.38 {
      let fade = Self.smoothStep(progress / 0.38)
      let scale = 1 - 0.025 * fade
      context.saveGState()
      context.translateBy(x: bounds.midX, y: bounds.midY)
      context.scaleBy(x: scale, y: scale)
      context.translateBy(x: -bounds.midX, y: -bounds.midY)
      snapshot.draw(in: bounds, blendMode: .normal, alpha: 1 - fade)
      context.restoreGState()
    }

    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let pulseProgress = Self.smoothStep(min(1, max(0, (progress - 0.20) / 0.28)))
    if pulseProgress > 0 {
      let pulseRadius = min(bounds.width, bounds.height)
        * (0.012 + 0.105 * pulseProgress)
      palette.covered.setFill()
      context.fillEllipse(in: CGRect(
        x: center.x - pulseRadius,
        y: center.y - pulseRadius,
        width: pulseRadius * 2,
        height: pulseRadius * 2
      ))
    }

    let slabProgress = Self.smoothStep(min(1, max(0, (progress - 0.38) / 0.62)))
    if slabProgress > 0 {
      let slabScale = 0.055 + 0.945 * slabProgress
      context.saveGState()
      context.translateBy(x: center.x, y: center.y)
      context.scaleBy(x: slabScale, y: slabScale)
      context.translateBy(x: -center.x, y: -center.y)
      drawReadySlab(in: bounds)
      context.restoreGState()

      let promptProgress = Self.smoothStep(
        min(1, max(0, (slabProgress - 0.72) / 0.28))
      )
      drawReadyPrompt(in: bounds, alpha: promptProgress)
    }
    return true
  }

  private func drawGridLine(
    in rect: CGRect,
    column: Int,
    row: Int,
    context: CGContext
  ) {
    context.saveGState()
    context.setStrokeColor(palette.gridLine.cgColor)
    context.setLineWidth(1)
    context.setLineCap(.round)
    let gap = Self.baseCellSize * 0.19
    if visuallyRevealed(column: column, row: row + 1) {
      context.move(to: CGPoint(x: rect.minX + gap, y: rect.maxY - 0.5))
      context.addLine(to: CGPoint(x: rect.maxX - gap, y: rect.maxY - 0.5))
    }
    if visuallyRevealed(column: column + 1, row: row) {
      context.move(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + gap))
      context.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.maxY - gap))
    }
    context.strokePath()
    context.restoreGState()
  }

  private func fillCoveredCell(_ rect: CGRect, radius: CGFloat) {
    if radius > 0 {
      UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    } else {
      UIRectFill(rect)
    }
  }

  /// The Android renderer unions orthogonally adjacent covered cells into
  /// clean polyomino-like regions. Isolated cells retain their rounded tile
  /// silhouette, while shared edges are bridged without visible gutters.
  private func drawConnectedCover(
    in cellRect: CGRect,
    fillRect: CGRect,
    radius: CGFloat,
    column: Int,
    row: Int,
    scale: CGFloat,
    matchesNeighbor: ((Int, Int) -> Bool)? = nil
  ) {
    fillCoveredCell(fillRect, radius: radius)

    let matches = matchesNeighbor ?? { [self] column, row in
      visuallyCovered(column: column, row: row)
    }
    let left = matches(column - 1, row)
    let right = matches(column + 1, row)
    let top = matches(column, row - 1)
    let bottom = matches(column, row + 1)
    let bridgeHeight = fillRect.height
    let bridgeWidth = fillRect.width

    if left {
      UIRectFill(CGRect(
        x: cellRect.minX,
        y: fillRect.midY - bridgeHeight / 2,
        width: fillRect.minX + radius - cellRect.minX,
        height: bridgeHeight
      ))
    }
    if right {
      let startX = fillRect.maxX - radius
      UIRectFill(CGRect(
        x: startX,
        y: fillRect.midY - bridgeHeight / 2,
        width: cellRect.maxX - startX,
        height: bridgeHeight
      ))
    }
    if top {
      UIRectFill(CGRect(
        x: fillRect.midX - bridgeWidth / 2,
        y: cellRect.minY,
        width: bridgeWidth,
        height: fillRect.minY + radius - cellRect.minY
      ))
    }
    if bottom {
      let startY = fillRect.maxY - radius
      UIRectFill(CGRect(
        x: fillRect.midX - bridgeWidth / 2,
        y: startY,
        width: bridgeWidth,
        height: cellRect.maxY - startY
      ))
    }

    // Fill shared four-cell junctions so merged regions do not retain tiny
    // pinholes at grid intersections.
    if right && bottom && matches(column + 1, row + 1) {
      let startX = fillRect.maxX - radius
      let startY = fillRect.maxY - radius
      UIRectFill(CGRect(
        x: startX,
        y: startY,
        width: cellRect.maxX - startX,
        height: cellRect.maxY - startY
      ))
    }
    if left && bottom && matches(column - 1, row + 1) {
      let startY = fillRect.maxY - radius
      UIRectFill(CGRect(
        x: cellRect.minX,
        y: startY,
        width: fillRect.minX + radius - cellRect.minX,
        height: cellRect.maxY - startY
      ))
    }
    if right && top && matches(column + 1, row - 1) {
      let startX = fillRect.maxX - radius
      UIRectFill(CGRect(
        x: startX,
        y: cellRect.minY,
        width: cellRect.maxX - startX,
        height: fillRect.minY + radius - cellRect.minY
      ))
    }
    if left && top && matches(column - 1, row - 1) {
      UIRectFill(CGRect(
        x: cellRect.minX,
        y: cellRect.minY,
        width: fillRect.minX + radius - cellRect.minX,
        height: fillRect.minY + radius - cellRect.minY
      ))
    }
    _ = scale
  }

  private func visuallyCovered(column: Int, row: Int) -> Bool {
    guard column >= 0, column < board.columns, row >= 0, row < board.rows else { return false }
    let index = row * board.columns + column
    switch board[column, row] {
    case .covered:
      return true
    case .revealed:
      return revealProgress(for: index) <= 0
    case .mine(let triggered):
      return triggered ? revealProgress(for: index) <= 0 : true
    case .flagged:
      return revealProgress(for: index) <= 0
    case .flaggedMine, .wrongFlag:
      return false
    }
  }

  private func visuallyRevealed(column: Int, row: Int) -> Bool {
    guard column >= 0, column < board.columns, row >= 0, row < board.rows else { return false }
    let index = row * board.columns + column
    guard revealProgress(for: index) > 0 else { return false }
    switch board[column, row] {
    case .revealed, .wrongFlag:
      return true
    case .covered, .flagged, .flaggedMine, .mine:
      return false
    }
  }

  /// At a grid vertex occupied by three covered cells and one revealed cell,
  /// the full-width adjacency bridges form a sharp inward corner. Extend the
  /// covered region into the revealed quadrant with a true circular quarter;
  /// its tangent-continuous arc avoids the pinched corners produced by the old
  /// quadratic approximation, especially around one isolated revealed cell.
  private func drawConcaveCoverCutouts(
    firstColumn: Int,
    lastColumn: Int,
    firstRow: Int,
    lastRow: Int
  ) {
    let radius = Self.baseCellSize * 0.09
    palette.covered.setFill()

    for vertexRow in max(1, firstRow)...min(board.rows - 1, lastRow + 1) {
      for vertexColumn in max(1, firstColumn)...min(board.columns - 1, lastColumn + 1) {
        let quadrants = [
          (column: vertexColumn - 1, row: vertexRow - 1, sx: -1.0, sy: -1.0),
          (column: vertexColumn, row: vertexRow - 1, sx: 1.0, sy: -1.0),
          (column: vertexColumn - 1, row: vertexRow, sx: -1.0, sy: 1.0),
          (column: vertexColumn, row: vertexRow, sx: 1.0, sy: 1.0),
        ]
        let covered = quadrants.map { visuallyCovered(column: $0.column, row: $0.row) }
        guard covered.filter({ $0 }).count == 3,
          let missing = covered.firstIndex(of: false)
        else { continue }
        let quadrant = quadrants[missing]
        guard visuallyRevealed(column: quadrant.column, row: quadrant.row) else { continue }

        let vertex = CGPoint(
          x: CGFloat(vertexColumn) * Self.baseCellSize,
          y: CGFloat(vertexRow) * Self.baseCellSize
        )
        let verticalTangent = CGPoint(
          x: vertex.x,
          y: vertex.y + CGFloat(quadrant.sy) * radius
        )
        let horizontalTangent = CGPoint(
          x: vertex.x + CGFloat(quadrant.sx) * radius,
          y: vertex.y
        )
        let kappa: CGFloat = 0.552_284_75
        let firstControl = CGPoint(
          x: vertex.x,
          y: vertex.y + CGFloat(quadrant.sy) * radius * (1 - kappa)
        )
        let secondControl = CGPoint(
          x: vertex.x + CGFloat(quadrant.sx) * radius * (1 - kappa),
          y: vertex.y
        )
        let cutout = UIBezierPath()
        cutout.move(to: vertex)
        cutout.addLine(to: verticalTangent)
        cutout.addCurve(
          to: horizontalTangent,
          controlPoint1: firstControl,
          controlPoint2: secondControl
        )
        cutout.close()
        cutout.fill()
      }
    }
  }

  private func cellRect(column: Int, row: Int) -> CGRect {
    CGRect(
      x: CGFloat(column) * Self.baseCellSize,
      y: CGFloat(row) * Self.baseCellSize,
      width: Self.baseCellSize,
      height: Self.baseCellSize
    )
  }

  private func drawFlagCoveredBackdrop(column: Int, row: Int, radius: CGFloat) {
    let rect = cellRect(column: column, row: row)
    for rowDirection in [-1, 1] {
      for columnDirection in [-1, 1] {
        // The rounded flag moat exposes its backing only at the corner. That
        // corner belongs to the covered field when covered cells wrap around
        // it on both incident sides. Treating either side (or only a diagonal)
        // as sufficient leaked tiny covered-color wedges onto revealed edges,
        // most visibly beneath a flag that protrudes from the covered slab.
        let horizontalCovered = visuallyCovered(
          column: column + columnDirection,
          row: row
        )
        let verticalCovered = visuallyCovered(
          column: column,
          row: row + rowDirection
        )
        // When another flag occupies the opposite diagonal, the two incident
        // covered cells are themselves diagonal-only neighbors. The source
        // keeps all four rounded corners independent at that vertex; painting
        // this backing square would manufacture the tiny covered-color spark
        // between the flags.
        let diagonalIsFlag = isFlagLike(
          column: column + columnDirection,
          row: row + rowDirection
        )
        guard horizontalCovered && verticalCovered && !diagonalIsFlag else { continue }
        UIRectFill(CGRect(
          x: columnDirection < 0 ? rect.minX : rect.maxX - radius,
          y: rowDirection < 0 ? rect.minY : rect.maxY - radius,
          width: radius,
          height: radius
        ))
      }
    }
  }

  private func isFlagLike(column: Int, row: Int) -> Bool {
    guard column >= 0, column < board.columns, row >= 0, row < board.rows else { return false }
    switch board[column, row] {
    case .flagged, .flaggedMine, .wrongFlag: return true
    default: return false
    }
  }

  private func drawClearingOverlay(in rect: CGRect, progress: CGFloat) {
    guard progress < 1 else { return }
    guard let context = UIGraphicsGetCurrentContext() else { return }
    let eased = Self.smoothStep(progress)
    let scale = max(0.04, 1 - eased * 0.96)
    let alpha = progress < 0.9 ? 1 : max(0, (1 - progress) / 0.1)
    // Do not pop a connected region into a pre-gapped matrix on frame one.
    // Android opens the seams progressively before the individual tiles
    // contract, which keeps the board reading as one continuous surface.
    let seamProgress = min(1, max(0, progress / 0.22))
    let seamInset = Self.baseCellSize * 0.08 * Self.smoothStep(seamProgress)
    let coveredRect = showsBorders
      ? rect.insetBy(dx: 0.55, dy: 0.55)
      : rect.insetBy(dx: seamInset, dy: seamInset)
    let width = coveredRect.width * scale
    let height = coveredRect.height * scale
    let overlay = CGRect(
      x: coveredRect.midX - width / 2,
      y: coveredRect.midY - height / 2,
      width: width,
      height: height
    )
    context.saveGState()
    context.setAlpha(alpha)
    palette.covered.setFill()
    let roundedSquareRadius = Self.baseCellSize * 0.09 * seamProgress * scale
    // Once a clearing tile is small, continue its contraction as a dot. A
    // proportionally shrinking rounded rectangle leaves a conspicuous tiny
    // square on final moves; the source resolves these late frames into the
    // same circular visual language as its touch ripple.
    let dotProgress = Self.smoothStep(min(1, max(0, (progress - 0.38) / 0.42)))
    let dotRadius = min(overlay.width, overlay.height) / 2
    let radius = roundedSquareRadius + (dotRadius - roundedSquareRadius) * dotProgress
    if progress <= 0 {
      drawConnectedCover(
        in: rect,
        fillRect: overlay,
        radius: radius,
        column: Int(rect.minX / Self.baseCellSize),
        row: Int(rect.minY / Self.baseCellSize),
        scale: scale
      )
    } else if radius > 0 {
      UIBezierPath(roundedRect: overlay, cornerRadius: radius).fill()
    } else {
      UIRectFill(overlay)
    }
    context.restoreGState()
  }

  private func drawNumber(_ number: Int, in rect: CGRect, scale: CGFloat) {
    let color =
      palette.clues.indices.contains(number - 1) ? palette.clues[number - 1] : palette.foreground
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont(name: "Rubik-Regular", size: Self.baseCellSize * 0.58 * scale)
        ?? UIFont.systemFont(ofSize: Self.baseCellSize * 0.58 * scale, weight: .regular),
      .foregroundColor: color,
    ]
    let string = NSString(string: "\(number)")
    let size = string.size(withAttributes: attributes)
    string.draw(
      at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
      withAttributes: attributes
    )
  }

  private func revealProgress(for index: Int) -> CGFloat {
    guard let start = revealStartedAt[index] else { return 1 }
    let elapsed = (renderTimestamp ?? CACurrentMediaTime()) - start
    if elapsed < 0 { return 0 }
    let duration = revealDurations[index] ?? 0.24 * Self.durationScale(for: animationSpeed)
    return CGFloat(min(1, elapsed / duration))
  }

  private func numberScale(for progress: CGFloat) -> CGFloat {
    guard progress < 1 else { return 1 }
    return 0.72 + Self.smoothStep(progress) * 0.28
  }

  private func maintainDisplayLink() {
    let now = CACurrentMediaTime()
    updatePaletteAnimation(at: now)
    if let startedAt = initialRevealStartedAt,
      now - startedAt >= initialRevealDuration
    {
      initialRevealStartedAt = nil
      initialRevealOrigin = nil
      initialRevealDuration = 0
    }
    if let startedAt = restartStartedAt,
      now - startedAt >= restartDuration
    {
      restartSnapshot = nil
      restartStartedAt = nil
      restartDuration = 0
    }
    let retention = 0.72 * Self.durationScale(for: animationSpeed)
    revealStartedAt = revealStartedAt.filter { now - $0.value < retention }
    let activeIndices = Set(revealStartedAt.keys)
    revealDurations = revealDurations.filter { activeIndices.contains($0.key) }
    if revealStartedAt.isEmpty,
      paletteTransitionStartedAt == nil,
      initialRevealStartedAt == nil,
      restartStartedAt == nil
    {
      displayLink?.invalidate()
      displayLink = nil
    } else if displayLink == nil {
      displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
      displayLink?.preferredFrameRateRange = CAFrameRateRange(
        minimum: 60,
        maximum: 120,
        preferred: 120
      )
      displayLink?.add(to: .main, forMode: .common)
    }
  }

  private static func durationScale(for speedPercent: Double) -> Double {
    guard speedPercent > 0 else { return 0.01 }
    return 100 / min(150, max(5, speedPercent))
  }

  private static func smoothStep(_ value: CGFloat) -> CGFloat {
    let clamped = min(1, max(0, value))
    return clamped * clamped * (3 - 2 * clamped)
  }

  @objc private func animationTick() {
    maintainDisplayLink()
    setNeedsDisplay()
  }

  private func updatePalette(to revised: BoardPalette, at now: CFTimeInterval) {
    guard hasReceivedPalette else {
      hasReceivedPalette = true
      palette = revised
      targetPalette = revised
      return
    }
    guard !targetPalette.matches(revised) else { return }
    updatePaletteAnimation(at: now)
    targetPalette = revised
    guard animationSpeed > 0, !UIAccessibility.isReduceMotionEnabled else {
      palette = revised
      paletteTransitionFrom = nil
      paletteTransitionStartedAt = nil
      return
    }
    paletteTransitionFrom = palette
    paletteTransitionStartedAt = now
  }

  private func updatePaletteAnimation(at now: CFTimeInterval) {
    guard let startedAt = paletteTransitionStartedAt, let from = paletteTransitionFrom else { return }
    let duration = 0.45 * Self.durationScale(for: animationSpeed)
    let progress = CGFloat(min(1, max(0, (now - startedAt) / duration)))
    palette = from.interpolated(to: targetPalette, progress: progress)
    if progress >= 1 {
      palette = targetPalette
      paletteTransitionFrom = nil
      paletteTransitionStartedAt = nil
    }
  }

  private func drawFlag(in rect: CGRect, color: UIColor, scale: CGFloat = 1) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -rect.midX, y: -rect.midY)
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + rect.width * x / 24, y: rect.minY + rect.height * y / 24)
    }
    // Filled Material flag silhouette used by the Android reference.
    let path = UIBezierPath()
    path.move(to: point(14.4, 6))
    path.addLine(to: point(14, 4))
    path.addLine(to: point(5, 4))
    path.addLine(to: point(5, 21))
    path.addLine(to: point(7, 21))
    path.addLine(to: point(7, 14))
    path.addLine(to: point(12.6, 14))
    path.addLine(to: point(13, 16))
    path.addLine(to: point(20, 16))
    path.addLine(to: point(20, 6))
    path.close()
    color.setFill()
    path.fill()
    context.restoreGState()
  }

  private func drawMine(in rect: CGRect, color: UIColor, holeColor: UIColor, scale: CGFloat = 1) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -rect.midX, y: -rect.midY)
    context.setFillColor(color.cgColor)
    let radius = rect.width * 0.18
    context.fillEllipse(
      in: CGRect(
        x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    for index in 0..<8 {
      let angle = CGFloat(index) * .pi / 4
      context.saveGState()
      context.translateBy(x: rect.midX, y: rect.midY)
      context.rotate(by: angle)
      let tooth = CGRect(
        x: radius * 0.72,
        y: -rect.width * 0.040,
        width: radius * 0.84,
        height: rect.width * 0.080
      )
      UIBezierPath(
        roundedRect: tooth,
        cornerRadius: rect.width * 0.040
      ).fill()
      context.restoreGState()
    }
    context.setFillColor(holeColor.cgColor)
    let holeSize = rect.width * 0.115
    context.fill(
      CGRect(
        x: rect.midX - holeSize / 2, y: rect.midY - holeSize / 2, width: holeSize, height: holeSize)
    )
    context.restoreGState()
  }

  private func drawCross(in rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.setStrokeColor(palette.mine.cgColor)
    context.setLineWidth(rect.width * 0.055)
    context.setLineCap(.round)
    let inset = rect.width * 0.30
    context.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
    context.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
    context.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
    context.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
    context.strokePath()
  }

  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard restartStartedAt == nil,
      recognizer.state == .ended,
      let coordinate = coordinate(at: recognizer.location(in: self))
    else { return }
    onTap?(coordinate.column, coordinate.row)
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard restartStartedAt == nil,
      recognizer.state == .began,
      let coordinate = coordinate(at: recognizer.location(in: self))
    else { return }
    onLongPress?(coordinate.column, coordinate.row)
  }

  private func coordinate(at point: CGPoint) -> (column: Int, row: Int)? {
    let column = Int(floor(point.x / Self.baseCellSize))
    let row = Int(floor(point.y / Self.baseCellSize))
    guard column >= 0, column < board.columns, row >= 0, row < board.rows else { return nil }
    return (column, row)
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    false
  }
}
