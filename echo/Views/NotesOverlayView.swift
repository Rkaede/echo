import SwiftUI

/// Compact floating panel shown while notes mode is active: displays the last
/// transcription added to the note and a button to stop the mode.
struct NotesOverlayView: View {
  @EnvironmentObject var notesMode: NotesModeService

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: "note.text")
          .foregroundStyle(Color.accentColor)
        Text("Notes Mode")
          .font(.system(size: 13, weight: .semibold))

        Spacer()

        Text("\(notesMode.entryCount)")
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.secondary.opacity(0.15)))

        Button(action: { notesMode.stop() }) {
          HStack(spacing: 4) {
            Image(systemName: "stop.fill")
              .font(.system(size: 9, weight: .bold))
            Text("Stop")
              .font(.system(size: 12, weight: .medium))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Capsule().fill(Color.red.opacity(0.85)))
        }
        .buttonStyle(.plain)
      }

      Text(lastTranscriptionText)
        .font(.system(size: 12))
        .foregroundStyle(notesMode.lastTranscription == nil ? .secondary : .primary)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)

      if !notesMode.screenshotsAvailable {
        Label(
          "Screenshots off — grant Screen Recording in System Settings",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.system(size: 10))
        .foregroundStyle(.orange)
      }
    }
    .padding(12)
    .frame(width: 340, height: 116, alignment: .top)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
  }

  private var lastTranscriptionText: String {
    if let last = notesMode.lastTranscription, !last.isEmpty {
      return last
    }
    return "Record to add the first entry…"
  }
}
