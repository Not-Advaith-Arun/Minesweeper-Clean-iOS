import SwiftUI
import UIKit
import MinesweeperCore

struct BoardRenderer: UIViewRepresentable {
  let board: BoardPresentation
  let phase: ReplicaGamePhase
  let isLoading: Bool
  let changedCoordinates: Set<CellCoordinate>
  let actionCoordinate: CellCoordinate?
  let fixedStartCoordinate: CellCoordinate?
  let isFixedStartEnabled: Bool
  let theme: AppTheme
  let showsBorders: Bool
  let animationSpeed: Double
  let isReplayCovering: Bool
  let replayCoverSequence: Int
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
      fixedStartCoordinate: fixedStartCoordinate,
      isFixedStartEnabled: isFixedStartEnabled,
      palette: BoardPalette(theme: theme),
      showsBorders: showsBorders,
      animationSpeed: animationSpeed,
      isReplayCovering: isReplayCovering,
      replayCoverSequence: replayCoverSequence
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
  let gridLine: UIColor

  var coveredText: UIColor {
    if background.contrastRatio(with: covered) >= 4.5 { return background }
    return [foreground, UIColor.black, UIColor.white].max {
      $0.contrastRatio(with: covered) < $1.contrastRatio(with: covered)
    } ?? foreground
  }

  var flagGlyph: UIColor {
    // Clean One normally lets the page/background color supply the dark flag
    // silhouette. Some themes, however, pair a dark background with an almost
    // equally dark flagged surface. Preserve the themed choice when it is
    // legible and fall back to the highest-contrast neutral when it is not.
    if background.contrastRatio(with: flagged) >= 4.5 { return background }
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

  var fixedStartMarker: UIColor {
    // Prefer the theme accent for the single prescribed opening, but retain a
    // strong neutral fallback for palettes whose accent is close to Covered.
    if accent.contrastRatio(with: covered) >= 3 { return accent }
    return [foreground, background, UIColor.black, UIColor.white].max {
      $0.contrastRatio(with: covered) < $1.contrastRatio(with: covered)
    } ?? foreground
  }

  private static func gridLine(
    surface: UIColor, separator: UIColor, foreground: UIColor, background: UIColor
  ) -> UIColor {
    // Reference separators sit quietly behind the clues. Some custom themes
    // use their text-muted color as a fallback separator; drawing it at full
    // strength creates a high-contrast wire grid across an AMOLED board.
    let neutral = foreground.contrastRatio(with: surface)
      >= background.contrastRatio(with: surface) ? foreground : background
    let target = separator.contrastRatio(with: surface) >= 1.22 ? separator : neutral
    var lower: CGFloat = 0
    var upper: CGFloat = 1
    for _ in 0..<12 {
      let midpoint = (lower + upper) / 2
      let candidate = surface.interpolated(to: target, progress: midpoint)
      if candidate.contrastRatio(with: surface) < 1.22 {
        lower = midpoint
      } else {
        upper = midpoint
      }
    }
    return surface.interpolated(to: target, progress: upper)
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
    gridLine = Self.gridLine(
      surface: surface, separator: separator, foreground: foreground, background: background)
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
    self.gridLine = Self.gridLine(
      surface: surface, separator: separator, foreground: foreground, background: background)
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
  private enum CameraAnimationKind {
    case focus
    case restart
    case terminal
  }

  private struct CameraAnimationState {
    let kind: CameraAnimationKind
    let startedAt: CFTimeInterval
    let duration: CFTimeInterval
    let startZoom: CGFloat
    let targetZoom: CGFloat
    let startOffset: CGPoint
    let targetOffset: CGPoint
    let startInset: UIEdgeInsets
    let targetInset: UIEdgeInsets
  }

  let canvas = BoardCanvasView()
  private var lastGridSize = CGSize.zero
  private var lastPhase: ReplicaGamePhase = .ready
  private var hasAppliedInitialZoom = false
  private var pendingFocusCoordinate: CellCoordinate?
  private var focusWorkItem: DispatchWorkItem?
  private var cameraAnimation: CameraAnimationState?
  private var cameraDisplayLink: CADisplayLink?
  private var isRestartCameraPending = false
  private var terminalWorkItem: DispatchWorkItem?
  private var pendingTerminalFrameAnimated: Bool?
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

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window == nil else {
      setNeedsLayout()
      return
    }
    // Finish while offscreen instead of leaving a half-restored camera with
    // no display link to complete it if this same viewport is attached again.
    applyPendingFocusIfNeeded()
    if let focusWorkItem {
      focusWorkItem.perform()
      focusWorkItem.cancel()
      self.focusWorkItem = nil
    }
    if let terminalWorkItem {
      terminalWorkItem.perform()
      terminalWorkItem.cancel()
      self.terminalWorkItem = nil
    }
    if pendingTerminalFrameAnimated != nil { applyTerminalFrame(animated: false) }
    if isRestartCameraPending, bounds.width > 0, bounds.height > 0, lastGridSize.width > 0 {
      let readyScale = min(
        bounds.height / lastGridSize.height,
        bounds.width / lastGridSize.width * 0.79
      )
      applyPendingRestartCameraIfNeeded(readyScale: readyScale)
    }
    settleCameraAnimation()
    canvas.settleFiniteAnimations()
    synchronizeGestureAvailability()
  }

  func update(
    board: BoardPresentation,
    phase: ReplicaGamePhase,
    isLoading: Bool,
    changedCoordinates: Set<CellCoordinate>,
    actionCoordinate: CellCoordinate?,
    fixedStartCoordinate: CellCoordinate?,
    isFixedStartEnabled: Bool,
    palette: BoardPalette,
    showsBorders: Bool,
    animationSpeed: Double,
    isReplayCovering: Bool,
    replayCoverSequence: Int
  ) {
    let gridSize = CGSize(
      width: CGFloat(board.columns) * BoardCanvasView.baseCellSize,
      height: CGFloat(board.rows) * BoardCanvasView.baseCellSize
    )
    let gridSizeChanged = gridSize != lastGridSize
    if gridSizeChanged {
      lastGridSize = gridSize
      canvas.frame = CGRect(origin: .zero, size: gridSize)
      contentSize = gridSize
      hasAppliedInitialZoom = false
    }
    let previousPhase = lastPhase
    if previousPhase != .ready, phase == .ready {
      focusWorkItem?.cancel()
      focusWorkItem = nil
      stopCameraAnimation()
      terminalWorkItem?.cancel()
      terminalWorkItem = nil
      pendingTerminalFrameAnimated = nil
      pendingFocusCoordinate = nil
      isHoldingRevealTransform = false
      isTerminalFramed = false
      let animateRestart = !gridSizeChanged
        && animationSpeed > 0
        && !UIAccessibility.isReduceMotionEnabled
      if animateRestart {
        // Keep the completed board's camera until the canvas has captured it,
        // then glide camera and slab to their ready framing on one timeline.
        isRestartCameraPending = true
      } else {
        isRestartCameraPending = false
        hasAppliedInitialZoom = false
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
      }
    }
    if previousPhase == .ready, phase == .playing {
      stopCameraAnimation()
      isRestartCameraPending = false
      pendingFocusCoordinate = actionCoordinate
      isHoldingRevealTransform = actionCoordinate != nil
      // Restored playing snapshots have no new touch to focus. Give them the
      // normal playing camera instead of holding the ready transform forever.
      if actionCoordinate == nil { hasAppliedInitialZoom = false }
      focusWorkItem?.cancel()
      focusWorkItem = nil
    }
    if !previousPhase.isFinished, phase.isFinished {
      focusWorkItem?.cancel()
      focusWorkItem = nil
      pendingFocusCoordinate = nil
      stopCameraAnimation(kind: .focus)
      isHoldingRevealTransform = false
      terminalWorkItem?.cancel()
      // Loss keeps the action capsule on-screen while mines radiate outward,
      // then begins fitting the whole board roughly ten 30-fps frames after
      // detonation. Win holds its close framing longer for the score reveal.
      let baseDelay = phase == .won ? 0.68 : 0.40
      let delay = animationSpeed > 0 && !UIAccessibility.isReduceMotionEnabled
        ? ReplicaMotion.duration(baseDelay, speedPercent: animationSpeed) : 0
      let work = DispatchWorkItem { [weak self] in
        self?.terminalWorkItem = nil
        self?.applyTerminalFrame(animated: delay > 0)
      }
      terminalWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    } else if previousPhase.isFinished, !phase.isFinished {
      terminalWorkItem?.cancel()
      terminalWorkItem = nil
      isTerminalFramed = false
      // The pending restart must begin at the completed board's current
      // scale. Resetting this flag here would snap to readyScale during the
      // next layout, before the camera has a chance to interpolate it.
      if !isRestartCameraPending { hasAppliedInitialZoom = false }
    }
    lastPhase = phase
    canvas.update(
      board: board,
      phase: phase,
      isLoading: isLoading,
      changedCoordinates: changedCoordinates,
      actionCoordinate: actionCoordinate,
      fixedStartCoordinate: fixedStartCoordinate,
      isFixedStartEnabled: isFixedStartEnabled,
      palette: palette,
      showsBorders: showsBorders,
      animationSpeed: animationSpeed,
      isReplayCovering: isReplayCovering,
      replayCoverSequence: replayCoverSequence
    )
    if animationSpeed <= 0 || UIAccessibility.isReduceMotionEnabled {
      settleCameraAnimation()
      if let focusWorkItem {
        focusWorkItem.perform()
        focusWorkItem.cancel()
        self.focusWorkItem = nil
      }
      if terminalWorkItem != nil {
        terminalWorkItem?.cancel()
        terminalWorkItem = nil
        applyTerminalFrame(animated: false)
      }
    }
    synchronizeGestureAvailability()
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
      bounds.width * 0.66 / lastGridSize.width,
      bounds.height * 0.545 / lastGridSize.height
    )
    // Large boards fit below the normal playing zoom floor. Preserve that
    // opening scale until the reveal and its following focus glide finish.
    minimumZoomScale = lastPhase == .ready
      ? (isRestartCameraPending || cameraAnimation?.kind == .restart
        ? min(readyScale, zoomScale)
        : readyScale)
      : (lastPhase.isFinished
        ? min(0.65, terminalScale)
        : (isHoldingRevealTransform || cameraAnimation?.kind == .focus
          ? min(0.65, zoomScale)
          : 0.65))
    maximumZoomScale = max(minimumZoomScale, 3.5)
    if !hasAppliedInitialZoom {
      zoomScale = lastPhase == .ready
        ? readyScale
        : max(minimumZoomScale, min(maximumZoomScale, 1.15))
      hasAppliedInitialZoom = true
    } else if zoomScale < minimumZoomScale {
      zoomScale = minimumZoomScale
    }
    if !isRestartCameraPending, cameraAnimation == nil {
      centerContent()
    }
    applyPendingRestartCameraIfNeeded(readyScale: readyScale)
    applyPendingFocusIfNeeded()
    if let animated = pendingTerminalFrameAnimated {
      applyTerminalFrame(animated: animated)
    }
    synchronizeGestureAvailability()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    if cameraAnimation == nil { centerContent() }
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { cancelAutomaticCameraForGesture() }

  func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
    cancelAutomaticCameraForGesture()
  }

