import SwiftUI

/// Wrapper view that observes AppState and provides reactive updates to the overlay panel.
/// In notes mode the panel stays up between recordings, and the pill shows the mode.
///
/// The live mic level is deliberately not read here: `OverlayWaveformView` picks up
/// `AudioLevelMeter` from the environment on its own, so only the bars re-render on each
/// metering tick rather than this whole view.
struct OverlayContentView: View {
  static let width: CGFloat = 300
  static let height: CGFloat = 72

  @EnvironmentObject var appState: AppState
  @EnvironmentObject var profilesService: ProfilesService
  @EnvironmentObject var notesMode: NotesModeService

  var body: some View {
    VStack {
      Spacer()
      OverlayView(
        status: appState.status,
        showingProfileName: appState.showingProfileName,
        showingProfileIconName: appState.showingProfileIconName,
        currentInputDevice: appState.currentInputDevice,
        activeProfileIconName: profilesService.activeProfile?.iconName,
        errorCategory: appState.errorCategory,
        errorRecoveryHint: appState.errorRecoveryHint,
        notesMode: notesModeContent
      )
      .help(appState.status == .error ? appState.errorMessage : "")
    }
    .padding(.bottom, 12)
    .frame(width: Self.width, height: Self.height)
    .background(Color.clear)
  }

  private var notesModeContent: OverlayNotesMode? {
    guard notesMode.isActive else { return nil }
    return OverlayNotesMode(
      screenshotsAvailable: notesMode.screenshotsAvailable,
      stop: { notesMode.stop() }
    )
  }
}
