import SwiftUI

struct IconPickerView: View {
  @Binding var iconName: String?
  let colorToken: String?

  @State private var isPopoverPresented = false
  @State private var hoveredOptionID: String?

  private static let gridColumns = Array(
    repeating: GridItem(.fixed(36), spacing: 8),
    count: 8
  )

  private var tint: Color? {
    ProfileAppearancePalette.color(for: colorToken)
  }

  private var activeSymbol: String? {
    guard let iconName, !iconName.isEmpty else { return nil }
    return ProfileAppearancePalette.displaySymbol(for: iconName)
  }

  private var selectedLabel: String {
    guard let iconName, !iconName.isEmpty else { return "None" }
    return ProfileAppearancePalette.iconOptions.first { $0.symbol == iconName }?.label ?? "Custom"
  }

  var body: some View {
    Button {
      isPopoverPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        if let symbol = activeSymbol {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(tint ?? .primary)
        } else {
          Image(systemName: "slash.circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.secondary)
        }

        Text(selectedLabel)
          .foregroundColor(activeSymbol != nil ? .primary : .secondary)

        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(.secondary)
      }
    }
    .buttonStyle(.bordered)
    .accessibilityLabel("Icon: \(selectedLabel)")
    .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
      popoverContent
    }
  }

  private var popoverContent: some View {
    LazyVGrid(columns: Self.gridColumns, spacing: 8) {
      ForEach(ProfileAppearancePalette.iconOptions) { option in
        let isSelected = isOptionSelected(option)
        let isHovered = hoveredOptionID == option.id

        Button {
          iconName = option.symbol
          isPopoverPresented = false
        } label: {
          let tileBackground: Color = {
            if isSelected {
              return option.symbol != nil
                ? (tint?.opacity(0.22) ?? Color.secondary.opacity(0.16))
                : Color.secondary.opacity(0.16)
            }
            return isHovered ? Color.secondary.opacity(0.1) : Color.clear
          }()

          let borderColor: Color = {
            if isSelected {
              return option.symbol != nil ? (tint ?? Color.accentColor) : Color.accentColor
            }
            return Color.secondary.opacity(isHovered ? 0.35 : 0.18)
          }()

          let iconColor: Color = {
            if isSelected {
              return option.symbol != nil ? (tint ?? Color.primary) : Color.primary
            }
            return option.symbol != nil ? Color.primary : .secondary
          }()

          ZStack {
            RoundedRectangle(cornerRadius: 8)
              .fill(tileBackground)
            RoundedRectangle(cornerRadius: 8)
              .stroke(borderColor, lineWidth: isSelected ? 2 : 1)

            if let symbol = option.symbol {
              Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(iconColor)
            } else {
              Image(systemName: "slash.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.secondary)
            }
          }
          .frame(width: 36, height: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          if hovering {
            hoveredOptionID = option.id
          } else if hoveredOptionID == option.id {
            hoveredOptionID = nil
          }
        }
        .help(option.symbol == nil ? "No icon" : option.label)
        .accessibilityLabel(option.symbol == nil ? "No icon" : option.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(12)
  }

  private func isOptionSelected(_ option: ProfileAppearancePalette.IconOption) -> Bool {
    if option.symbol == nil {
      return iconName == nil || iconName?.isEmpty == true
    }
    return iconName == option.symbol
  }
}
