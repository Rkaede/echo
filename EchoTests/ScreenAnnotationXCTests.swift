import XCTest

@testable import Echo

final class ScreenAnnotationXCTests: XCTestCase {
  private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

  func testBoundsIncludeLineWidth() {
    let bounds = ScreenAnnotation.bounds(of: [[CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10)]])

    XCTAssertEqual(bounds, CGRect(x: 6, y: 6, width: 108, height: 8))
  }

  func testBoundsOfNoStrokesIsNull() {
    XCTAssertTrue(ScreenAnnotation.bounds(of: []).isNull)
  }

  func testNoMarksKeepsWholeScreen() {
    XCTAssertEqual(ScreenAnnotation.cropRect(around: .null, in: screen), screen)
  }

  func testCircledWordGrowsToMinimumSizeAroundItsCenter() {
    let crop = ScreenAnnotation.cropRect(
      around: CGRect(x: 700, y: 400, width: 120, height: 40), in: screen)

    XCTAssertEqual(crop, CGRect(x: 520, y: 285, width: 480, height: 270))
  }

  func testLargerMarkGetsProportionalMargin() {
    let crop = ScreenAnnotation.cropRect(
      around: CGRect(x: 200, y: 200, width: 600, height: 300), in: screen)

    XCTAssertEqual(crop, CGRect(x: 110, y: 110, width: 780, height: 480))
  }

  func testMarkNearCornerSlidesCropOntoScreen() {
    let crop = ScreenAnnotation.cropRect(
      around: CGRect(x: 10, y: 860, width: 100, height: 30), in: screen)

    XCTAssertEqual(crop, CGRect(x: 0, y: 630, width: 480, height: 270))
  }

  func testWideUnderlineKeepsAFullWidthStrip() {
    let crop = ScreenAnnotation.cropRect(
      around: CGRect(x: 100, y: 500, width: 1200, height: 8), in: screen)

    XCTAssertEqual(crop, CGRect(x: 0, y: 369, width: 1440, height: 270))
  }

  func testMarksCoveringMostOfTheScreenKeepWholeScreen() {
    let crop = ScreenAnnotation.cropRect(
      around: CGRect(x: 100, y: 100, width: 1200, height: 700), in: screen)

    XCTAssertEqual(crop, screen)
  }

  func testAnnotatedScreenshotIsCroppedAroundStrokeAtRetinaScale() throws {
    let screenSize = CGSize(width: 1440, height: 900)
    let capture = try XCTUnwrap(Self.whiteImage(width: 2880, height: 1800))
    // A short stroke near the top-left corner, in bottom-left-origin points
    let stroke = [CGPoint(x: 40, y: 850), CGPoint(x: 60, y: 850)]

    let annotated = try XCTUnwrap(
      ScreenshotService.annotate(capture, strokes: [stroke], screenSize: screenSize))

    // The crop is the top-left 480x270 points, at 2x
    XCTAssertEqual(annotated.width, 960)
    XCTAssertEqual(annotated.height, 540)

    let pixels = try XCTUnwrap(Self.rgbaPixels(of: annotated))
    let ink = pixels.at(x: 100, yFromTop: 100)
    XCTAssertGreaterThan(ink.red, 200)
    XCTAssertLessThan(ink.green, 120)

    let background = pixels.at(x: 600, yFromTop: 400)
    XCTAssertGreaterThan(background.green, 240)
  }

  private struct Pixels {
    let data: [UInt8]
    let width: Int

    func at(x: Int, yFromTop: Int) -> (red: UInt8, green: UInt8) {
      let offset = (yFromTop * width + x) * 4
      return (data[offset], data[offset + 1])
    }
  }

  private static func rgbaContext(width: Int, height: Int) -> CGContext? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }

  private static func whiteImage(width: Int, height: Int) -> CGImage? {
    guard let context = rgbaContext(width: width, height: height) else { return nil }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  /// Bitmap contexts store rows top to bottom, so row 0 is the top of the image.
  private static func rgbaPixels(of image: CGImage) -> Pixels? {
    guard let context = rgbaContext(width: image.width, height: image.height) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return nil }
    let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    return Pixels(
      data: Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4)),
      width: image.width
    )
  }
}
