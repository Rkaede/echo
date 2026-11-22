import XCTest

@testable import Echo

final class AppIconStyleXCTests: XCTestCase {
  func testEveryStyleIsBundled() {
    for style in AppIconStyle.allCases {
      XCTAssertNotNil(style.image, "\(style.assetName) is missing from the asset catalog")
    }
  }

  func testMenuBarIconIsATemplateImage() throws {
    let icon = try XCTUnwrap(NSImage(named: "MenuBarIcon"))
    XCTAssertTrue(icon.isTemplate)
  }
}
