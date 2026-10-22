import SwiftUI

/// What the pill shows between recordings while notes mode is on.
struct OverlayNotesMode {
  let screenshotsAvailable: Bool
  let stop: @MainActor () -> Void
}

struct OverlayView: View {
  let status: RecordingStatus
  let showingProfileName: String?
  let showingProfileIconName: String?
  let currentInputDevice: String
  let activeProfileIconName: String?
  let errorCategory: ErrorCategory?
  let errorRecoveryHint: String?
  /// Set while notes mode is on. Recordings show their usual status; in between, the
  /// pill shows the mode and a button to stop it.
  let notesMode: OverlayNotesMode?

  init(
    status: RecordingStatus,
    showingProfileName: String? = nil,
    showingProfileIconName: String? = nil,
    currentInputDevice: String = "",
    activeProfileIconName: String? = nil,
    errorCategory: ErrorCategory? = nil,
    errorRecoveryHint: String? = nil,
    notesMode: OverlayNotesMode? = nil
  ) {
    self.status = status
    self.showingProfileName = showingProfileName
    self.showingProfileIconName = showingProfileIconName
    self.currentInputDevice = currentInputDevice
    self.activeProfileIconName = activeProfileIconName
    self.errorCategory = errorCategory
    self.errorRecoveryHint = errorRecoveryHint
    self.notesMode = notesMode
  }

