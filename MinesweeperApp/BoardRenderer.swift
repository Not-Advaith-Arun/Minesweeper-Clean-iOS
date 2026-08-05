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
    background.isVisuallyDark ? background : foreground
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

  var isVisuallyDark: Bool { relativeLuminance < 0.20 }

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
    self.board = board
    self.phase = phase
    self.isLoading = isLoading
    self.showsBorders = showsBorders
    self.animationSpeed = animationSpeed
    let now = CACurrentMediaTime()
    updatePalette(to: palette, at: now)
    let distanceScale = Self.durationScale(for: animationSpeed)
    for coordinate in changedCoordinates {
      let index = coordinate.row * board.columns + coordinate.column
      guard board.cells.indices.contains(index) else { continue }
      if oldBoard.cells.indices.contains(index), oldBoard.cells[index] != board.cells[index] {
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
      drawReadyBoard(in: bounds)
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
        guard case .covered = board[column, row] else { continue }
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
    drawDiagonalCoverConnectors(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow
    )
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
      drawGridLine(in: rect, context: context)
      if count > 0 { drawNumber(count, in: rect, scale: revealScale) }
      drawClearingOverlay(in: rect, progress: progress)
    case .flagged:
      palette.flagged.setFill()
      drawConnectedCover(
        in: rect,
        fillRect: inset,
        radius: radius,
        column: column,
        row: row,
        scale: 1,
        matchesNeighbor: { [self] column, row in
          isFlagged(column: column, row: row)
        }
      )
      drawFlag(
        in: rect,
        color: palette.flagGlyph,
        scale: flagScale(for: progress) * 0.55
      )
      // Clean One morphs the covered surface away to expose the flag tile.
      // Reusing the reveal mask keeps the tile, its rounded boundary and the
      // glyph on one animation clock instead of popping topology immediately.
      drawClearingOverlay(in: rect, progress: progress)
    case .mine(let triggered):
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
      if triggered {
        palette.mine.setFill()
        UIBezierPath(roundedRect: inset, cornerRadius: radius).fill()
      }
      drawMine(
        in: rect,
        color: triggered ? palette.background : palette.mine,
        holeColor: triggered ? palette.mine : palette.surface,
        scale: numberScale(for: progress)
      )
      drawClearingOverlay(in: rect, progress: progress)
    case .wrongFlag:
      palette.flagged.withAlphaComponent(0.56).setFill()
      drawConnectedCover(
        in: rect,
        fillRect: inset,
        radius: radius,
        column: column,
        row: row,
        scale: 1,
        matchesNeighbor: { [self] column, row in isFlagLike(column: column, row: row) }
      )
      drawFlag(in: rect, color: palette.flagGlyph, scale: 0.55)
      drawCross(in: rect)
    }

    if showsBorders {
      context.setStrokeColor(palette.separator.cgColor)
      context.setLineWidth(0.7)
      context.stroke(inset)
    }
  }

  private func drawReadyBoard(in rect: CGRect) {
    let boardRect = rect
    palette.covered.setFill()
    UIBezierPath(
      roundedRect: boardRect,
      cornerRadius: min(boardRect.width, boardRect.height) * 0.012
    ).fill()

    let attributes: [NSAttributedString.Key: Any] = [
      // The ready board is fitted to the viewport, so derive type from canvas
      // width as well. This keeps the rendered prompt the same size on Easy,
      // Medium and the taller boards instead of making it huge on Easy.
      .font: UIFont(name: "Rubik-Regular", size: rect.width * 0.045)
        ?? UIFont.systemFont(ofSize: rect.width * 0.045, weight: .regular),
      .foregroundColor: palette.background.withAlphaComponent(0.56),
    ]
    // Normal board generation completes within a frame. Retain the Android
    // prompt instead of flashing a one-frame loading label before the reveal.
    let string = NSString(string: "Tap to begin.")
    let size = string.size(withAttributes: attributes)
    string.draw(
      at: CGPoint(x: boardRect.midX - size.width / 2, y: boardRect.midY - size.height / 2),
      withAttributes: attributes
    )
  }

  private func drawGridLine(in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.setStrokeColor(palette.separator.withAlphaComponent(0.23).cgColor)
    context.setLineWidth(1.15)
    let gap = Self.baseCellSize * 0.19
    context.move(to: CGPoint(x: rect.minX + gap, y: rect.maxY - 0.5))
    context.addLine(to: CGPoint(x: rect.maxX - gap, y: rect.maxY - 0.5))
    context.move(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + gap))
    context.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.maxY - gap))
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
    case .revealed, .mine:
      return revealProgress(for: index) <= 0
    case .flagged, .wrongFlag:
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
    case .covered, .flagged, .mine:
      return false
    }
  }

  /// At a grid vertex occupied by three covered cells and one revealed cell,
  /// the full-width adjacency bridges form a sharp inward corner. Extend the
  /// covered region into the revealed quadrant with a quadratic quarter-round;
  /// its arc joins the two boundary rays without a pointed cutout.
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
        let cutout = UIBezierPath()
        cutout.move(to: vertex)
        cutout.addLine(to: verticalTangent)
        cutout.addQuadCurve(to: horizontalTangent, controlPoint: vertex)
        cutout.close()
        cutout.fill()
      }
    }
  }

  /// Clean One keeps diagonally touching covered cells in the same visual
  /// mass. Join the two rounded corners with a compact circular neck, while
  /// leaving genuinely isolated cells rounded on all four sides.
  private func drawDiagonalCoverConnectors(
    firstColumn: Int,
    lastColumn: Int,
    firstRow: Int,
    lastRow: Int
  ) {
    let radius = Self.baseCellSize * 0.09
    palette.covered.setFill()

    for vertexRow in max(1, firstRow)...min(board.rows - 1, lastRow + 1) {
      for vertexColumn in max(1, firstColumn)...min(board.columns - 1, lastColumn + 1) {
        let northwest = visuallyCovered(column: vertexColumn - 1, row: vertexRow - 1)
        let northeast = visuallyCovered(column: vertexColumn, row: vertexRow - 1)
        let southwest = visuallyCovered(column: vertexColumn - 1, row: vertexRow)
        let southeast = visuallyCovered(column: vertexColumn, row: vertexRow)
        let diagonalPair = (northwest && southeast && !northeast && !southwest)
          || (northeast && southwest && !northwest && !southeast)
        guard diagonalPair else { continue }

        let vertex = CGPoint(
          x: CGFloat(vertexColumn) * Self.baseCellSize,
          y: CGFloat(vertexRow) * Self.baseCellSize
        )
        UIBezierPath(
          ovalIn: CGRect(
            x: vertex.x - radius,
            y: vertex.y - radius,
            width: radius * 2,
            height: radius * 2
          )
        ).fill()
      }
    }
  }

  private func isFlagged(column: Int, row: Int) -> Bool {
    guard column >= 0, column < board.columns, row >= 0, row < board.rows else { return false }
    if case .flagged = board[column, row] { return true }
    return false
  }

  private func isFlagLike(column: Int, row: Int) -> Bool {
    guard column >= 0, column < board.columns, row >= 0, row < board.rows else { return false }
    switch board[column, row] {
    case .flagged, .wrongFlag: return true
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
    let radius = Self.baseCellSize * 0.09 * seamProgress * scale
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
    let duration = 0.24 * Self.durationScale(for: animationSpeed)
    return CGFloat(min(1, elapsed / duration))
  }

  private func numberScale(for progress: CGFloat) -> CGFloat {
    guard progress < 1 else { return 1 }
    return 0.72 + Self.smoothStep(progress) * 0.28
  }

  private func flagScale(for progress: CGFloat) -> CGFloat {
    guard progress < 1 else { return 1 }
    return 0.78 + Self.smoothStep(progress) * 0.22
  }

  private func maintainDisplayLink() {
    let now = CACurrentMediaTime()
    updatePaletteAnimation(at: now)
    let retention = 0.72 * Self.durationScale(for: animationSpeed)
    revealStartedAt = revealStartedAt.filter { now - $0.value < retention }
    if revealStartedAt.isEmpty, paletteTransitionStartedAt == nil {
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
    guard recognizer.state == .ended, let coordinate = coordinate(at: recognizer.location(in: self))
    else { return }
    onTap?(coordinate.column, coordinate.row)
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let coordinate = coordinate(at: recognizer.location(in: self))
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
