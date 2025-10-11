import SwiftUI

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

enum ProfileAppearancePalette {
  struct ColorOption: Identifiable {
    let label: String
    let token: String?
    let color: Color
    let overlayColor: Color
    let isClear: Bool

    init(
      label: String, token: String?, color: Color, overlayColor: Color? = nil, isClear: Bool = false
    ) {
      self.label = label
      self.token = token
      self.color = color
      self.overlayColor = overlayColor ?? color
      self.isClear = isClear
    }

    var id: String { label }
  }

  struct IconOption: Identifiable {
    let label: String
    let symbol: String?
    var id: String { label }
  }
  // these icons are not available in the system symbol set
  // umbrella.circle.fill
  // paintbrush.circle.fill
  // shield.circle.fill
  // music.note.circle.fill
  // globe.circle.fill
  // wrench.circle.fill
  // key.circle.fill
  // sparkles.circle.fill
  // building.circle.fill
  // display.circle.fill
  // scanner.circle.fill
  // laptopcomputer.circle.fill
  // ticket.circle.fill
  // chart.bar.circle.fill
  // chart.pie.circle.fill
  // percent.circle.fill
  // desktopcomputer.circle.fill
  // printer.circle.fill
  // powerplug.circle.fill
  // server.rack.circle.fill

  // do not add these icons:
  // xmark.circle.fill
  // pause.circle.fill
  // stop.circle.fill
  // battery.100.circle.fill
  // forward.circle.fill
  // backward.circle.fill
  // multiply.circle.fill
  // divide.circle.fill
  // cart.circle.fill
  // phone.circle.fill
  // gearshape.circle.fill
  // camera.circle.fill
  // video.circle.fill
  // folder.circle.fill
  // bag.circle.fill
  // link.circle.fill
  // paperclip.circle.fill

  static let iconOptions: [IconOption] = [
    IconOption(label: "None", symbol: nil),
    IconOption(label: "Mic", symbol: "mic.circle.fill"),
    IconOption(label: "Wave", symbol: "waveform.circle.fill"),
    IconOption(label: "Bolt", symbol: "bolt.circle.fill"),
    IconOption(label: "Star", symbol: "star.circle.fill"),
    IconOption(label: "Record", symbol: "record.circle.fill"),
    IconOption(label: "Chat", symbol: "message.circle.fill"),
    IconOption(label: "Clock", symbol: "clock.circle.fill"),
    IconOption(label: "Lightbulb", symbol: "lightbulb.circle.fill"),
    IconOption(label: "Bookmark", symbol: "bookmark.circle.fill"),
    IconOption(label: "Clipboard", symbol: "doc.circle.fill"),
    IconOption(label: "Headphones", symbol: "headphones.circle.fill"),
    IconOption(label: "People", symbol: "person.2.circle.fill"),
    IconOption(label: "Flame", symbol: "flame.circle.fill"),
    IconOption(label: "Download", symbol: "arrow.down.circle.fill"),
    IconOption(label: "Upload", symbol: "arrow.up.circle.fill"),
    IconOption(label: "Heart", symbol: "heart.circle.fill"),
    IconOption(label: "Bell", symbol: "bell.circle.fill"),
    IconOption(label: "Flag", symbol: "flag.circle.fill"),
    IconOption(label: "Tag", symbol: "tag.circle.fill"),
    IconOption(label: "Pin", symbol: "pin.circle.fill"),
    IconOption(label: "Map", symbol: "map.circle.fill"),
    IconOption(label: "Compass", symbol: "location.circle.fill"),
    IconOption(label: "Lock", symbol: "lock.circle.fill"),
    IconOption(label: "Eye", symbol: "eye.circle.fill"),
    IconOption(label: "Moon", symbol: "moon.circle.fill"),
    IconOption(label: "Sun", symbol: "sun.max.circle.fill"),
    IconOption(label: "Cloud", symbol: "cloud.circle.fill"),
    IconOption(label: "Gift", symbol: "gift.circle.fill"),
    IconOption(label: "Trophy", symbol: "trophy.circle.fill"),
    IconOption(label: "Gamepad", symbol: "gamecontroller.circle.fill"),
    IconOption(label: "Hammer", symbol: "hammer.circle.fill"),
    IconOption(label: "Trash", symbol: "trash.circle.fill"),
    IconOption(label: "Pencil", symbol: "pencil.circle.fill"),
    IconOption(label: "Envelope", symbol: "envelope.circle.fill"),
    IconOption(label: "Paperplane", symbol: "paperplane.circle.fill"),
    IconOption(label: "Calendar", symbol: "calendar.circle.fill"),
    IconOption(label: "Book", symbol: "book.circle.fill"),
    IconOption(label: "Photo", symbol: "photo.circle.fill"),
    IconOption(label: "Play", symbol: "play.circle.fill"),
    IconOption(label: "Speaker", symbol: "speaker.circle.fill"),
    IconOption(label: "Airplane", symbol: "airplane.circle.fill"),
    IconOption(label: "Car", symbol: "car.circle.fill"),
    IconOption(label: "Bicycle", symbol: "bicycle.circle.fill"),
    IconOption(label: "House", symbol: "house.circle.fill"),
    IconOption(label: "Tram", symbol: "tram.circle.fill"),
    IconOption(label: "Wifi", symbol: "wifi.circle.fill"),
    IconOption(label: "Antenna", symbol: "antenna.radiowaves.left.and.right.circle.fill"),
    IconOption(label: "At", symbol: "at.circle.fill"),
    IconOption(label: "Number", symbol: "number.circle.fill"),
    IconOption(label: "Plus", symbol: "plus.circle.fill"),
    IconOption(label: "Minus", symbol: "minus.circle.fill"),
    IconOption(label: "Equal", symbol: "equal.circle.fill"),
    IconOption(label: "Checkmark", symbol: "checkmark.circle.fill"),
    IconOption(label: "Question", symbol: "questionmark.circle.fill"),
    IconOption(label: "Exclamation", symbol: "exclamationmark.circle.fill"),
    IconOption(label: "Info", symbol: "info.circle.fill"),
    IconOption(label: "Ellipsis", symbol: "ellipsis.circle.fill"),
  ]

