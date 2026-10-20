import AppKit

/// Freehand strokes drawn over one screen in notes mode. Points are relative to the
/// screen's bottom-left corner, which matches both the drawing panel's view
/// coordinates and a bitmap context the size of the screen.
struct ScreenAnnotation {
  static let lineWidth: CGFloat = 4
  static let strokeColor = CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)

  /// Smallest area kept around a mark, so a circled word still shows the lines around it.
  static let minimumCropSize = CGSize(width: 480, height: 270)
  /// Crops covering more of the screen than this keep the whole screen instead.
  static let fullScreenCoverage: CGFloat = 0.6

  let screen: NSScreen
  let strokes: [[CGPoint]]

  /// A stroke as a curve through the midpoints between its samples, so fast drags
  /// don't look jagged. A single sample becomes a dot.
  static func path(for stroke: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = stroke.first, let last = stroke.last else { return path }
    path.move(to: first)
    for (previous, point) in zip(stroke, stroke.dropFirst()) {
      let midpoint = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
      path.addQuadCurve(to: midpoint, control: previous)
    }
    path.addLine(to: last)
    return path
  }

  /// The area the strokes cover, including their line width. Null when there are none.
  static func bounds(of strokes: [[CGPoint]]) -> CGRect {
    let path = CGMutablePath()
    for stroke in strokes {
      path.addPath(self.path(for: stroke))
    }
    return path.boundingBoxOfPath.insetBy(dx: -lineWidth, dy: -lineWidth)
  }

  /// Draws the strokes the same way on screen and in the screenshot.
  static func draw(_ strokes: [[CGPoint]], in context: CGContext) {
    context.saveGState()
    context.setStrokeColor(strokeColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    // A soft shadow keeps the ink readable over red or busy content
    context.setShadow(offset: .zero, blur: 3, color: CGColor(gray: 0, alpha: 0.35))
    for stroke in strokes {
      context.addPath(path(for: stroke))
      context.strokePath()
    }
    context.restoreGState()
  }

  /// The part of the screen to keep in an annotated screenshot: the marked area plus a
  /// margin of context, grown to `minimumCropSize` and slid back on screen where needed.
  /// Returns the whole screen when the crop would cover most of it anyway.
  static func cropRect(around marked: CGRect, in screen: CGRect) -> CGRect {
    guard !marked.isNull else { return screen }

    let margin = min(max(max(marked.width, marked.height) * 0.15, 32), 120)
    let padded = marked.insetBy(dx: -margin, dy: -margin)
    let width = min(max(padded.width, minimumCropSize.width), screen.width)
    let height = min(max(padded.height, minimumCropSize.height), screen.height)
    let crop = CGRect(
      x: min(max(padded.midX - width / 2, screen.minX), screen.maxX - width),
      y: min(max(padded.midY - height / 2, screen.minY), screen.maxY - height),
      width: width,
      height: height
    )

    let coverage = (crop.width * crop.height) / (screen.width * screen.height)
    return coverage > fullScreenCoverage ? screen : crop
  }
}
