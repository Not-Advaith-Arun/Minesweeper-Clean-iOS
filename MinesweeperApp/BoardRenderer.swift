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
}

final class BoardViewport: UIScrollView, UIScrollViewDelegate {
  let canvas = BoardCanvasView()
  private var lastGridSize = CGSize.zero
  private var lastPhase: ReplicaGamePhase = .ready
  private var hasAppliedInitialZoom = false
  private var pendingFocusCoordinate: CellCoordinate?

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
    if lastPhase == .ready, phase == .playing {
      pendingFocusCoordinate = actionCoordinate
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
    let fit = min(fitWidth, fitHeight)
    minimumZoomScale = min(fit, fitWidth)
    maximumZoomScale = max(minimumZoomScale, 4.0)
    if !hasAppliedInitialZoom {
      zoomScale = minimumZoomScale
      hasAppliedInitialZoom = true
    } else if zoomScale < minimumZoomScale {
      zoomScale = minimumZoomScale
    }
    centerContent()
    applyPendingFocusIfNeeded()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

  private func centerContent() {
    let horizontal = max(0, (bounds.width - contentSize.width) / 2)
    let vertical = max(0, (bounds.height - contentSize.height) / 2)
    contentInset = UIEdgeInsets(
      top: vertical, left: horizontal, bottom: vertical, right: horizontal)
  }

  private func applyPendingFocusIfNeeded() {
    guard let coordinate = pendingFocusCoordinate, bounds.width > 0, bounds.height > 0 else { return }
    pendingFocusCoordinate = nil
    let targetZoom = max(minimumZoomScale, min(maximumZoomScale, 1.38))
    let center = CGPoint(
      x: (CGFloat(coordinate.column) + 0.5) * BoardCanvasView.baseCellSize,
      y: (CGFloat(coordinate.row) + 0.5) * BoardCanvasView.baseCellSize
    )
    DispatchQueue.main.async {
      self.setZoomScale(targetZoom, animated: true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        let size = self.bounds.size
        let offset = CGPoint(
          x: center.x * self.zoomScale - size.width / 2,
          y: center.y * self.zoomScale - size.height / 2
        )
        self.setContentOffset(self.boundedOffset(offset), animated: true)
      }
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
  private var showsBorders = false
  private var animationSpeed = 100.0
  private var revealStartedAt: [Int: CFTimeInterval] = [:]
  private var displayLink: CADisplayLink?

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
    self.palette = palette
    self.showsBorders = showsBorders
    self.animationSpeed = animationSpeed
    let now = CACurrentMediaTime()
    let distanceScale = Self.durationScale(for: animationSpeed)
    for coordinate in changedCoordinates {
      let index = coordinate.row * board.columns + coordinate.column
      guard board.cells.indices.contains(index) else { continue }
      if oldBoard.cells.indices.contains(index), oldBoard.cells[index] != board.cells[index] {
        let distance =
          actionCoordinate.map {
            max(abs(coordinate.row - $0.row), abs(coordinate.column - $0.column))
          } ?? 0
        revealStartedAt[index] =
          now + min(0.26, Double(distance) * 0.014 * distanceScale)
      }
    }
    accessibilityLabel = "Minesweeper board, \(board.columns) columns by \(board.rows) rows"
    maintainDisplayLink()
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.setFillColor(palette.background.cgColor)
    context.fill(rect)

    if phase == .ready {
      drawReadyBoard(in: bounds)
      return
    }

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
  }

  private func drawCell(_ cell: BoardCellVisual, column: Int, row: Int, context: CGContext) {
    let rect = CGRect(
      x: CGFloat(column) * Self.baseCellSize,
      y: CGFloat(row) * Self.baseCellSize,
      width: Self.baseCellSize,
      height: Self.baseCellSize
    )
    let index = row * board.columns + column
    let inset = showsBorders ? rect.insetBy(dx: 0.55, dy: 0.55) : rect
    let radius = showsBorders ? 0 : 0
    let progress = revealProgress(for: index)
    let revealScale = numberScale(for: progress)

    switch cell {
    case .covered:
      palette.covered.setFill()
      fillCoveredCell(inset, radius: radius)
    case .revealed(let count):
      context.setFillColor(palette.surface.cgColor)
      context.fill(rect)
      drawGridLine(in: rect, context: context)
      if count > 0 { drawNumber(count, in: rect, scale: revealScale) }
      drawClearingOverlay(in: rect, progress: progress)
    case .flagged:
      palette.flagged.setFill()
      fillCoveredCell(inset, radius: radius)
      drawFlag(in: rect, color: palette.foreground)
    case .mine(let triggered):
      context.setFillColor((triggered ? palette.mine : palette.background).cgColor)
      context.fill(rect)
      drawMine(
        in: rect,
        color: triggered ? palette.background : palette.mine,
        holeColor: triggered ? palette.mine : palette.background
      )
    case .wrongFlag:
      context.setFillColor(palette.surface.cgColor)
      context.fill(rect)
      drawGridLine(in: rect, context: context)
      drawFlag(in: rect, color: palette.muted)
      drawCross(in: rect)
    }

    if showsBorders {
      context.setStrokeColor(palette.separator.cgColor)
      context.setLineWidth(0.7)
      context.stroke(inset)
    }
  }

  private func drawReadyBoard(in rect: CGRect) {
    let boardRect = rect.insetBy(dx: Self.baseCellSize * 0.35, dy: Self.baseCellSize * 0.55)
    palette.covered.setFill()
    UIBezierPath(roundedRect: boardRect, cornerRadius: Self.baseCellSize * 0.72).fill()

    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont(name: "Rubik-Regular", size: Self.baseCellSize * 0.52)
        ?? UIFont.systemFont(ofSize: Self.baseCellSize * 0.52, weight: .regular),
      .foregroundColor: palette.foreground.withAlphaComponent(0.42),
    ]
    let string = NSString(string: isLoading ? "Preparing..." : "Tap to begin.")
    let size = string.size(withAttributes: attributes)
    string.draw(
      at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
      withAttributes: attributes
    )
  }

  private func drawGridLine(in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.setStrokeColor(palette.separator.withAlphaComponent(0.23).cgColor)
    context.setLineWidth(1.15)
    let gap = Self.baseCellSize * 0.22
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

  private func drawClearingOverlay(in rect: CGRect, progress: CGFloat) {
    guard progress < 1, progress > 0 else { return }
    guard let context = UIGraphicsGetCurrentContext() else { return }
    let eased = Self.easeOutCubic(progress)
    let scale = max(0.08, 1 - eased * 0.78)
    let alpha = max(0, 1 - eased)
    let width = rect.width * scale
    let height = rect.height * scale
    let overlay = CGRect(
      x: rect.midX - width / 2,
      y: rect.midY - height / 2,
      width: width,
      height: height
    )
    context.saveGState()
    context.setAlpha(alpha)
    palette.covered.setFill()
    UIBezierPath(roundedRect: overlay, cornerRadius: rect.width * 0.11 * scale).fill()
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
    let elapsed = CACurrentMediaTime() - start
    if elapsed < 0 { return 0 }
    let duration = 0.2 * Self.durationScale(for: animationSpeed)
    return CGFloat(min(1, elapsed / duration))
  }

  private func numberScale(for progress: CGFloat) -> CGFloat {
    guard progress < 1 else { return 1 }
    return 0.72 + Self.easeOutCubic(progress) * 0.28
  }

  private func maintainDisplayLink() {
    let now = CACurrentMediaTime()
    let retention = 0.62 * Self.durationScale(for: animationSpeed)
    revealStartedAt = revealStartedAt.filter { now - $0.value < retention }
    if revealStartedAt.isEmpty {
      displayLink?.invalidate()
      displayLink = nil
    } else if displayLink == nil {
      displayLink = CADisplayLink(target: self, selector: #selector(animationTick))
      displayLink?.add(to: .main, forMode: .common)
    }
  }

  private static func durationScale(for speedPercent: Double) -> Double {
    guard speedPercent > 0 else { return 0.01 }
    return 100 / min(150, max(5, speedPercent))
  }

  private static func easeOutCubic(_ value: CGFloat) -> CGFloat {
    let clamped = min(1, max(0, value))
    let inverse = 1 - clamped
    return 1 - inverse * inverse * inverse
  }

  @objc private func animationTick() {
    maintainDisplayLink()
    setNeedsDisplay()
  }

  private func drawFlag(in rect: CGRect, color: UIColor) {
    let path = UIBezierPath()
    let poleX = rect.minX + rect.width * 0.43
    path.move(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.22))
    path.addLine(to: CGPoint(x: poleX, y: rect.maxY - rect.height * 0.22))
    path.move(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.24))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.20, y: rect.minY + rect.height * 0.37))
    path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.50))
    path.close()
    color.setStroke()
    color.setFill()
    path.lineWidth = 2.1
    path.lineCapStyle = .round
    path.stroke()
    path.fill()

    let base = UIBezierPath()
    base.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.maxY - rect.height * 0.20))
    base.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.27, y: rect.maxY - rect.height * 0.20))
    base.lineWidth = 2.1
    base.lineCapStyle = .round
    base.stroke()
  }

  private func drawMine(in rect: CGRect, color: UIColor, holeColor: UIColor) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.setStrokeColor(color.cgColor)
    context.setFillColor(color.cgColor)
    context.setLineWidth(1.8)
    context.setLineCap(.round)
    let radius = rect.width * 0.22
    context.fillEllipse(
      in: CGRect(
        x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    for index in 0..<8 {
      let angle = CGFloat(index) * .pi / 4
      context.move(
        to: CGPoint(
          x: rect.midX + cos(angle) * radius * 0.75, y: rect.midY + sin(angle) * radius * 0.75))
      context.addLine(
        to: CGPoint(
          x: rect.midX + cos(angle) * radius * 1.65, y: rect.midY + sin(angle) * radius * 1.65))
    }
    context.strokePath()
    context.setFillColor(holeColor.cgColor)
    let holeSize = rect.width * 0.13
    context.fill(
      CGRect(
        x: rect.midX - holeSize / 2, y: rect.midY - holeSize / 2, width: holeSize, height: holeSize)
    )
    context.restoreGState()
  }

  private func drawCross(in rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.setStrokeColor(palette.mine.cgColor)
    context.setLineWidth(2.3)
    context.setLineCap(.round)
    let inset = rect.width * 0.24
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
