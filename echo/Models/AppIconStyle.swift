import AppKit

/// The app icon styles bundled in Assets.xcassets (drawn by scripts/make-icons.py).
///
/// Line is the icon the build uses (AppIcon). Red and Night are bundled so a setting can
/// offer them later: `NSApp.applicationIconImage = style.image` changes the Dock icon
/// while Echo runs. Finder keeps showing AppIcon.
enum AppIconStyle: String, CaseIterable {
  case line
  case red
  case night

  static let current: AppIconStyle = .line

  var assetName: String { "AppIcon" + rawValue.capitalized }

  var image: NSImage? { NSImage(named: assetName) }
}