  private func centerContent() {
    contentInset = calculatedContentInset(at: zoomScale)
  }

  private func calculatedContentInset(at scale: CGFloat) -> UIEdgeInsets {
    let scaledContentSize = CGSize(
      width: lastGridSize.width * scale,
      height: lastGridSize.height * scale
    )
    let horizontal = max(0, (bounds.width - scaledContentSize.width) / 2)
    let spareVertical = max(0, bounds.height - scaledContentSize.height)
    let targetCenterY: CGFloat? = if lastPhase == .ready || isHoldingRevealTransform {
      bounds.height * 0.54
    } else if isTerminalFramed {
      // Keep every completed board above the controls. This is also the
      // original game's settled framing: the board center sits near 42% of
      // the viewport, leaving a small clean gap before the restart pill.
      bounds.height * 0.416
    } else {
      nil
    }
    let vertical = targetCenterY.map { max(0, $0 - scaledContentSize.height / 2) }
      ?? spareVertical / 2
    // Give every edge the same deliberate scroll tail. The inset is stable for
    // the whole playing phase, so it cannot switch on halfway through the
    // first-focus animation and kick the canvas to a new offset.
    let hasPanTail = lastPhase == .playing && !isHoldingRevealTransform
    let horizontalPanTail = hasPanTail ? bounds.width * 0.34 : 0
    let verticalPanTail = hasPanTail ? bounds.height * 0.34 : 0
    let bottom = max(0, spareVertical - vertical) + verticalPanTail
    return UIEdgeInsets(
      top: vertical + verticalPanTail,
      left: horizontal + horizontalPanTail,
      bottom: bottom,
      right: horizontal + horizontalPanTail
    )
  }

  private func applyPendingRestartCameraIfNeeded(readyScale: CGFloat) {
    guard isRestartCameraPending, lastPhase == .ready else { return }
    isRestartCameraPending = false
    let speed = canvas.animationSpeedPercent
    let targetInset = calculatedContentInset(at: readyScale)
    let targetOffset = CGPoint(x: -targetInset.left, y: -targetInset.top)
    guard speed > 0, !UIAccessibility.isReduceMotionEnabled else {
      applyCameraFrame(zoom: readyScale, offset: targetOffset, inset: targetInset)
      minimumZoomScale = readyScale
      return
    }
    startCameraAnimation(
      kind: .restart,
      targetZoom: readyScale,
      targetOffset: targetOffset,
      targetInset: targetInset,
      duration: ReplicaMotion.duration(
        ReplicaMotion.restartTransition,
        speedPercent: speed
      )
    )
  }