  static let colorOptions: [ColorOption] = [
    ColorOption(
      label: "Clear",
      token: nil,
      color: .clear,
      overlayColor: Color.white.opacity(0.85),
      isClear: true
    ),
    ColorOption(
      label: "Blue",
      token: "blue",
      color: Color(red: 0.12, green: 0.48, blue: 0.98),
      overlayColor: overlayVariant(red: 0.12, green: 0.48, blue: 0.98)
    ),
    ColorOption(
      label: "Indigo",
      token: "indigo",
      color: Color(red: 0.36, green: 0.27, blue: 0.94),
      overlayColor: overlayVariant(red: 0.36, green: 0.27, blue: 0.94)
    ),
    ColorOption(
      label: "Purple",
      token: "purple",
      color: Color(red: 0.63, green: 0.32, blue: 0.90),
      overlayColor: overlayVariant(red: 0.63, green: 0.32, blue: 0.90)
    ),
    ColorOption(
      label: "Pink",
      token: "pink",
      color: Color(red: 0.94, green: 0.36, blue: 0.64),
      overlayColor: overlayVariant(red: 0.94, green: 0.36, blue: 0.64)
    ),
    ColorOption(
      label: "Red",
      token: "red",
      color: Color(red: 0.95, green: 0.27, blue: 0.23),
      overlayColor: overlayVariant(red: 0.95, green: 0.27, blue: 0.23)
    ),
    ColorOption(
      label: "Orange",
      token: "orange",
      color: Color(red: 0.99, green: 0.59, blue: 0.15),
      overlayColor: overlayVariant(red: 0.99, green: 0.59, blue: 0.15)
    ),
    ColorOption(
      label: "Yellow",
      token: "yellow",
      color: Color(red: 0.99, green: 0.81, blue: 0.17),
      overlayColor: overlayVariant(red: 0.99, green: 0.81, blue: 0.17)
    ),
    ColorOption(
      label: "Green",
      token: "green",
      color: Color(red: 0.30, green: 0.78, blue: 0.36),
      overlayColor: overlayVariant(red: 0.30, green: 0.78, blue: 0.36)
    ),
    ColorOption(
      label: "Mint",
      token: "mint",
      color: Color(red: 0.53, green: 0.88, blue: 0.83),
      overlayColor: overlayVariant(red: 0.53, green: 0.88, blue: 0.83)
    ),
    ColorOption(
      label: "Teal",
      token: "teal",
      color: Color(red: 0.28, green: 0.65, blue: 0.73),
      overlayColor: overlayVariant(red: 0.28, green: 0.65, blue: 0.73)
    ),
    ColorOption(
      label: "Gray",
      token: "gray",
      color: Color(red: 0.55, green: 0.58, blue: 0.63),
      overlayColor: overlayVariant(red: 0.55, green: 0.58, blue: 0.63)
    ),
    ColorOption(
      label: "Black",
      token: "black",
      color: Color(red: 0.15, green: 0.15, blue: 0.15),
      overlayColor: overlayVariant(red: 0.15, green: 0.15, blue: 0.15, amount: 0.65)
    ),
    ColorOption(
      label: "Brown",
      token: "brown",
      color: Color(red: 0.64, green: 0.42, blue: 0.28),
      overlayColor: overlayVariant(red: 0.64, green: 0.42, blue: 0.28)
    ),
  ]

