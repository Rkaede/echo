import SwiftUI

  struct OverlayColors {
    static let muted = Color.gray.opacity(0.8)
    static let muted2 = Color(hue: 0.12, saturation: 0.04, brightness: 0.9)
    // overlay colors
    static let red = Color(red: 1.0, green: 0.0, blue: 0.29, opacity: 1.0)
    static let green = Color(red: 0.463, green: 1.0, blue: 0.114, opacity: 1.0)
    static let bg = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 1)
    static let bg2 = Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.9)
    static let text = Color(red: 0.1, green: 0.1, blue: 0.1, opacity: 0.8)
  }



struct OverlayViewV2: View {
  let status: RecordingStatus
  let showingProfileName: String?
  let showingProfileIconName: String?
  let currentInputDevice: String
  let currentInputLevel: Float
  let activeProfileIconName: String?

  // Animation configuration
  private let containerAnimation = Animation.smooth(duration: 0.3)
  private let contentAnimation = Animation.smooth(duration: 0.2)
  private let containerDuration: Double = 0.3
  private let contentDuration: Double = 0.2

  // Internal staging state
  @State private var isExpanded: Bool
  @State private var showContent: Bool
  @State private var animationTask: Task<Void, Never>? = nil

  init(
    status: RecordingStatus,
    showingProfileName: String? = nil,
    showingProfileIconName: String? = nil,
    currentInputDevice: String = "",
    currentInputLevel: Float = 0.0,
    activeProfileIconName: String? = nil
  ) {
    self.status = status
    self.showingProfileName = showingProfileName
    self.showingProfileIconName = showingProfileIconName
    self.currentInputDevice = currentInputDevice
    self.currentInputLevel = currentInputLevel
    self.activeProfileIconName = activeProfileIconName
    // Initialize internal state to match current status without animating on first render
    _isExpanded = State(initialValue: status != .idle)
    _showContent = State(initialValue: status != .idle)
  }

