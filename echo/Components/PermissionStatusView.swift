import SwiftUI

struct PermissionStatusView: View {
  let title: String
  let description: String
  let icon: String
  let iconColor: Color
  let status: AppPermissionStatus
  let onEnable: () -> Void
  let onOpenSettings: (() -> Void)?
  let enableButtonLabel: String
  let enabledLabel: String
  
  init(
    title: String,
    description: String,
    icon: String,
    iconColor: Color,
    status: AppPermissionStatus,
    onEnable: @escaping () -> Void,
    onOpenSettings: (() -> Void)? = nil,
    enableButtonLabel: String = "Enable",
    enabledLabel: String = "Enabled"
  ) {
    self.title = title
    self.description = description
    self.icon = icon
    self.iconColor = iconColor
    self.status = status
    self.onEnable = onEnable
    self.onOpenSettings = onOpenSettings
    self.enableButtonLabel = enableButtonLabel
    self.enabledLabel = enabledLabel
  }
  
  var body: some View {
    HStack(spacing: 16) {
      // Icon
      ZStack {
        Circle()
          .fill(iconColor.opacity(0.1))
          .frame(width: 48, height: 48)
        
        Image(systemName: icon)
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(iconColor)
      }
      
      // Content
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .fontWeight(.semibold)
        
        Text(description)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      
      Spacer()
      
      // Status/Button
      Group {
        if status == .granted {
          HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundColor(.green)
              .font(.system(size: 16))
            Text(enabledLabel)
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.green)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.green.opacity(0.1))
          .cornerRadius(20)
        } else if status == .denied {
          if let onOpenSettings = onOpenSettings {
            HStack(spacing: 8) {
              HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.red)
                  .font(.system(size: 14))
                Text("Denied")
                  .font(.caption)
                  .fontWeight(.medium)
                  .foregroundColor(.red)
              }
              
              Button("Open Settings") {
                onOpenSettings()
              }
              .buttonStyle(.bordered)
//              .controlSize(.mini)
            }
          } else {
            // For onboarding view where we don't show denied state
            Button(enableButtonLabel) {
              onEnable()
            }
          }
        } else {
          Button(enableButtonLabel) {
            onEnable()
          }
        }
      }
    }
    .padding(20)
    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(status == .granted ? .green.opacity(0.3) : .gray.opacity(0.2), lineWidth: 1)
    )
    .cornerRadius(12)
  }
}

#Preview("Microphone - Unknown") {
  PermissionStatusView(
    title: "Microphone",
    description: "We need to borrow your mic to work our speech-to-text magic ✨",
    icon: "mic.fill",
    iconColor: .blue,
    status: .unknown,
    onEnable: {}
  )
  .frame(width: 480)
  .padding()
}

#Preview("Microphone - Granted") {
  PermissionStatusView(
    title: "Microphone",
    description: "We need to borrow your mic to work our speech-to-text magic ✨",
    icon: "mic.fill",
    iconColor: .blue,
    status: .granted,
    onEnable: {}
  )
  .frame(width: 480)
  .padding()
}

#Preview("Accessibility - Denied with Settings") {
  PermissionStatusView(
    title: "Accessibility",
    description: "Allow us to place transcribed text straight into your apps.",
    icon: "accessibility",
    iconColor: .green,
    status: .denied,
    onEnable: {},
    onOpenSettings: {},
    enableButtonLabel: "Grant",
    enabledLabel: "Granted"
  )
  .frame(width: 480)
  .padding()
}

#Preview("Accessibility - Denied without Settings") {
  PermissionStatusView(
    title: "Accessibility",
    description: "Allow us to place transcribed text straight into your apps.",
    icon: "accessibility",
    iconColor: .green,
    status: .denied,
    onEnable: {}
  )
  .frame(width: 480)
  .padding()
}

#Preview("All States") {
  VStack(spacing: 16) {
    PermissionStatusView(
      title: "Microphone",
      description: "Required for recording audio",
      icon: "mic.fill",
      iconColor: .blue,
      status: .unknown,
      onEnable: {}
    )
    
    PermissionStatusView(
      title: "Microphone",
      description: "Required for recording audio",
      icon: "mic.fill",
      iconColor: .blue,
      status: .granted,
      onEnable: {}
    )
    
    PermissionStatusView(
      title: "Accessibility",
      description: "Required for automatic text pasting",
      icon: "accessibility",
      iconColor: .green,
      status: .denied,
      onEnable: {},
      onOpenSettings: {},
      enableButtonLabel: "Grant",
      enabledLabel: "Granted"
    )
  }
  .frame(width: 480)
  .padding()
}
