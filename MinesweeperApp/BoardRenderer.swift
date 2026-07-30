import SwiftUI
import UIKit

struct BoardRenderer: UIViewRepresentable {
  let board: BoardPresentation
  let theme: AppTheme
  let showsBorders: Bool
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
      palette: BoardPalette(theme: theme),
      showsBorders: showsBorders
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
  private var hasAppliedInitialZoom = false

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

  func update(board: BoardPresentation, palette: BoardPalette, showsBorders: Bool) {
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
    canvas.update(board: board, palette: palette, showsBorders: showsBorders)
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, lastGridSize.width > 0 else { return }
    let fitWidth = bounds.width / lastGridSize.width
    let fitHeight = bounds.height / lastGridSize.height
    let fit = min(fitWidth, fitHeight)
    minimumZoomScale = min(fit, fitWidth)
    maximumZoomScale = max(minimumZoomScale, 3.5)
    if !hasAppliedInitialZoom {
      zoomScale = minimumZoomScale
      hasAppliedInitialZoom = true
    } else if zoomScale < minimumZoomScale {
      zoomScale = minimumZoomScale
    }
    centerContent()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }

  private func centerContent() {
    let horizontal = max(0, (bounds.width - contentSize.width) / 2)
    let vertical = max(0, (bounds.height - contentSize.height) / 2)
    contentInset = UIEdgeInsets(
      top: vertical, left: horizontal, bottom: vertical, right: horizontal)
  }
}

final class BoardCanvasView: UIView, UIGestureRecognizerDelegate {
  static let baseCellSize: CGFloat = 28

  var onTap: ((Int, Int) -> Void)?
  var onLongPress: ((Int, Int) -> Void)?
  private var board = BoardPresentation(columns: 1, rows: 1)
  private var palette = BoardPalette(theme: ThemeCatalog.fallback)
  private var showsBorders = false

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

  func update(board: BoardPresentation, palette: BoardPalette, showsBorders: Bool) {
    self.board = board
    self.palette = palette
    self.showsBorders = showsBorders
    accessibilityLabel = "Minesweeper board, \(board.columns) columns by \(board.rows) rows"
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.setFillColor(palette.background.cgColor)
    context.fill(rect)

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
    let inset = showsBorders ? rect.insetBy(dx: 0.55, dy: 0.55) : rect

    switch cell {
    case .covered:
      context.setFillColor(palette.covered.cgColor)
      context.fill(inset)
    case .revealed(let count):
      context.setFillColor(palette.surface.cgColor)
      context.fill(rect)
      if count > 0 { drawNumber(count, in: rect) }
    case .flagged:
      context.setFillColor(palette.flagged.cgColor)
      context.fill(inset)
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
      drawFlag(in: rect, color: palette.muted)
      drawCross(in: rect)
    }

    if showsBorders {
      context.setStrokeColor(palette.separator.cgColor)
      context.setLineWidth(0.7)
      context.stroke(inset)
    }
  }

  private func drawNumber(_ number: Int, in rect: CGRect) {
    let color =
      palette.clues.indices.contains(number - 1) ? palette.clues[number - 1] : palette.foreground
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont(name: "Rubik-Medium", size: Self.baseCellSize * 0.56)
        ?? UIFont.systemFont(ofSize: Self.baseCellSize * 0.56, weight: .medium),
      .foregroundColor: color,
    ]
    let string = NSString(string: "\(number)")
    let size = string.size(withAttributes: attributes)
    string.draw(
      at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
      withAttributes: attributes
    )
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
