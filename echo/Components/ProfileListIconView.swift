import SwiftUI

struct ProfileListIconView: View {
  let iconName: String?
  let colorToken: String?

  var body: some View {
    let hasIcon = iconName != nil && !iconName!.isEmpty
    let tint = hasIcon ? ProfileAppearancePalette.color(for: colorToken) : nil
    let symbol = ProfileAppearancePalette.displaySymbol(for: iconName)

    let background = hasIcon ? (tint?.opacity(0.18) ?? Color.secondary.opacity(0.1)) : Color.secondary.opacity(0.1)
    let foreground = hasIcon ? (tint ?? Color.secondary) : Color.secondary

    return ZStack {
      RoundedRectangle(cornerRadius: 10)
        .fill(background)
        .frame(width: 32, height: 32)

      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(foreground)
    }
  }
}
