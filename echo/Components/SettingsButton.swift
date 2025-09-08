import SwiftUI

// Environment keys for button properties
struct ButtonSizeKey: EnvironmentKey {
  static let defaultValue: SettingsButtonSize = .medium
}

struct ButtonStyleVariantKey: EnvironmentKey {
  static let defaultValue: SettingsButtonStyleVariant = .primary
}

extension EnvironmentValues {
  var buttonSize: SettingsButtonSize {
    get { self[ButtonSizeKey.self] }
    set { self[ButtonSizeKey.self] = newValue }
  }

  var buttonStyleVariant: SettingsButtonStyleVariant {
    get { self[ButtonStyleVariantKey.self] }
    set { self[ButtonStyleVariantKey.self] = newValue }
  }
}

enum SettingsButtonSize {
  case small, medium, large

  var padding: EdgeInsets {
    switch self {
    case .small: return EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
    case .medium: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    case .large: return EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
    }
  }

  var cornerRadius: CGFloat {
    switch self {
    case .small: return 4
    case .medium: return 6
    case .large: return 8
    }
  }
}

enum SettingsButtonStyleVariant {
  case primary, secondary, destructive, bare

  var backgroundColor: Color {
    switch self {
    case .primary: return .accentColor
    case .secondary: return Color.secondary.opacity(0.1)
    case .destructive: return .clear
    case .bare: return .clear
    }
  }

  var foregroundColor: Color {
    switch self {
    case .primary: return .white
    case .secondary: return .primary
    case .destructive: return .red
    case .bare: return .secondary
    }
  }

  var hoverColor: Color {
    switch self {
    case .primary: return Color.accentColor.opacity(0.8)
    case .secondary: return Color.gray.opacity(0.15)
    case .destructive: return Color.red.opacity(0.1)
    case .bare: return Color.gray.opacity(0.15)
    }
  }

  var strokeColor: Color {
    switch self {
    case .primary: return Color.clear
    case .secondary: return Color.gray.opacity(0.5)
    case .destructive: return Color.red.opacity(0.5)
    case .bare: return Color.clear
    }
  }

  var hoverForegroundColor: Color {
    switch self {
    case .primary: return .white
    case .secondary: return .primary
    case .destructive: return .red
    case .bare: return .primary
    }
  }
}

struct SettingsButton: ButtonStyle {
  @Environment(\.buttonSize) var size
  @Environment(\.buttonStyleVariant) var styleVariant
  @State private var isHovering: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundColor(
        isHovering ? styleVariant.hoverForegroundColor : styleVariant.foregroundColor
      )
      .padding(size.padding)
      .background(
        RoundedRectangle(cornerRadius: size.cornerRadius)
          .fill(isHovering ? styleVariant.hoverColor : styleVariant.backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: size.cornerRadius)
          .stroke(
            isHovering ? styleVariant.strokeColor.opacity(0.8) : styleVariant.strokeColor,
            lineWidth: styleVariant == .bare ? 0 : 1)
      )
      .onHover { hovering in
        isHovering = hovering
      }
  }
}

// Convenience view modifiers
extension View {
  func settingsButtonSize(_ size: SettingsButtonSize) -> some View {
    environment(\.buttonSize, size)
  }

  func settingsButtonStyle(_ style: SettingsButtonStyleVariant) -> some View {
    environment(\.buttonStyleVariant, style)
  }
}

#if DEBUG
  struct SettingsButton_Previews: PreviewProvider {
    static var previews: some View {
      VStack(spacing: 20) {
        Text("Settings Button Sizes & Styles")
          .font(.headline)

        // Size variants
        HStack(spacing: 16) {
          Button("Small") {}
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.small)

          Button("Medium") {}
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)

          Button("Large") {}
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.large)
        }

        // Style variants
        HStack(spacing: 16) {
          Button("Primary") {}
            .buttonStyle(SettingsButton())
            .settingsButtonStyle(.primary)

          Button("Secondary") {}
            .buttonStyle(SettingsButton())
            .settingsButtonStyle(.secondary)

          Button("Destructive") {}
            .buttonStyle(SettingsButton())
            .settingsButtonStyle(.destructive)

          Button("Bare") {}
            .buttonStyle(SettingsButton())
            .settingsButtonStyle(.bare)
        }

        // Combined size and style
        HStack(spacing: 16) {
          Button("Save") {}
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.primary)

          Button("Cancel") {}
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.secondary)

          Button("Delete") {}
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.destructive)
        }

        Divider()

        Text("Buttons with Icons")
          .font(.headline)

        // Icon-only buttons
        HStack(spacing: 16) {
          Button {
            // Back action
          } label: {
            Image(systemName: "chevron.left")
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.bare)

          Button {
            // Settings action
          } label: {
            Image(systemName: "gearshape")
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.primary)

          Button {
            // Add action
          } label: {
            Image(systemName: "plus")
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.primary)

          Button {
            // Refresh action
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.secondary)

          Button {
            // Delete action
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.destructive)
        }

        // Buttons with text and icons
        HStack(spacing: 16) {
          Button {
            // Save action
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "checkmark")
              Text("Save")
            }
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.primary)

          Button {
            // Export action
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "square.and.arrow.up")
              Text("Export")
            }
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.secondary)

          Button {
            // Remove action
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "minus.circle")
              Text("Remove")
            }
          }
          .buttonStyle(SettingsButton())
          .settingsButtonSize(.medium)
          .settingsButtonStyle(.destructive)
        }

        // Different sizes with icons
        VStack(spacing: 12) {
          Text("Icon Buttons - Different Sizes")
            .font(.subheadline)
            .foregroundColor(.secondary)

          HStack(spacing: 16) {
            Button {
              // Small action
            } label: {
              HStack(spacing: 2) {
                Image(systemName: "heart")
                Text("Like")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.small)
            .settingsButtonStyle(.primary)

            Button {
              // Medium action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "star")
                Text("Favorite")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.primary)

            Button {
              // Large action
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "crown")
                Text("Premium")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.large)
            .settingsButtonStyle(.primary)
          }
        }

        // Practical examples
        VStack(spacing: 12) {
          Text("Practical Examples")
            .font(.subheadline)
            .foregroundColor(.secondary)

          // Navigation example with bare style
          HStack(spacing: 12) {
            Button {
              // Back navigation
            } label: {
              Image(systemName: "chevron.left")
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.bare)

            Text("Navigation Example")
              .font(.headline)

            Spacer()
          }

          HStack(spacing: 12) {
            Button {
              // Record action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "mic.circle.fill")
                Text("Record")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.primary)

            Button {
              // Stop action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "stop.circle")
                Text("Stop")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.destructive)

            Button {
              // Play action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "play.circle")
                Text("Play")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.secondary)
          }

          HStack(spacing: 12) {
            Button {
              // Copy action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                Text("Copy")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.secondary)

            Button {
              // Share action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                Text("Share")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.primary)

            Button {
              // Download action
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                Text("Download")
              }
            }
            .buttonStyle(SettingsButton())
            .settingsButtonSize(.medium)
            .settingsButtonStyle(.primary)
          }
        }

        Text("Hover over buttons to see effects")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding()
      .frame(minWidth: 600, minHeight: 800)
      .previewLayout(.sizeThatFits)
    }
  }
#endif
