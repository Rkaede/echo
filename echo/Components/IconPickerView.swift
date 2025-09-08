import SwiftUI

struct IconPickerView: View {
  @Binding var iconName: String?
  let colorToken: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Icon")
        .font(.subheadline)
        .fontWeight(.semibold)

      let tint = ProfileAppearancePalette.color(for: colorToken)

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 56), spacing: 10)], spacing: 10) {
        ForEach(ProfileAppearancePalette.iconOptions) { option in
          Button {
            iconName = option.symbol
          } label: {
            let isSelected: Bool = {
              if option.symbol == nil {
                return iconName == nil || iconName?.isEmpty == true
              }
              guard let symbol = option.symbol else { return false }
              return iconName == symbol
            }()

            let tileBackground = isSelected
              ? (option.symbol != nil ? (tint?.opacity(0.22) ?? Color.secondary.opacity(0.16)) : Color.secondary.opacity(0.16))
              : Color.clear
            let borderColor = isSelected
              ? (option.symbol != nil ? (tint ?? Color.accentColor) : Color.accentColor)
              : Color.secondary.opacity(0.18)
            let iconColor = isSelected
              ? (option.symbol != nil ? (tint ?? Color.primary) : Color.primary)
              : (option.symbol != nil ? Color.primary : .secondary)

            ZStack {
              RoundedRectangle(cornerRadius: 8)
                .fill(tileBackground)
              RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)

              if let symbol = option.symbol {
                Image(systemName: symbol)
                  .font(.system(size: 18, weight: .semibold))
                  .foregroundColor(iconColor)
              } else {
                Image(systemName: "slash.circle")
                  .font(.system(size: 18, weight: .semibold))
                  .foregroundColor(.secondary)
              }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(option.symbol == nil ? "No icon" : option.label)
        }
      }
      .padding(.vertical, 2)
    }
  }
}
