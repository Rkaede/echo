import SwiftUI

struct OverlayView: View {
  let status: RecordingStatus
  @EnvironmentObject private var appState: AppState

  // Animation configuration
  private let containerAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8)
  private let contentAnimation = Animation.easeInOut(duration: 0.25)
  private let containerDuration: Double = 0.4
  private let contentDuration: Double = 0.25

  // Internal staging state
  @State private var isExpanded: Bool
  @State private var showContent: Bool
  @State private var animationTask: Task<Void, Never>? = nil

  init(status: RecordingStatus) {
    self.status = status
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
              Color(.sRGB, white: 0.15, opacity: 0.9),
              Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )

      // Content
      if showContent {
        HStack(spacing: 0) {
          // Icon container - fixed width to match right padding
          Circle()
            .fill(statusColor.opacity(0.0))
            .frame(width: 28, height: 28)
            .overlay(
              Image(systemName: statusIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(statusColor)
                .symbolEffect(.pulse, isActive: status == .recording || status == .processing)
            )
            .frame(width: 36, alignment: .leading) // Match the right padding width
            .padding(.leading, 4)

          // Text content - centered in remaining space
          Text(displayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Constants.Colors.muted2)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)

          // Right spacer - matches left icon area width
          Spacer()
            .frame(width: 36) // Match the left icon area width
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }
    }
    .frame(
      width: isExpanded ? Constants.Overlay.activeWidth : Constants.Overlay.idleWidth,
      height: isExpanded ? Constants.Overlay.activeHeight : Constants.Overlay.idleHeight,
    )
    .preferredColorScheme(.dark)
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
      return
    }

    animationTask = Task { @MainActor in
      if newStatus == .idle {
        // Fade out content first, then shrink container
        if showContent {
          withAnimation(contentAnimation) {
            showContent = false
          }
          // Wait for fade-out to complete
          try? await Task.sleep(nanoseconds: UInt64(contentDuration * 1_000_000_000))
        }
        withAnimation(containerAnimation) {
          isExpanded = false
        }
      } else {
        // Expand container first, then fade in content
        withAnimation(containerAnimation) {
          isExpanded = true
        }
        // Wait for expand to complete
        try? await Task.sleep(nanoseconds: UInt64(containerDuration * 1_000_000_000))
        if !showContent {
          withAnimation(contentAnimation) {
            showContent = true
          }
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
      return "record.circle.fill"
    case .processing:
      return "sparkles"
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
    if status == .recording && !appState.currentInputDevice.isEmpty {
      return appState.currentInputDevice
    } else {
      return statusText
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
            OverlayView(status: status)
              .environmentObject(AppState())
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
          OverlayRecordingPreview(deviceName: "Built-in Microphone")
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
          OverlayRecordingPreview(deviceName: "Blue Yeti USB Microphone")
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
          OverlayRecordingPreview(deviceName: "Sony WH-1000XM4 Wireless Headphones")
          Spacer()
        }
      }
      .frame(width: Constants.Overlay.activeWidth, height: Constants.Overlay.previewFrameHeight)
      .background(Color.black.opacity(0.1))
      .border(Color.gray.opacity(0.3))
    }
  }
  .padding(40)
  .background(.secondary)
}



// Helper used only in previews now that state is injected
private struct OverlayRecordingPreview: View {
  let deviceName: String

  var body: some View {
    let appState = AppState()
    appState.currentInputDevice = deviceName
    return OverlayView(status: .recording)
      .environmentObject(appState)
  }
}

#Preview("Animated") {
  struct AnimatedPreview: View {
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

  return AnimatedPreview()
}
