import SwiftUI

struct ColorPickerView: View {
  @Binding var colorToken: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Color")
        .font(.subheadline)
        .fontWeight(.semibold)

      LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 10), count: 7), spacing: 10) {
        ForEach(ProfileAppearancePalette.colorOptions) { option in
          Button {
            colorToken = option.isClear ? nil : option.token
          } label: {
            let isSelected: Bool = {
              if option.isClear {
                return colorToken == nil || colorToken?.isEmpty == true
              }
              guard let token = option.token else { return false }
              return colorToken.map { $0.caseInsensitiveCompare(token) == .orderedSame } ?? false
            }()

            ZStack {
              Circle()
                .fill(Color.secondary.opacity(isSelected ? 0.18 : 0.07))
                .frame(width: 30, height: 30)
              Circle()
                .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                .frame(width: 26, height: 26)

              if option.isClear {
                Image(systemName: "slash.circle")
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundColor(.secondary)
              } else {
                Circle()
                  .fill(option.color)
                  .frame(width: 20, height: 20)
              }
            }
            .contentShape(Circle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 2)
    }
  }
}