  var body: some View {
    let showContent = status != .idle

    ZStack {
      // Background with border and shadow
      RoundedRectangle(cornerRadius: 40)
        .fill(
          LinearGradient(
            colors: [
              Constants.Colors.bg,
              Constants.Colors.bg,
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

      // Content
      if status == .idle, let notesMode {
        notesModeContent(notesMode)
      } else if showContent {
        HStack(spacing: 0) {
          iconSlot(statusIcon, color: statusIconColor)

          // Text content - centered in remaining space
          if let profileName = showingProfileName, status != .error {
            HStack(spacing: 6) {
              Image(systemName: profileDisplaySymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16, alignment: .center)

              Text(profileName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Constants.Colors.text)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
          } else if status == .error && errorCategory != nil {
            // Error state with category subtitle
            VStack(spacing: 2) {
              Text(errorRecoveryHint == nil ? displayText : "Paste failed")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Constants.Colors.text)
                .lineLimit(1)

              if let category = errorCategory {
                Text(errorRecoveryHint ?? category.rawValue)
                  .font(.system(size: 10, weight: .regular))
                  .foregroundColor(Constants.Colors.text.opacity(0.7))
                  .lineLimit(1)
              }
            }
            .frame(maxWidth: .infinity, alignment: .center)
          } else {
            Text(displayText)
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(Constants.Colors.text)
              .lineLimit(1)
              // Shrinks a little before truncating, enough for "MacBook Pro Microphone"
              .minimumScaleFactor(0.85)
              .frame(maxWidth: .infinity, alignment: .center)
          }

          // Waveform indicator - only show once input is live. It reads AudioLevelMeter from
          // the environment itself so mic ticks don't re-render this view.
          if shouldShowWaveform && showContent {
            HStack(spacing: 4) {
              OverlayWaveformView()
            }
            .frame(width: 36, alignment: .trailing)
            .padding(.trailing, 10)
          } else {
            Spacer()
              .frame(width: 36, alignment: .trailing)
              .padding(.trailing, 10)
          }
        }
      }
    }
    .frame(
      width: Constants.Overlay.activeWidth,
      height: Constants.Overlay.activeHeight
    )
  }

  /// Icon container - fixed width to match the right slot
  private func iconSlot(_ systemName: String, color: Color) -> some View {
    Circle()
      .fill(Color.clear)
      .frame(width: 28, height: 28)
      .overlay(
        Image(systemName: systemName)
          .font(.system(size: iconFontSize, weight: .medium))
          .foregroundColor(color)
      )
      .frame(width: 36, alignment: .leading)  // Match the right padding width
      .padding(.leading, 4)
  }

  /// Laid out like the error state, with the stop button where the waveform goes.
  private func notesModeContent(_ notesMode: OverlayNotesMode) -> some View {
    HStack(spacing: 0) {
      iconSlot("scribble.variable", color: .accentColor)

      VStack(spacing: 2) {
        Text("Notes mode")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(Constants.Colors.text)
          .lineLimit(1)

        if !notesMode.screenshotsAvailable {
          Text("Screenshots off")
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(.orange)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)

      Button(action: notesMode.stop) {
        Image(systemName: "stop.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(Color.red.opacity(0.85))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Stop notes mode")
      .frame(width: 36, alignment: .trailing)
      .padding(.trailing, 10)
    }
  }

  private var statusIcon: String {
    OverlayPresentation.statusIconName(for: status, recordingIconName: recordingIconSymbol)
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
    switch OverlayPresentation.statusTone(for: status) {
    case .neutral:
      return .gray
    case .preparing:
      return .orange
    case .recording:
      return .red
    case .processing:
      return .yellow
    case .postProcessing:
      return .purple
    case .success:
      return .green
    case .cancelled:
      return .orange
    case .confirming:
      return .orange
    case .error:
      return .red
    }
  }

  private var displayText: String {
    OverlayPresentation.displayText(
      status: status,
      showingProfileName: showingProfileName,
      currentInputDevice: currentInputDevice
    )
  }

  private var profileDisplaySymbol: String {
    ProfileAppearancePalette.displaySymbol(for: showingProfileIconName)
  }

  private var shouldShowWaveform: Bool {
    OverlayPresentation.shouldShowWaveform(for: status)
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
    case .noSpeechDetected:
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
private struct OverlayViewRecordingPreview: View {
  let deviceName: String

  var body: some View {
    return OverlayView(
      status: .recording,
      currentInputDevice: deviceName
    )
  }
}

private struct OverlayViewProfilePreview: View {
  let profileName: String
  let iconName: String?

  var body: some View {
    return OverlayView(
      status: .recording,
      showingProfileName: profileName,
      showingProfileIconName: iconName
    )
  }
}

#Preview("Animated") {
  struct OverlayViewAnimatedPreview: View {
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
            OverlayView(status: currentStatus)
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

  return OverlayViewAnimatedPreview()
    .environmentObject(AudioLevelMeter.shared)
}

#Preview("Static States") {
  struct StaticPreviewRow: View {
    let status: RecordingStatus
    var body: some View {
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
            OverlayView(status: status)
            Spacer()
          }
        }
        .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
        .background(Color.black.opacity(0.1))
        .border(Color.gray.opacity(0.3))
      }
    }
  }

  struct ProfilePreviewRow: View {
    let label: String
    let profileName: String
    let iconName: String?
    var body: some View {
      HStack {
        Text(label)
          .font(.caption)
          .foregroundColor(.primary)
          .frame(width: 120, alignment: .leading)

        Spacer()

        VStack {
          Spacer()
          HStack {
            Spacer()
            OverlayViewProfilePreview(profileName: profileName, iconName: iconName)
            Spacer()
          }
        }
        .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
        .background(Color.black.opacity(0.1))
        .border(Color.gray.opacity(0.3))
      }
    }
  }

  struct NotesModePreviewRow: View {
    let label: String
    let screenshotsAvailable: Bool
    var body: some View {
      HStack {
        Text(label)
          .font(.caption)
          .foregroundColor(.primary)
          .frame(width: 120, alignment: .leading)

        Spacer()

        VStack {
          Spacer()
          HStack {
            Spacer()
            OverlayView(
              status: .idle,
              notesMode: OverlayNotesMode(
                screenshotsAvailable: screenshotsAvailable,
                stop: {}
              )
            )
            Spacer()
          }
        }
        .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
        .background(Color.black.opacity(0.1))
        .border(Color.gray.opacity(0.3))
      }
    }
  }

  struct DevicePreviewRow: View {
    let label: String
    let deviceName: String
    var body: some View {
      HStack {
        Text(label)
          .font(.caption)
          .foregroundColor(.primary)
          .frame(width: 120, alignment: .leading)

        Spacer()

        VStack {
          Spacer()
          HStack {
            Spacer()
            OverlayViewRecordingPreview(deviceName: deviceName)
            Spacer()
          }
        }
        .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
        .background(Color.black.opacity(0.1))
        .border(Color.gray.opacity(0.3))
      }
    }
  }

  return VStack(spacing: 30) {
    ForEach(
      [
        RecordingStatus.idle, .initiatingRecording, .recording, .processing, .inserted, .cancelled,
        .confirmingCancel, .error,
      ], id: \.self
    ) { status in
      StaticPreviewRow(status: status)
    }

    NotesModePreviewRow(label: "Notes mode", screenshotsAvailable: true)
    NotesModePreviewRow(label: "Notes, no screenshots", screenshotsAvailable: false)

    DevicePreviewRow(label: "Recording with Built-in Mic", deviceName: "Built-in Microphone")
    ProfilePreviewRow(
      label: "Profile: Focus Mode", profileName: "Focus Mode", iconName: "bolt.circle.fill")
    ProfilePreviewRow(
      label: "Profile: Meeting Notes", profileName: "Meeting Notes",
      iconName: "person.2.circle.fill")
    ProfilePreviewRow(
      label: "Profile: Code Review", profileName: "Code Review", iconName: "eye.circle.fill")
    ProfilePreviewRow(
      label: "Profile: Quick Capture", profileName: "Quick Capture",
      iconName: "arrow.down.circle.fill")
    DevicePreviewRow(label: "Recording with External Mic", deviceName: "Blue Yeti USB Microphone")
    DevicePreviewRow(
      label: "Recording with Long Name", deviceName: "Sony WH-1000XM4 Wireless Headphones")
  }
  .padding(40)
  .background(Constants.Colors.bg)
  .environmentObject(AudioLevelMeter.shared)
}