  var body: some View {
    ZStack {
      // Background with border and shadow
      RoundedRectangle(cornerRadius: 40)
        .fill(
          LinearGradient(
            colors: [
              OverlayColors.bg,
              OverlayColors.bg
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

      // Content
      if showContent {
        HStack(spacing: 0) {
          // Icon container - fixed width to match right padding
          Circle()
            .fill(statusColor.opacity(0.0))
            .frame(width: 28, height: 28)
            .overlay(
              Image(systemName: statusIcon)
                .font(.system(size: iconFontSize, weight: .medium))
                .foregroundColor(statusIconColor)
            )
            .frame(width: 36, alignment: .leading) // Match the right padding width
            .padding(.leading, 4)

          // Text content - centered in remaining space
          if let profileName = showingProfileName {
            HStack(spacing: 6) {
              Image(systemName: profileDisplaySymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16, alignment: .center)

              Text(profileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(OverlayColors.text)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(nil, value: showingProfileName)
            .animation(nil, value: showingProfileIconName)
          } else {
            Text(displayText)
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(OverlayColors.text)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .center)
              .transition(.opacity.combined(with: .scale(scale: 0.98)))
              .animation(.easeInOut(duration: 0.3), value: displayText)
          }

          // Waveform indicator - only show during recording and idle states when content is visible
          if shouldShowWaveform && showContent {
            OverlayWaveformView(level: CGFloat(currentInputLevel))
              .frame(width: 36, alignment: .trailing)
              .padding(.trailing, 10)
          } else {
            Spacer()
              .frame(width: 36, alignment: .trailing)
              .padding(.trailing, 10)
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }
    }
    .frame(
      width: isExpanded ? Constants.Overlay.activeWidth : Constants.Overlay.idleWidth,
      height: isExpanded ? Constants.Overlay.activeHeight : Constants.Overlay.idleHeight,
    )
    // .preferredColorScheme(.dark)
    .onChange(of: status) { _, newStatus in
      runStagedAnimation(for: newStatus)
    }
    .onAppear {
      // Ensure internal state reflects incoming status on first appearance without extra animation
      isExpanded = status != .idle
      showContent = status != .idle
    }
  }

  @MainActor
  private func runStagedAnimation(for newStatus: RecordingStatus) {
    // Cancel any in-flight staging
    animationTask?.cancel()

    // If moving between non-idle states and content is already visible and expanded, no staging needed
    if newStatus != .idle && isExpanded && showContent {
      print("OverlayViewV2: Early return - already expanded and showing content")
      return
    }

    print("OverlayViewV2: Starting staged animation for \(newStatus) (isExpanded: \(isExpanded), showContent: \(showContent))")

    animationTask = Task { @MainActor in
      if newStatus == .idle {
        // Fade out content first, then shrink container
        if showContent {
          print("OverlayViewV2: Hiding content")
          withAnimation(contentAnimation) {
            showContent = false
          }
          // Wait for full content animation to complete before shrinking container
          try? await Task.sleep(nanoseconds: UInt64(contentDuration * 1_000_000_000))
        }
        print("OverlayViewV2: Shrinking container")
        withAnimation(containerAnimation) {
          isExpanded = false
        }
      } else {
        // Expand container first, then fade in content
        print("OverlayViewV2: Expanding container")
        withAnimation(containerAnimation) {
          isExpanded = true
        }
        // Wait for container animation plus extra buffer before showing content
        print("OverlayViewV2: Waiting before showing content...")
        try? await Task.sleep(nanoseconds: UInt64(containerDuration * 1.5 * 1_000_000_000))

        // Check if task was cancelled during sleep
        if Task.isCancelled {
          print("OverlayViewV2: Task cancelled, skipping content show")
          return
        }

        if !showContent {
          print("OverlayViewV2: Showing content now")
          withAnimation(contentAnimation) {
            showContent = true
          }
        } else {
          print("OverlayViewV2: Content already visible, skipping")
        }
      }
    }
  }

  private var statusIcon: String {
    switch status {
    case .idle:
      return "mic.circle"
    case .initiatingRecording:
      return "record.circle.fill"
    case .recording:
      return recordingIconSymbol
    case .processing:
      return "sparkles"
    case .postProcessing:
      return "wand.and.rays"
    case .inserted:
      return "checkmark.circle.fill"
    case .cancelled:
      return "xmark.circle.fill"
    case .confirmingCancel:
      return "questionmark.circle.fill"
    case .error:
      return "exclamationmark.circle.fill"
    }
  }

  private var recordingIconSymbol: String {
    let iconName = showingProfileIconName ?? activeProfileIconName
    return ProfileAppearancePalette.displaySymbol(for: iconName)
  }

  private var iconFontSize: CGFloat {
    return 20
  }

  private var statusIconColor: Color {
    return statusColor
  }

  private var statusColor: Color {
    switch status {
    case .idle:
      return .gray
    case .initiatingRecording:
      return .red.opacity(0.5)
    case .recording:
      return .red
    case .processing:
      return .yellow
    case .postProcessing:
      return .purple
    case .inserted:
      return .green
    case .cancelled:
      return .orange
    case .confirmingCancel:
      return .orange
    case .error:
      return .red
    }
  }

  private var statusText: String {
    switch status {
    case .initiatingRecording:
      return "Recording"
    case .inserted:
      return "Done"
    case .confirmingCancel:
      return "Are you sure? (Esc)"
    default:
      return status.rawValue.capitalized
    }
  }

  private var displayText: String {
    // Priority 1: Show profile name if switching profiles
    if let profileName = showingProfileName {
      return profileName
    }
    // Priority 2: Show recording device when recording
    else if status == .recording && !currentInputDevice.isEmpty {
      return currentInputDevice
    }
    // Priority 3: Show status text
    else {
      return statusText
    }
  }

  private var profileDisplaySymbol: String {
    ProfileAppearancePalette.displaySymbol(for: showingProfileIconName)
  }

  private var shouldShowWaveform: Bool {
    switch status {
    case .idle, .initiatingRecording, .recording:
      return true
    case .processing, .postProcessing, .inserted, .cancelled, .confirmingCancel, .error:
      return false
    }
  }

  private var backgroundColorForStatus: Color {
    switch status {
    case .idle:
      return Color(NSColor.windowBackgroundColor)
    case .initiatingRecording, .recording:
      return Color.red
    case .processing:
      return Color.orange
    case .postProcessing:
      return Color.purple
    case .inserted:
      return Color.green
    case .cancelled:
      return Color.orange
    case .confirmingCancel:
      return Color.orange
    case .error:
      return Color.red
    }
  }
}



// MARK: - Preview

// Helper used only in previews
private struct OverlayViewV2RecordingPreview: View {
  let deviceName: String

  var body: some View {
    return OverlayViewV2(
      status: .recording,
      currentInputDevice: deviceName,
      currentInputLevel: 0.65
    )
  }
}

private struct OverlayViewV2ProfilePreview: View {
  let profileName: String
  let iconName: String?

  var body: some View {
    return OverlayViewV2(
      status: .recording,
      showingProfileName: profileName,
      showingProfileIconName: iconName,
      currentInputLevel: 0.5
    )
  }
}

#Preview("Animated") {
  struct OverlayViewV2AnimatedPreview: View {
    @State private var currentStatus: RecordingStatus = .idle
    let statuses: [RecordingStatus] = [
      .idle, .initiatingRecording, .recording, .processing, .inserted, .error,
    ]

    var body: some View {
      VStack(spacing: 20) {
        VStack {
          Spacer()
          HStack {
            Spacer()
            OverlayViewV2(status: currentStatus)
            Spacer()
          }
        }
        .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.activeHeight)
        .background(Color.black.opacity(0.1))
        .border(Color.gray.opacity(0.3))

        HStack(spacing: 16) {
          Button("Toggle Idle/Initiating") {
            currentStatus = currentStatus == .idle ? .initiatingRecording : .idle
          }
          .buttonStyle(.borderedProminent)

          Button("Next State") {
            if let currentIndex = statuses.firstIndex(of: currentStatus) {
              let nextIndex = (currentIndex + 1) % statuses.count
              currentStatus = statuses[nextIndex]
            }
          }
        }

        Text("Current: \(currentStatus.rawValue)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(40)
      .background(.secondary)
    }
  }

  return OverlayViewV2AnimatedPreview()
}


#Preview("Static States") {
  VStack(spacing: 30) {
    ForEach(
      [
        RecordingStatus.idle, .initiatingRecording, .recording, .processing, .inserted, .cancelled,
        .confirmingCancel, .error,
      ], id: \.self
    ) { status in
      HStack {
        Text(status.rawValue.capitalized)
          .font(.caption)
          .foregroundColor(.primary)
          .frame(width: 120, alignment: .leading)

        Spacer()

        VStack {
          Spacer()
          HStack {
            Spacer()
            OverlayViewV2(status: status)
            Spacer()
          }
        }
        .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
        .background(Color.black.opacity(0.1))
        .border(Color.gray.opacity(0.3))
      }
    }
    
    // Recording with microphone device names
    HStack {
      Text("Recording with Built-in Mic")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2RecordingPreview(deviceName: "Built-in Microphone")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }
    
    HStack {
      Text("Profile: Focus Mode")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2ProfilePreview(profileName: "Focus Mode", iconName: "bolt.circle.fill")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }

    HStack {
      Text("Profile: Meeting Notes")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2ProfilePreview(profileName: "Meeting Notes", iconName: "person.2.circle.fill")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }

    HStack {
      Text("Profile: Code Review")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2ProfilePreview(profileName: "Code Review", iconName: "curlybraces.circle.fill")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }

    HStack {
      Text("Profile: Quick Capture")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2ProfilePreview(profileName: "Quick Capture", iconName: "arrow.down.circle.fill")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }

    HStack {
      Text("Recording with External Mic")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2RecordingPreview(deviceName: "Blue Yeti USB Microphone")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }
    
    HStack {
      Text("Recording with Long Name")
        .font(.caption)
        .foregroundColor(.primary)
        .frame(width: 120, alignment: .leading)

      Spacer()

      VStack {
        Spacer()
        HStack {
          Spacer()
          OverlayViewV2RecordingPreview(deviceName: "Sony WH-1000XM4 Wireless Headphones")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }
  }
  .padding(40)
  .background(OverlayColors.bg)
}