  private static let fallbackColor = Color.accentColor
  private static let fallbackOverlayColor = overlayVariant(color: Color.accentColor)

  static func color(for token: String?) -> Color? {
    guard let token, !token.isEmpty else { return nil }
    if let option = colorOptions.first(where: { option in
      guard let optionToken = option.token else { return false }
      return optionToken.caseInsensitiveCompare(token) == .orderedSame
    }) {
      return option.color
    }
    if let hexColor = colorFromHex(token) {
      return hexColor
    }
    return fallbackColor
  }

  static func overlayColor(for token: String?) -> Color? {
    guard let token, !token.isEmpty else { return nil }
    if let option = colorOptions.first(where: { option in
      guard let optionToken = option.token else { return false }
      return optionToken.caseInsensitiveCompare(token) == .orderedSame
    }) {
      return option.overlayColor
    }
    if let hexColor = overlayColorFromHex(token) {
      return hexColor
    }
    return fallbackOverlayColor
  }

  static func displaySymbol(for iconName: String?) -> String {
    guard let iconName, !iconName.isEmpty else { return "person.crop.circle" }
    return isValidSymbol(iconName) ? iconName : "questionmark.circle"
  }

  static func isValidSymbol(_ name: String) -> Bool {
    #if canImport(AppKit)
      return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    #elseif canImport(UIKit)
      return UIImage(systemName: name) != nil
    #else
      return !name.isEmpty
    #endif
  }

  private static func colorFromHex(_ hex: String) -> Color? {
    guard let components = colorComponents(from: hex) else { return nil }
    return Color(
      red: components.red,
      green: components.green,
      blue: components.blue,
      opacity: components.alpha
    )
  }

  private static func overlayColorFromHex(_ hex: String) -> Color? {
    guard let components = colorComponents(from: hex) else { return nil }
    return overlayVariant(
      red: components.red,
      green: components.green,
      blue: components.blue,
      alpha: components.alpha
    )
  }

  private static func colorComponents(from hex: String) -> (
    red: Double, green: Double, blue: Double, alpha: Double
  )? {
    var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if string.hasPrefix("#") { string.removeFirst() }
    guard string.count == 6 || string.count == 8 else { return nil }

    var value: UInt64 = 0
    guard Scanner(string: string).scanHexInt64(&value) else { return nil }

    let r: Double
    let g: Double
    let b: Double
    let a: Double
    if string.count == 8 {
      r = Double((value & 0xFF00_0000) >> 24) / 255.0
      g = Double((value & 0x00FF_0000) >> 16) / 255.0
      b = Double((value & 0x0000_FF00) >> 8) / 255.0
      a = Double(value & 0x0000_00FF) / 255.0
    } else {
      r = Double((value & 0xFF0000) >> 16) / 255.0
      g = Double((value & 0x00FF00) >> 8) / 255.0
      b = Double(value & 0x0000FF) / 255.0
      a = 1.0
    }

    return (r, g, b, a)
  }

  private static func overlayVariant(
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double = 1.0,
    amount: Double = 0.45
  ) -> Color {
    Color(
      red: lighten(red, amount: amount),
      green: lighten(green, amount: amount),
      blue: lighten(blue, amount: amount),
      opacity: alpha
    )
  }

  private static func overlayVariant(color: Color) -> Color {
    guard let cgColor = color.cgColor,
      let components = cgColor.components
    else { return color }

    switch components.count {
    case 2:  // grayscale + alpha
      let gray = Double(components[0])
      let alpha = Double(components[1])
      return overlayVariant(red: gray, green: gray, blue: gray, alpha: alpha)
    case 4:
      return overlayVariant(
        red: Double(components[0]),
        green: Double(components[1]),
        blue: Double(components[2]),
        alpha: Double(components[3])
      )
    default:
      return color
    }
  }

  private static func lighten(_ component: Double, amount: Double) -> Double {
    min(1.0, component + (1.0 - component) * amount)
  }
}
