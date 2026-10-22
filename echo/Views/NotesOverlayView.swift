import SwiftUI

/// Notes bar shown above the recording pill while notes mode is active: the entry
/// count, the last entry added (or the drawing hint while recording), and a button to
/// stop the mode. Styled to match the pill, which keeps its light look in dark mode.
struct NotesOverlayView: View {
  let status: RecordingStatus

  @EnvironmentObject var notesMode: NotesModeService

  private static let mutedText = Constants.Colors.text.opacity(0.55)

  var body: some View {
    if notesMode.isActive {
      HStack(spacing: 6) {
        Image(systemName: "note.text")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.accentColor)

        Text("\(notesMode.entryCount)")
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
          .foregroundStyle(Constants.Colors.text)

        message
          .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: { notesMode.stop() }) {
          Image(systemName: "stop.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(Color.red.opacity(0.85))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop notes mode")
      }
      .padding(.leading, 12)
      .padding(.trailing, 8)
      .frame(width: 280, height: 30)
      .background(
        Capsule()
          .fill(Constants.Colors.bg)
          .stroke(Color.gray.opacity(0.3), lineWidth: 1)
          .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
      )
    }
  }

  @ViewBuilder
  private var message: some View {
    if notesMode.isDrawing {
      line("Drag to draw on screen", icon: "pencil.tip", color: .accentColor)
    } else if status == .recording && !notesMode.screenshotsAvailable {
      screenshotsOffWarning
    } else if let last = notesMode.lastTranscription, !last.isEmpty {
      line(
        last,
        icon: notesMode.lastEntryHasScreenshot ? "photo" : nil,
        color: Constants.Colors.text,
        iconColor: Self.mutedText
      )
    } else if !notesMode.screenshotsAvailable {
      screenshotsOffWarning
    } else {
      line("Press Fn to add an entry", icon: nil, color: Self.mutedText)
    }
  }

  private var screenshotsOffWarning: some View {
    line("Screenshots off — allow Screen Recording", icon: "exclamationmark.triangle.fill", color: .orange)
  }

  /// One line of text, with an optional icon in front of it.
  private func line(_ text: String, icon: String?, color: Color, iconColor: Color? = nil) -> some View {
    HStack(spacing: 5) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 10))
          .foregroundStyle(iconColor ?? color)
      }
      Text(text)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }
}
