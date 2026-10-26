import SwiftUI
import XCTest

@testable import Echo

final class MenuShortcutXCTests: XCTestCase {
  func testDefaultNotesShortcutMapsToControlOptionN() throws {
    let shortcut = try XCTUnwrap(ShortcutUtils.menuShortcut(for: "ctrl+alt+n"))

    XCTAssertEqual(shortcut.key, KeyEquivalent("n"))
    XCTAssertEqual(shortcut.modifiers, [.control, .option])
  }

  func testAllModifiersAndSpecialKeysMap() throws {
    let shortcut = try XCTUnwrap(ShortcutUtils.menuShortcut(for: "Cmd+Shift+Option+Control+space"))

    XCTAssertEqual(shortcut.key, .space)
    XCTAssertEqual(shortcut.modifiers, [.control, .option, .shift, .command])
    XCTAssertEqual(ShortcutUtils.menuShortcut(for: "alt+left")?.key, .leftArrow)
  }

  func testUnrepresentableOrInvalidShortcutsReturnNil() {
    XCTAssertNil(ShortcutUtils.menuShortcut(for: "ctrl+f5"))
    XCTAssertNil(ShortcutUtils.menuShortcut(for: ""))
    XCTAssertNil(ShortcutUtils.menuShortcut(for: "ctrl+alt"))
  }
}