  private func applyPendingFocusIfNeeded() {
    guard lastPhase == .playing else { return }
    guard let coordinate = pendingFocusCoordinate, bounds.width > 0, bounds.height > 0 else { return }
    pendingFocusCoordinate = nil
    // Begin at the fitted scale, then glide toward roughly eight visible
    // columns while the opening tiles finish contracting.
    let targetZoom = max(minimumZoomScale, min(maximumZoomScale, 1.29))
    let center = CGPoint(
      x: (CGFloat(coordinate.column) + 0.5) * BoardCanvasView.baseCellSize,
      y: (CGFloat(coordinate.row) + 0.5) * BoardCanvasView.baseCellSize
    )
    let focusDelay = UIAccessibility.isReduceMotionEnabled || canvas.animationSpeedPercent == 0
      ? 0
      : ReplicaMotion.duration(
        ReplicaMotion.firstFocusDelay,
        speedPercent: canvas.animationSpeedPercent
      )
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.focusWorkItem = nil
      guard self.lastPhase == .playing else { return }
      self.isHoldingRevealTransform = false
      let targetOffset = CGPoint(
        x: center.x * targetZoom - self.bounds.width / 2,
        y: center.y * targetZoom - self.bounds.height / 2
      )
      let targetInset = self.calculatedContentInset(at: targetZoom)
      let targetContentSize = CGSize(
        width: self.lastGridSize.width * targetZoom,
        height: self.lastGridSize.height * targetZoom
      )
      let boundedTargetOffset = self.boundedOffset(
        targetOffset,
        contentSize: targetContentSize,
        inset: targetInset
      )
      let animated = !UIAccessibility.isReduceMotionEnabled && self.canvas.animationSpeedPercent > 0
      guard animated else {
        self.applyCameraFrame(
          zoom: targetZoom,
          offset: boundedTargetOffset,
          inset: targetInset
        )
        return
      }
      self.startCameraAnimation(
        kind: .focus,
        targetZoom: targetZoom,
        targetOffset: boundedTargetOffset,
        targetInset: targetInset,
        duration: ReplicaMotion.duration(
          ReplicaMotion.firstFocusDuration,
          speedPercent: self.canvas.animationSpeedPercent
        )
      )
    }
    focusWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: work)
  }

  private func cancelAutomaticCameraForGesture() {
    // Restart owns the ready framing until its slab has settled, just as the
    // canvas suppresses reveal/flag gestures during that transition.
    guard !isRestartCameraPending, cameraAnimation?.kind != .restart else { return }
    focusWorkItem?.cancel()
    focusWorkItem = nil
    terminalWorkItem?.cancel()
    terminalWorkItem = nil
    pendingTerminalFrameAnimated = nil
    let wasAnimating = cameraAnimation != nil
    stopCameraAnimation()
    pendingFocusCoordinate = nil
    if isHoldingRevealTransform {
      isHoldingRevealTransform = false
      centerContent()
    } else if wasAnimating {
      centerContent()
    }
  }

  private func applyTerminalFrame(animated: Bool) {
    guard lastPhase.isFinished else { return }
    guard bounds.width > 0, bounds.height > 0, lastGridSize.width > 0 else {
      pendingTerminalFrameAnimated = animated
      return
    }
    pendingTerminalFrameAnimated = nil
    isTerminalFramed = true
    let scale = min(
      1.15,
      bounds.width * 0.66 / lastGridSize.width,
      bounds.height * 0.545 / lastGridSize.height
    )
    minimumZoomScale = min(0.65, scale)
    let targetInset = calculatedContentInset(at: scale)
    let duration = lastPhase == .lost ? 0.59 : 0.36
    startCameraAnimation(
      kind: .terminal,
      targetZoom: scale,
      targetOffset: CGPoint(x: -targetInset.left, y: -targetInset.top),
      targetInset: targetInset,
      duration: animated
        ? ReplicaMotion.duration(duration, speedPercent: canvas.animationSpeedPercent) : 0
    )
  }

  private func startCameraAnimation(
    kind: CameraAnimationKind,
    targetZoom: CGFloat,
    targetOffset: CGPoint,
    targetInset: UIEdgeInsets,
    duration: CFTimeInterval
  ) {
    stopCameraAnimation()
    guard duration > 0, window != nil else {
      applyCameraFrame(zoom: targetZoom, offset: targetOffset, inset: targetInset)
      finishCameraAnimation(kind: kind, targetZoom: targetZoom)
      return
    }
    cameraAnimation = CameraAnimationState(
      kind: kind,
      startedAt: CACurrentMediaTime(),
      duration: duration,
      startZoom: zoomScale,
      targetZoom: targetZoom,
      startOffset: contentOffset,
      targetOffset: targetOffset,
      startInset: contentInset,
      targetInset: targetInset
    )
    synchronizeGestureAvailability()
    let displayLink = CADisplayLink(target: self, selector: #selector(stepCameraAnimation(_:)))
    displayLink.preferredFrameRateRange = CAFrameRateRange(
      minimum: 60,
      maximum: 120,
      preferred: 120
    )
    cameraDisplayLink = displayLink
    displayLink.add(to: .main, forMode: .common)
  }

  @objc private func stepCameraAnimation(_ displayLink: CADisplayLink) {
    guard let animation = cameraAnimation else {
      stopCameraAnimation()
      return
    }
    let linearProgress = CGFloat(
      min(1, max(0, (displayLink.targetTimestamp - animation.startedAt) / animation.duration))
    )
    let easedProgress = cameraProgress(linearProgress, kind: animation.kind)
    func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
      start + (end - start) * easedProgress
    }
    let zoom = interpolate(animation.startZoom, animation.targetZoom)
    let offset = CGPoint(
      x: interpolate(animation.startOffset.x, animation.targetOffset.x),
      y: interpolate(animation.startOffset.y, animation.targetOffset.y)
    )
    let inset = UIEdgeInsets(
      top: interpolate(animation.startInset.top, animation.targetInset.top),
      left: interpolate(animation.startInset.left, animation.targetInset.left),
      bottom: interpolate(animation.startInset.bottom, animation.targetInset.bottom),
      right: interpolate(animation.startInset.right, animation.targetInset.right)
    )
    applyCameraFrame(zoom: zoom, offset: offset, inset: inset)
    guard linearProgress >= 1 else { return }
    stopCameraAnimation()
    finishCameraAnimation(kind: animation.kind, targetZoom: animation.targetZoom)
  }

  private func applyCameraFrame(zoom: CGFloat, offset: CGPoint, inset: UIEdgeInsets) {
    setZoomScale(zoom, animated: false)
    contentInset = inset
    contentOffset = offset
  }

  private func finishCameraAnimation(kind: CameraAnimationKind, targetZoom: CGFloat) {
    if kind == .restart, lastPhase == .ready {
      minimumZoomScale = targetZoom
      maximumZoomScale = max(targetZoom, 3.5)
      hasAppliedInitialZoom = true
    } else if kind == .terminal, lastPhase.isFinished {
      hasAppliedInitialZoom = true
    }
    synchronizeGestureAvailability()
    setNeedsLayout()
  }

  private func stopCameraAnimation(kind: CameraAnimationKind? = nil) {
    if let kind, cameraAnimation?.kind != kind { return }
    cameraDisplayLink?.invalidate()
    cameraDisplayLink = nil
    cameraAnimation = nil
    synchronizeGestureAvailability()
  }

  private func settleCameraAnimation() {
    guard let animation = cameraAnimation else { return }
    stopCameraAnimation()
    applyCameraFrame(
      zoom: animation.targetZoom,
      offset: animation.targetOffset,
      inset: animation.targetInset
    )
    finishCameraAnimation(kind: animation.kind, targetZoom: animation.targetZoom)
  }

  private func synchronizeGestureAvailability() {
    let allowsGestures = !isRestartCameraPending && cameraAnimation?.kind != .restart
    if isScrollEnabled != allowsGestures { isScrollEnabled = allowsGestures }
    if panGestureRecognizer.isEnabled != allowsGestures {
      panGestureRecognizer.isEnabled = allowsGestures
    }
    if let pinch = pinchGestureRecognizer, pinch.isEnabled != allowsGestures {
      pinch.isEnabled = allowsGestures
    }
  }

  private func cameraProgress(_ progress: CGFloat, kind: CameraAnimationKind) -> CGFloat {
    guard kind == .terminal, progress > 0, progress < 1 else {
      // Focus and restart retain their zero-velocity, zero-acceleration ends
      // for a smooth handoff to direct manipulation.
      return progress * progress * progress * (progress * (progress * 6 - 15) + 10)
    }
    // Preserve the former UIView curveEaseInOut timing while tracking each
    // terminal frame, so motion-off and direct gestures can finish/cancel it.
    var lower: CGFloat = 0
    var upper: CGFloat = 1
    for _ in 0..<12 {
      let t = (lower + upper) / 2
      let inverse = 1 - t
      let x = 3 * 0.42 * inverse * inverse * t + 3 * 0.58 * inverse * t * t + t * t * t
      if x < progress { lower = t } else { upper = t }
    }
    let t = (lower + upper) / 2
    return t * t * (3 - 2 * t)
  }

  private func boundedOffset(
    _ offset: CGPoint,
    contentSize: CGSize? = nil,
    inset: UIEdgeInsets? = nil
  ) -> CGPoint {
    let effectiveContentSize = contentSize ?? self.contentSize
    let effectiveInset = inset ?? contentInset
    let minX = -effectiveInset.left
    let minY = -effectiveInset.top
    let maxX = max(minX, effectiveContentSize.width - bounds.width + effectiveInset.right)
    let maxY = max(minY, effectiveContentSize.height - bounds.height + effectiveInset.bottom)
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
  private var initialRevealFixedStartCoordinate: CellCoordinate?
  private var winGlyphFadeStartedAt: CFTimeInterval?
  private var winGlyphOpacity: CGFloat = 1
  private var restartSnapshot: UIImage?
  private var restartStartedAt: CFTimeInterval?
  private var restartDuration: CFTimeInterval = 0
  private var isReplayCovering = false
  private var replayCoverSequence = 0
  private var replayCoverStartedAt: CFTimeInterval?
  private var replayCoverDuration: CFTimeInterval = 0
  private var loadingPulseStartedAt: CFTimeInterval?
  private var loadingPulseOrigin: CGPoint?
  private var fixedStartCoordinate: CellCoordinate?
  private var isFixedStartEnabled = false
  private var cachedPlayingBoardImage: UIImage?
  private var previousAnimatingRevealIndices: Set<Int> = []
  private var wasInvalidatingFullCanvas = false
  private var previousLoadingPulseRect: CGRect?
  private var previousInitialRevealOverlayRect: CGRect?
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

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      // CADisplayLink retains its target. Invalidate when navigation removes
      // the canvas, including while a slow opening is still being prepared.
      displayLink?.invalidate()
      displayLink = nil
    } else {
      maintainDisplayLink()
      setNeedsDisplay()
    }
  }

  fileprivate func settleFiniteAnimations() {
    revealStartedAt.removeAll(keepingCapacity: true)
    revealDurations.removeAll(keepingCapacity: true)
    initialRevealStartedAt = nil
    initialRevealOrigin = nil
    initialRevealDuration = 0
    initialRevealFixedStartCoordinate = nil
    restartSnapshot = nil
    restartStartedAt = nil
    restartDuration = 0
    palette = targetPalette
    paletteTransitionFrom = nil
    paletteTransitionStartedAt = nil
    winGlyphFadeStartedAt = nil
    winGlyphOpacity = phase == .won ? 0 : 1
    if isReplayCovering, replayCoverDuration > 0 {
      replayCoverStartedAt = CACurrentMediaTime() - replayCoverDuration
    }
    cachedPlayingBoardImage = nil
    previousAnimatingRevealIndices.removeAll(keepingCapacity: true)
    previousInitialRevealOverlayRect = nil
    previousLoadingPulseRect = nil
    wasInvalidatingFullCanvas = false
    displayLink?.invalidate()
    displayLink = nil
    // A preparation pulse may still be needed on return, but finite reveal,
    // palette and restart transitions must agree with the settled camera.
    setNeedsDisplay()
  }

  func update(
    board: BoardPresentation,
    phase: ReplicaGamePhase,
    isLoading: Bool,
    changedCoordinates: Set<CellCoordinate>,
    actionCoordinate: CellCoordinate?,
    fixedStartCoordinate: CellCoordinate?,
    isFixedStartEnabled: Bool,
    palette: BoardPalette,
    showsBorders: Bool,
    animationSpeed: Double,
    isReplayCovering: Bool,
    replayCoverSequence: Int
  ) {
    let oldBoard = self.board
    let oldPhase = self.phase
    let wasLoading = self.isLoading
    let oldFixedStartCoordinate = self.fixedStartCoordinate
    let wasFixedStartEnabled = self.isFixedStartEnabled
    let appearanceChanged = oldBoard != board || self.showsBorders != showsBorders
      || oldFixedStartCoordinate != fixedStartCoordinate
      || wasFixedStartEnabled != isFixedStartEnabled
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
    self.fixedStartCoordinate = fixedStartCoordinate
    self.isFixedStartEnabled = isFixedStartEnabled
    self.showsBorders = showsBorders
    self.animationSpeed = animationSpeed
    let allowsMotion = animationSpeed > 0 && !UIAccessibility.isReduceMotionEnabled
    let now = CACurrentMediaTime()
    if appearanceChanged { cachedPlayingBoardImage = nil }
    if phase == .won, oldPhase != .won {
      winGlyphFadeStartedAt = allowsMotion ? now : nil
      winGlyphOpacity = allowsMotion ? 1 : 0
    } else if phase != .won {
      winGlyphFadeStartedAt = nil
      winGlyphOpacity = 1
    }
    if allowsMotion, isLoading, phase == .ready, let actionCoordinate,
      !wasLoading || loadingPulseOrigin == nil
    {
      loadingPulseStartedAt = now
      loadingPulseOrigin = CGPoint(
        x: (CGFloat(actionCoordinate.column) + 0.5) * Self.baseCellSize,
        y: (CGFloat(actionCoordinate.row) + 0.5) * Self.baseCellSize
      )
    } else if !allowsMotion || !isLoading || phase != .ready {
      loadingPulseStartedAt = nil
      loadingPulseOrigin = nil
    }
    if allowsMotion, isReplayCovering,
      (!self.isReplayCovering || self.replayCoverSequence != replayCoverSequence)
    {
      replayCoverStartedAt = now
      replayCoverDuration = ReplicaMotion.replayCoverDuration * Self.durationScale(for: animationSpeed)
    } else if !allowsMotion || !isReplayCovering {
      replayCoverStartedAt = nil
      replayCoverDuration = 0
    }
    self.isReplayCovering = isReplayCovering
    self.replayCoverSequence = replayCoverSequence
    updatePalette(to: palette, at: now)
    let distanceScale = Self.durationScale(for: animationSpeed)
    if let pendingRestartSnapshot {
      restartSnapshot = pendingRestartSnapshot
      restartStartedAt = now
      restartDuration = ReplicaMotion.restartTransition * distanceScale
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
      initialRevealDuration = ReplicaMotion.firstRevealWave * distanceScale
      initialRevealOrigin = CGPoint(
        x: (CGFloat(actionCoordinate.column) + 0.5) * Self.baseCellSize,
        y: (CGFloat(actionCoordinate.row) + 0.5) * Self.baseCellSize
      )
      initialRevealFixedStartCoordinate = oldFixedStartCoordinate
      previousInitialRevealOverlayRect = initialRevealOverlayBounds
    } else if phase == .ready {
      initialRevealStartedAt = nil
      initialRevealOrigin = nil
      initialRevealDuration = 0
      initialRevealFixedStartCoordinate = nil
    }
    if !allowsMotion {
      // Animation Off and Reduce Motion finish the current visual operation
      // immediately, even when the preference changes halfway through it.
      revealStartedAt.removeAll(keepingCapacity: true)
      revealDurations.removeAll(keepingCapacity: true)
      initialRevealStartedAt = nil
      initialRevealOrigin = nil
      initialRevealDuration = 0
      initialRevealFixedStartCoordinate = nil
      restartSnapshot = nil
      restartStartedAt = nil
      restartDuration = 0
      self.palette = targetPalette
      paletteTransitionFrom = nil
      paletteTransitionStartedAt = nil
      cachedPlayingBoardImage = nil
      winGlyphFadeStartedAt = nil
      winGlyphOpacity = phase == .won ? 0 : 1
    }
    let openingMaximumDistance: Double = if startsInitialReveal, let actionCoordinate {
      changedCoordinates.map { coordinate in
        hypot(
          Double(coordinate.column - actionCoordinate.column),
          Double(coordinate.row - actionCoordinate.row)
        )
      }.max() ?? 0
    } else {
      0
    }
    let openingStagger = min(0.24, openingMaximumDistance * 0.018)
    for coordinate in changedCoordinates where allowsMotion {
      let index = coordinate.row * board.columns + coordinate.column
      guard board.cells.indices.contains(index) else { continue }
      if oldBoard.cells.indices.contains(index), oldBoard.cells[index] != board.cells[index] {
        let delay: Double
        let participatesInLossWave: Bool = switch board.cells[index] {
        case .mine, .flaggedMine: true
        case .covered, .revealed, .flagged, .wrongFlag: false
        }
        if startsInitialReveal, let actionCoordinate {
          // Both native Android captures and recent gameplay show a mosaic
          // only inside the opening region: seams appear, then rounded tiles
          // shrink to dots. A radial stagger carries that change from touch.
          let distance = hypot(
            Double(coordinate.column - actionCoordinate.column),
            Double(coordinate.row - actionCoordinate.row)
          )
          delay = openingMaximumDistance > 0
            ? distance / openingMaximumDistance * openingStagger : 0
        } else if phase == .lost, participatesInLossWave, let actionCoordinate {
          let dx = Double(coordinate.column - actionCoordinate.column)
          let dy = Double(coordinate.row - actionCoordinate.row)
          let radial = hypot(dx, dy) * 0.023
          let jitter = Double((coordinate.row * 17 + coordinate.column * 29) % 23) / 1_000
          // A radial wave avoids the mechanical diagonal bands produced by a
          // Chebyshev schedule. The deterministic micro-jitter keeps nearby
          // mines from appearing on exactly the same display frame.
          // Do not cap the far half of a tall board too early. Nearby mines
          // begin at about 100 ms; distant mines continue arriving through
          // the terminal zoom and settle close to the one-second mark.
          delay = min(0.78, radial) + (dx == 0 && dy == 0 ? 0 : 0.07 + jitter)
        } else {
          let distance = actionCoordinate.map {
            max(abs(coordinate.row - $0.row), abs(coordinate.column - $0.column))
          } ?? 0
          delay = min(0.30, Double(distance) * 0.012)
        }
        revealStartedAt[index] = now + delay * distanceScale
        // Flags and mine glyphs swap in within roughly one or two 30-fps
        // frames. The loss cascade's motion comes from its radial schedule,
        // not from slowly growing each individual gear.
        switch board.cells[index] {
        case .flagged, .flaggedMine, .wrongFlag:
          revealDurations[index] = 0.07 * distanceScale
        case .mine:
          revealDurations[index] = 0.08 * distanceScale
        case .covered, .revealed:
          revealDurations[index] = (startsInitialReveal
            ? ReplicaMotion.firstRevealWave - openingStagger : 0.24) * distanceScale
        }
      }
    }
    if phase == .ready, let fixedStartCoordinate {
      let readiness = isFixedStartEnabled ? "ready" : "preparing"
      accessibilityLabel =
        "Minesweeper board, \(board.columns) columns by \(board.rows) rows, "
        + "Extreme start row \(fixedStartCoordinate.row + 1), column "
        + "\(fixedStartCoordinate.column + 1), \(readiness)"
      accessibilityActivationPoint = convert(
        CGPoint(
          x: (CGFloat(fixedStartCoordinate.column) + 0.5) * Self.baseCellSize,
          y: (CGFloat(fixedStartCoordinate.row) + 0.5) * Self.baseCellSize
        ),
        to: nil
      )
    } else {
      accessibilityLabel = "Minesweeper board, \(board.columns) columns by \(board.rows) rows"
      accessibilityActivationPoint = convert(
        CGPoint(x: bounds.midX, y: bounds.midY),
        to: nil
      )
    }
    accessibilityValue = switch phase {
    case .ready: isLoading ? "Preparing" : "Ready"
    case .playing: "Playing"
    case .won: "Won"
    case .lost: "Lost"
    }
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
        drawLoadingPulse(context: context)
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
    if shouldUseCachedPlayingBoard, let image = cachedPlayingBoard() {
      image.draw(in: bounds)
    } else {
      drawPlayingBoardContent(in: rect, context: context)
    }
    drawInitialRevealOverlay(context: context)
    drawReplayCoverOverlay(context: context)
    context.restoreGState()
  }

  /// Draws only the stable playing-state board. Large circular wipes reuse a
  /// cached copy of this result so a 576/1,296-cell canvas is not rebuilt at
  /// every 120 Hz display tick.
  private func drawPlayingBoardContent(in rect: CGRect, context: CGContext) {
    context.setFillColor(palette.surface.cgColor)
    context.fill(bounds)

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
    drawConcaveRegionCorners(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow,
      radius: Self.baseCellSize * 0.09,
      fillColor: palette.covered,
      matches: { [self] column, row in
        visuallyCovered(column: column, row: row)
      },
      permitsMissingQuadrant: { [self] column, row in
        visuallyRevealed(column: column, row: row)
      }
    )
    drawCoveredCellBorders(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow,
      context: context
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
  }

  private var shouldUseCachedPlayingBoard: Bool {
    revealStartedAt.isEmpty
      && paletteTransitionStartedAt == nil
      && winGlyphFadeStartedAt == nil
      && (initialRevealStartedAt != nil || isReplayCovering)
  }

  private func cachedPlayingBoard() -> UIImage? {
    if let cachedPlayingBoardImage { return cachedPlayingBoardImage }
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = max(1, contentScaleFactor)
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
    let image = renderer.image { output in
      let snapshotContext = output.cgContext
      snapshotContext.saveGState()
      UIBezierPath(
        roundedRect: bounds,
        cornerRadius: Self.baseCellSize * 0.09
      ).addClip()
      drawPlayingBoardContent(in: bounds, context: snapshotContext)
      snapshotContext.restoreGState()
    }
    cachedPlayingBoardImage = image
    return image
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

  }

  private func drawCoveredCellBorders(
    firstColumn: Int,
    lastColumn: Int,
    firstRow: Int,
    lastRow: Int,
    context: CGContext
  ) {
    guard showsBorders, winGlyphOpacity > 0 else { return }
    // Draw after the connected covered surface; painting these in drawCell
    // lets the later union fill erase every border again.
    context.saveGState()
    context.setAlpha(winGlyphOpacity)
    context.setStrokeColor(palette.separator.cgColor)
    context.setLineWidth(0.7)
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn {
        switch board[column, row] {
        case .covered, .mine(triggered: false):
          let rect = cellRect(column: column, row: row).insetBy(dx: 0.55, dy: 0.55)
          let path = UIBezierPath(
            roundedRect: rect,
            cornerRadius: Self.baseCellSize * 0.09 - 0.55
          )
          context.addPath(path.cgPath)
        case .revealed, .flagged, .flaggedMine, .mine(triggered: true), .wrongFlag:
          continue
        }
      }
    }
    context.strokePath()
    context.restoreGState()
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
    // Native reference frames use a 71 px cell pitch and a 59 px flag surface.
    // Preserve that 83% ratio here. The source's rasterized flag measures
    // about 30% x 32% of the cell, so its 24-unit Material path needs a
    // slightly wider-than-tall viewport. The previous uniform 55% viewport
    // made the silhouette especially tall and weakened the surrounding moat.
    let tileInset = Self.baseCellSize * 0.085
    let flagGlyphScaleX: CGFloat = 0.50
    let flagGlyphScaleY: CGFloat = 0.455

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
    drawConcaveRegionCorners(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow,
      radius: radius,
      fillColor: palette.surface,
      matches: { [self] column, row in isFlagLike(column: column, row: row) }
    )
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
    drawConcaveRegionCorners(
      firstColumn: firstColumn,
      lastColumn: lastColumn,
      firstRow: firstRow,
      lastRow: lastRow,
      radius: radius + tileInset,
      boundaryInset: tileInset,
      fillColor: palette.flagged,
      matches: { [self] column, row in isFlagLike(column: column, row: row) }
    )
    // Glyphs and the short placement morph sit above the completed topology.
    for row in firstRow...lastRow {
      for column in firstColumn...lastColumn where isFlagLike(column: column, row: row) {
        let rect = cellRect(column: column, row: row)
        let index = row * board.columns + column
        let progress = revealProgress(for: index)
        guard progress > 0 else {
          if case .flaggedMine = board[column, row] {
            drawFlag(
              in: rect,
              color: palette.flagGlyph,
              scaleX: flagGlyphScaleX,
              scaleY: flagGlyphScaleY
            )
            continue
          }
          if case .wrongFlag = board[column, row] {
            drawFlag(
              in: rect,
              color: palette.flagGlyph,
              scaleX: flagGlyphScaleX,
              scaleY: flagGlyphScaleY
            )
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
            scale: 1
          )
        } else {
          drawFlag(
            in: rect,
            color: palette.flagGlyph,
            scaleX: flagGlyphScaleX,
            scaleY: flagGlyphScaleY
          )
        }
        // A merged flag cluster is one continuous visual surface. Restroking
        // each flagged cell here draws square per-cell edges after the rounded
        // topology pass, leaving a faint rectangular outline outside concave
        // curves when cell borders are enabled.
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
    drawFixedStartMarker()
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
      .foregroundColor: palette.coveredText.withAlphaComponent(alpha),
    ]
    let prompt: String
    let effectiveFixedStart = fixedStartCoordinate ?? initialRevealFixedStartCoordinate
    if effectiveFixedStart != nil {
      prompt = isFixedStartEnabled
        ? "Begin at the marked cell."
        : "Preparing an Extreme board…"
    } else {
      prompt = "Tap to begin."
    }
    let string = NSString(string: prompt)
    let size = string.size(withAttributes: attributes)
    let promptCenterY: CGFloat
    if let fixedStartCoordinate = effectiveFixedStart {
      // The prescribed opening is near the geometric center. Lift the prompt
      // by one cell so the copy and target remain independently readable.
      promptCenterY = (CGFloat(fixedStartCoordinate.row) + 0.5) * Self.baseCellSize
        - Self.baseCellSize * 1.18
    } else {
      promptCenterY = rect.midY
    }
    string.draw(
      at: CGPoint(x: rect.midX - size.width / 2, y: promptCenterY - size.height / 2),
      withAttributes: attributes
    )
  }

  private func drawFixedStartMarker() {
    guard let coordinate = fixedStartCoordinate,
      coordinate.column >= 0,
      coordinate.column < board.columns,
      coordinate.row >= 0,
      coordinate.row < board.rows,
      let context = UIGraphicsGetCurrentContext()
    else { return }

    let rect = cellRect(column: coordinate.column, row: coordinate.row)
    let color = palette.fixedStartMarker
    let enabledAlpha: CGFloat = isFixedStartEnabled ? 0.96 : 0.44
    let plate = rect.insetBy(dx: Self.baseCellSize * 0.105, dy: Self.baseCellSize * 0.105)

    context.saveGState()
    context.setFillColor(color.withAlphaComponent(0.12 * enabledAlpha).cgColor)
    context.setStrokeColor(color.withAlphaComponent(enabledAlpha).cgColor)
    context.setLineWidth(Self.baseCellSize * 0.052)
    let outline = UIBezierPath(
      roundedRect: plate,
      cornerRadius: Self.baseCellSize * 0.16
    )
    outline.fill()
    outline.stroke()

    // A compact bullseye reads at the board's fit-to-screen scale and avoids
    // suggesting either Dig or Flag when the user's preferred action differs.
    let ringRadius = Self.baseCellSize * 0.135
    context.setLineWidth(Self.baseCellSize * 0.040)
    context.strokeEllipse(in: CGRect(
      x: rect.midX - ringRadius,
      y: rect.midY - ringRadius,
      width: ringRadius * 2,
      height: ringRadius * 2
    ))
    let dotRadius = Self.baseCellSize * 0.042
    context.setFillColor(color.withAlphaComponent(enabledAlpha).cgColor)
    context.fillEllipse(in: CGRect(
      x: rect.midX - dotRadius,
      y: rect.midY - dotRadius,
      width: dotRadius * 2,
      height: dotRadius * 2
    ))
    context.restoreGState()
  }

  /// Immediate first-touch feedback while a verified board is being prepared.
  /// Extreme generation stays fully no-guess, but the tap no longer presents
  /// as a frozen frame during its bounded solver pass.
  private func drawLoadingPulse(context: CGContext) {
    guard isLoading,
      let startedAt = loadingPulseStartedAt,
      let origin = loadingPulseOrigin,
      animationSpeed > 0,
      !UIAccessibility.isReduceMotionEnabled
    else { return }

    let cycle = max(0.22, 0.46 * Self.durationScale(for: animationSpeed))
    let elapsed = max(0, (renderTimestamp ?? CACurrentMediaTime()) - startedAt)
    let phase = CGFloat((elapsed / cycle).truncatingRemainder(dividingBy: 1))
    let eased = Self.smoothStep(phase)
    let radius = Self.baseCellSize * (0.12 + 0.34 * eased)
    let color = palette.background.withAlphaComponent(0.70 * (1 - eased))

    context.saveGState()
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(Self.baseCellSize * 0.055 * (1 - 0.45 * eased))
    context.strokeEllipse(in: CGRect(
      x: origin.x - radius,
      y: origin.y - radius,
      width: radius * 2,
      height: radius * 2
    ))
    context.setFillColor(palette.background.withAlphaComponent(0.62).cgColor)
    let dotRadius = Self.baseCellSize * 0.075
    context.fillEllipse(in: CGRect(
      x: origin.x - dotRadius,
      y: origin.y - dotRadius,
      width: dotRadius * 2,
      height: dotRadius * 2
    ))
    context.restoreGState()
  }

  /// Keeps the ready prompt and touch acknowledgement above the per-cell
  /// opening mosaic. The cells themselves clear in drawClearingOverlay, so
  /// the surrounding covered slab remains connected throughout the reveal.
  private func drawInitialRevealOverlay(context: CGContext) {
    guard let startedAt = initialRevealStartedAt,
      let origin = initialRevealOrigin,
      initialRevealDuration > 0
    else { return }

    let elapsed = (renderTimestamp ?? CACurrentMediaTime()) - startedAt
    let progress = CGFloat(min(1, max(0, elapsed / initialRevealDuration)))
    guard progress < 1 else { return }

    // Fade the prompt while the first seams open beneath it.
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

  /// Closes a completed replay with the centered covered-color circle visible
  /// in Clean One's native timelapse. The controller swaps in the true covered
  /// board while this circle fills the clipped canvas, allowing the overlay to
  /// disappear without exposing a single stale completed-board frame.
  private func drawReplayCoverOverlay(context: CGContext) {
    guard isReplayCovering,
      let startedAt = replayCoverStartedAt,
      replayCoverDuration > 0
    else { return }

    let elapsed = (renderTimestamp ?? CACurrentMediaTime()) - startedAt
    let progress = CGFloat(min(1, max(0, elapsed / replayCoverDuration)))
    // The native wipe hesitates for approximately one 30-fps frame, then its
    // leading edge accelerates before settling against the board corners.
    let delayedProgress = min(1, max(0, (progress - 0.035) / 0.965))
    let radiusProgress = Self.smoothStep(delayedProgress)
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let maximumRadius = hypot(bounds.width / 2, bounds.height / 2)
      + Self.baseCellSize * 0.08
    let radius = maximumRadius * radiusProgress
    guard radius > 0 else { return }

    context.saveGState()
    context.setFillColor(palette.covered.cgColor)
    context.fillEllipse(in: CGRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    ))
    context.restoreGState()
  }

  /// Crossfades the completed board into one aspect-preserving fresh slab.
  /// Keeping a single rectangular surface throughout prevents the separate
  /// circle and rectangle from overlapping as a visible ghost during restart.
  @discardableResult
  private func drawRestartTransition(context: CGContext) -> Bool {
    guard let startedAt = restartStartedAt,
      let snapshot = restartSnapshot,
      restartDuration > 0
    else { return false }

    let elapsed = (renderTimestamp ?? CACurrentMediaTime()) - startedAt
    let progress = CGFloat(min(1, max(0, elapsed / restartDuration)))
    guard progress < 1 else { return false }

    if progress < 0.58 {
      let fade = Self.smoothStep(progress / 0.58)
      let scale = 1 - 0.018 * fade
      context.saveGState()
      context.translateBy(x: bounds.midX, y: bounds.midY)
      context.scaleBy(x: scale, y: scale)
      context.translateBy(x: -bounds.midX, y: -bounds.midY)
      snapshot.draw(in: bounds, blendMode: .normal, alpha: 1 - fade)
      context.restoreGState()
    }

    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let slabProgress = Self.smoothStep(min(1, max(0, (progress - 0.14) / 0.86)))
    if slabProgress > 0 {
      let slabScale = 0.12 + 0.88 * slabProgress
      let slabAlpha = Self.smoothStep(min(1, slabProgress / 0.22))
      context.saveGState()
      context.setAlpha(slabAlpha)
      context.translateBy(x: center.x, y: center.y)
      context.scaleBy(x: slabScale, y: slabScale)
      context.translateBy(x: -center.x, y: -center.y)
      drawReadySlab(in: bounds)
      context.restoreGState()

      let promptProgress = Self.smoothStep(
        min(1, max(0, (slabProgress - 0.78) / 0.22))
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
    guard winGlyphOpacity > 0 else { return }
    context.saveGState()
    context.setAlpha(winGlyphOpacity)
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

  /// At a grid vertex occupied by three cells from one visual region, the
  /// adjacency bridges otherwise form a sharp 90-degree inward corner. Extend
  /// that region into the missing quadrant with a tangent-continuous quarter
  /// arc. The same contour repair is shared by covers and both flag layers.
  private func drawConcaveRegionCorners(
    firstColumn: Int,
    lastColumn: Int,
    firstRow: Int,
    lastRow: Int,
    radius: CGFloat,
    boundaryInset: CGFloat = 0,
    fillColor: UIColor,
    matches: (Int, Int) -> Bool,
    permitsMissingQuadrant: ((Int, Int) -> Bool)? = nil
  ) {
    fillColor.setFill()
    let firstVertexRow = max(1, firstRow)
    let lastVertexRow = min(board.rows - 1, lastRow + 1)
    let firstVertexColumn = max(1, firstColumn)
    let lastVertexColumn = min(board.columns - 1, lastColumn + 1)
    guard firstVertexRow <= lastVertexRow, firstVertexColumn <= lastVertexColumn else { return }

    for vertexRow in firstVertexRow...lastVertexRow {
      for vertexColumn in firstVertexColumn...lastVertexColumn {
        let quadrants = [
          (column: vertexColumn - 1, row: vertexRow - 1, sx: -1.0, sy: -1.0),
          (column: vertexColumn, row: vertexRow - 1, sx: 1.0, sy: -1.0),
          (column: vertexColumn - 1, row: vertexRow, sx: -1.0, sy: 1.0),
          (column: vertexColumn, row: vertexRow, sx: 1.0, sy: 1.0),
        ]
        let membership = quadrants.map { matches($0.column, $0.row) }
        guard membership.filter({ $0 }).count == 3,
          let missing = membership.firstIndex(of: false)
        else { continue }
        let quadrant = quadrants[missing]
        if let permitsMissingQuadrant,
          !permitsMissingQuadrant(quadrant.column, quadrant.row)
        {
          continue
        }

        let vertex = CGPoint(
          x: CGFloat(vertexColumn) * Self.baseCellSize,
          y: CGFloat(vertexRow) * Self.baseCellSize
        )
        // An inset region has its horizontal and vertical boundaries shifted
        // away from the missing quadrant. Move the curve's origin by the same
        // amount and increase its radius, producing the true parallel offset
        // of the outer contour. Painting squares around the grid vertex looks
        // connected but rasterizes as a visible staircase at this corner.
        let corner = CGPoint(
          x: vertex.x - CGFloat(quadrant.sx) * boundaryInset,
          y: vertex.y - CGFloat(quadrant.sy) * boundaryInset
        )
        let verticalTangent = CGPoint(
          x: corner.x,
          y: corner.y + CGFloat(quadrant.sy) * radius
        )
        let horizontalTangent = CGPoint(
          x: corner.x + CGFloat(quadrant.sx) * radius,
          y: corner.y
        )
        // The inset cells are composited before this repair curve. Cover the
        // one-device-pixel antialias fringe along their former square edges
        // on the region side of each tangent; otherwise that fringe remains
        // visible as a faint rectangular box behind the rounded corner.
        if boundaryInset > 0, let context = UIGraphicsGetCurrentContext() {
          let overlap = 1 / max(1, contentScaleFactor)
          context.saveGState()
          context.setShouldAntialias(false)
          UIRectFill(CGRect(
            x: min(corner.x, horizontalTangent.x),
            y: quadrant.sy > 0 ? corner.y - overlap : corner.y,
            width: abs(horizontalTangent.x - corner.x),
            height: overlap
          ))
          UIRectFill(CGRect(
            x: quadrant.sx > 0 ? corner.x - overlap : corner.x,
            y: min(corner.y, verticalTangent.y),
            width: overlap,
            height: abs(verticalTangent.y - corner.y)
          ))
          context.restoreGState()
        }
        let kappa: CGFloat = 0.552_284_75
        let firstControl = CGPoint(
          x: corner.x,
          y: corner.y + CGFloat(quadrant.sy) * radius * (1 - kappa)
        )
        let secondControl = CGPoint(
          x: corner.x + CGFloat(quadrant.sx) * radius * (1 - kappa),
          y: corner.y
        )
        let cutout = UIBezierPath()
        cutout.move(to: corner)
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
    guard winGlyphOpacity > 0 else { return }
    let color =
      palette.clues.indices.contains(number - 1) ? palette.clues[number - 1] : palette.foreground
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont(name: "Rubik-Regular", size: Self.baseCellSize * 0.58 * scale)
        ?? UIFont.systemFont(ofSize: Self.baseCellSize * 0.58 * scale, weight: .regular),
      .foregroundColor: color.withAlphaComponent(winGlyphOpacity),
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

  private func maintainDisplayLink(at now: CFTimeInterval = CACurrentMediaTime()) {
    // Preserve final-frame cleanup even when the first tick after a stall
    // arrives beyond an animation's end and clears its timestamp below.
    if paletteTransitionStartedAt != nil || winGlyphFadeStartedAt != nil
      || restartStartedAt != nil || (isReplayCovering && replayCoverStartedAt != nil)
    {
      wasInvalidatingFullCanvas = true
    }
    updatePaletteAnimation(at: now)
    if let startedAt = winGlyphFadeStartedAt {
      let scale = Self.durationScale(for: animationSpeed)
      let elapsed = now - startedAt - ReplicaMotion.winGlyphFadeDelay * scale
      let progress = CGFloat(min(1, max(0, elapsed / (ReplicaMotion.winGlyphFadeDuration * scale))))
      winGlyphOpacity = 1 - Self.smoothStep(progress)
      cachedPlayingBoardImage = nil
      if progress >= 1 { winGlyphFadeStartedAt = nil }
    }
    if let startedAt = initialRevealStartedAt,
      now - startedAt >= initialRevealDuration
    {
      initialRevealStartedAt = nil
      initialRevealOrigin = nil
      initialRevealDuration = 0
      initialRevealFixedStartCoordinate = nil
    }
    if let startedAt = restartStartedAt,
      now - startedAt >= restartDuration
    {
      restartSnapshot = nil
      restartStartedAt = nil
      restartDuration = 0
    }
    let finalFrameTail = max(displayLink?.duration ?? (1 / 60), 1 / 120) * 1.5
    var completedRevealIndices: Set<Int> = []
    revealStartedAt = revealStartedAt.filter { index, start in
      let duration = revealDurations[index]
        ?? 0.24 * Self.durationScale(for: animationSpeed)
      let isActive = now < start + duration + finalFrameTail
      if !isActive { completedRevealIndices.insert(index) }
      return isActive
    }
    // A delayed display tick can skip a cell's entire animation. Its final
    // state still needs drawing even if no earlier frame marked it dirty.
    previousAnimatingRevealIndices.formUnion(completedRevealIndices)
    let activeIndices = Set(revealStartedAt.keys)
    revealDurations = revealDurations.filter { activeIndices.contains($0.key) }
    let replayCoverIsAnimating = if isReplayCovering,
      let startedAt = replayCoverStartedAt
    {
      now - startedAt < replayCoverDuration
    } else {
      false
    }
    if revealStartedAt.isEmpty,
      paletteTransitionStartedAt == nil,
      winGlyphFadeStartedAt == nil,
      initialRevealStartedAt == nil,
      restartStartedAt == nil,
      loadingPulseStartedAt == nil,
      !replayCoverIsAnimating
    {
      displayLink?.invalidate()
      displayLink = nil
    } else if displayLink == nil, window != nil {
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
    ReplicaMotion.durationScale(speedPercent: speedPercent)
  }

  private static func smoothStep(_ value: CGFloat) -> CGFloat {
    let clamped = min(1, max(0, value))
    return clamped * clamped * (3 - 2 * clamped)
  }

  @objc private func animationTick() {
    let now = displayLink?.targetTimestamp ?? CACurrentMediaTime()
    maintainDisplayLink(at: now)
    invalidateAnimationFrame(at: now)
  }

  private func invalidateAnimationFrame(at now: CFTimeInterval) {
    let replayCoverIsAnimating = if isReplayCovering,
      let startedAt = replayCoverStartedAt
    {
      now - startedAt < replayCoverDuration
    } else {
      false
    }
    let invalidatesFullCanvas = paletteTransitionStartedAt != nil
      || winGlyphFadeStartedAt != nil
      || restartStartedAt != nil
      || replayCoverIsAnimating
    if invalidatesFullCanvas || wasInvalidatingFullCanvas {
      wasInvalidatingFullCanvas = invalidatesFullCanvas
      previousAnimatingRevealIndices.removeAll(keepingCapacity: true)
      previousLoadingPulseRect = nil
      previousInitialRevealOverlayRect = nil
      setNeedsDisplay()
      return
    }

    let frameLead = max(displayLink?.duration ?? (1 / 60), 1 / 120)
    var animating: Set<Int> = []
    animating.reserveCapacity(revealStartedAt.count)
    for (index, start) in revealStartedAt {
      let duration = revealDurations[index]
        ?? 0.24 * Self.durationScale(for: animationSpeed)
      if now >= start - frameLead, now <= start + duration {
        animating.insert(index)
      }
    }

    let cellsToInvalidate = animating.union(previousAnimatingRevealIndices)
    previousAnimatingRevealIndices = animating
    var dirtyRect: CGRect?
    for index in cellsToInvalidate where board.columns > 0 {
      let column = index % board.columns
      let row = index / board.columns
      let cell = CGRect(
        x: CGFloat(column) * Self.baseCellSize,
        y: CGFloat(row) * Self.baseCellSize,
        width: Self.baseCellSize,
        height: Self.baseCellSize
      )
      dirtyRect = dirtyRect.map { $0.union(cell) } ?? cell
    }

    // The opening now changes only its revealed tiles, prompt and small
    // touch ripple. Redrawing the whole 576/1,296-cell canvas here would undo
    // the existing per-cell invalidation on even a tiny Extreme opening.
    let currentInitialOverlayRect: CGRect? = if let startedAt = initialRevealStartedAt,
      initialRevealDuration > 0,
      now - startedAt < initialRevealDuration * 0.62
    {
      initialRevealOverlayBounds
    } else {
      nil
    }
    if let currentInitialOverlayRect {
      dirtyRect = dirtyRect.map { $0.union(currentInitialOverlayRect) }
        ?? currentInitialOverlayRect
    }
    if let previousInitialRevealOverlayRect {
      // Include the last visible overlay once more when it disappears, even
      // if a delayed display tick skips directly past the end of the reveal.
      dirtyRect = dirtyRect.map { $0.union(previousInitialRevealOverlayRect) }
        ?? previousInitialRevealOverlayRect
    }
    previousInitialRevealOverlayRect = currentInitialOverlayRect

    if isLoading, phase == .ready, let origin = loadingPulseOrigin {
      let extent = Self.baseCellSize * 0.55
      let pulseRect = CGRect(
        x: origin.x - extent,
        y: origin.y - extent,
        width: extent * 2,
        height: extent * 2
      )
      dirtyRect = dirtyRect.map { $0.union(pulseRect) } ?? pulseRect
      if let previousLoadingPulseRect {
        dirtyRect = dirtyRect?.union(previousLoadingPulseRect)
      }
      previousLoadingPulseRect = pulseRect
    } else if let previousLoadingPulseRect {
      dirtyRect = dirtyRect.map { $0.union(previousLoadingPulseRect) }
        ?? previousLoadingPulseRect
      self.previousLoadingPulseRect = nil
    }

    if var dirtyRect {
      // Connected corners inspect immediate neighbors, so include one-cell
      // breathing room without redrawing a full Extreme/Huge canvas.
      dirtyRect = dirtyRect.insetBy(dx: -Self.baseCellSize, dy: -Self.baseCellSize)
        .intersection(bounds)
      if !dirtyRect.isNull, !dirtyRect.isEmpty { setNeedsDisplay(dirtyRect) }
    }
  }

  private var initialRevealOverlayBounds: CGRect {
    let promptCenterY = initialRevealFixedStartCoordinate.map {
      (CGFloat($0.row) + 0.5) * Self.baseCellSize - Self.baseCellSize * 1.18
    } ?? bounds.midY
    // Rubik is 4.5% of board width here; this envelope includes ascenders,
    // descenders and raster antialiasing throughout the prompt's fade.
    let promptHalfHeight = max(Self.baseCellSize * 0.5, bounds.width * 0.06)
    var overlay = CGRect(
      x: bounds.minX,
      y: promptCenterY - promptHalfHeight,
      width: bounds.width,
      height: promptHalfHeight * 2
    )
    if let origin = initialRevealOrigin {
      let extent = Self.baseCellSize * 0.32
      overlay = overlay.union(CGRect(
        x: origin.x - extent,
        y: origin.y - extent,
        width: extent * 2,
        height: extent * 2
      ))
    }
    return overlay.intersection(bounds)
  }

  private func updatePalette(to revised: BoardPalette, at now: CFTimeInterval) {
    guard hasReceivedPalette else {
      hasReceivedPalette = true
      palette = revised
      targetPalette = revised
      cachedPlayingBoardImage = nil
      return
    }
    guard !targetPalette.matches(revised) else { return }
    updatePaletteAnimation(at: now)
    targetPalette = revised
    cachedPlayingBoardImage = nil
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
    cachedPlayingBoardImage = nil
    if progress >= 1 {
      palette = targetPalette
      paletteTransitionFrom = nil
      paletteTransitionStartedAt = nil
    }
  }

  private func drawFlag(
    in rect: CGRect,
    color: UIColor,
    scaleX: CGFloat = 1,
    scaleY: CGFloat = 1
  ) {
    guard winGlyphOpacity > 0, let context = UIGraphicsGetCurrentContext() else { return }
    context.saveGState()
    context.setAlpha(winGlyphOpacity)
    context.translateBy(x: rect.midX, y: rect.midY)
    context.scaleBy(x: scaleX, y: scaleY)
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
    // Keep the modern 48–49% outer envelope, but use the reference's chunky
    // hub and short, mildly rounded teeth. Filling one composite path removes
    // the swollen detached-pill look caused by eight independent draw calls.
    let outerRadius = rect.width * 0.244
    let coreRadius = rect.width * 0.200
    let toothStart = rect.width * 0.165
    let toothThickness = rect.width * 0.093
    let toothCornerRadius = rect.width * 0.011
    let silhouette = UIBezierPath(
      ovalIn: CGRect(
        x: rect.midX - coreRadius,
        y: rect.midY - coreRadius,
        width: coreRadius * 2,
        height: coreRadius * 2
      )
    )
    for index in 0..<8 {
      let angle = CGFloat(index) * .pi / 4
      let tooth = CGRect(
        x: rect.midX + toothStart,
        y: rect.midY - toothThickness / 2,
        width: outerRadius - toothStart,
        height: toothThickness
      )
      let toothPath = UIBezierPath(roundedRect: tooth, cornerRadius: toothCornerRadius)
      var transform = CGAffineTransform(
        translationX: rect.midX,
        y: rect.midY
      )
      transform = transform.rotated(by: angle)
      transform = transform.translatedBy(x: -rect.midX, y: -rect.midY)
      toothPath.apply(transform)
      silhouette.append(toothPath)
    }
    color.setFill()
    silhouette.fill()

    // The substrate-colored square is the reference's visual knockout.
    let holeSize = rect.width * 0.099
    holeColor.setFill()
    UIRectFill(
      CGRect(
        x: rect.midX - holeSize / 2,
        y: rect.midY - holeSize / 2,
        width: holeSize,
        height: holeSize
      )
    )
    context.restoreGState()
  }

  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard restartStartedAt == nil,
      recognizer.state == .ended,
      let coordinate = coordinate(at: recognizer.location(in: self))
    else { return }
    if phase == .ready, let fixedStartCoordinate {
      guard coordinate.column == fixedStartCoordinate.column,
        coordinate.row == fixedStartCoordinate.row
      else { return }
    }
    onTap?(coordinate.column, coordinate.row)
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard restartStartedAt == nil,
      recognizer.state == .began,
      let coordinate = coordinate(at: recognizer.location(in: self))
    else { return }
    if phase == .ready, let fixedStartCoordinate {
      guard coordinate.column == fixedStartCoordinate.column,
        coordinate.row == fixedStartCoordinate.row
      else { return }
    }
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
