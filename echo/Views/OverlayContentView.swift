import SwiftUI

/// Wrapper view that observes AppState and provides reactive updates to the overlay panel.
/// In notes mode the notes bar sits above the status pill.
///
/// The live mic level is deliberately not read here: `OverlayWaveformView` picks up
/// `AudioLevelMeter` from the environment on its own, so only the bars re-render on each
/// metering tick rather than this whole view.
struct OverlayContentView: View {
  static let width: CGFloat = 300
  static let height: CGFloat = 108

  @EnvironmentObject var appState: AppState
  @EnvironmentObject var profilesService: ProfilesService

  var body: some View {
    let isIdle = appState.status == .idle

    VStack(spacing: 6) {
      Spacer(minLength: 0)
      NotesOverlayView(status: appState.status)
      OverlayView(
        status: appState.status,
        showingProfileName: appState.showingProfileName,
        showingProfileIconName: appState.showingProfileIconName,
        currentInputDevice: appState.currentInputDevice,
        activeProfileIconName: profilesService.activeProfile?.iconName,
        errorCategory: appState.errorCategory,
        errorRecoveryHint: appState.errorRecoveryHint
      )
      // Notes mode keeps the panel up between recordings, so the pill hides itself.
      // Appearing stays instant; only the fade out is animated.
      .opacity(isIdle ? 0 : 1)
      .animation(isIdle ? .easeOut(duration: 0.3) : nil, value: isIdle)
      .help(appState.status == .error ? appState.errorMessage : "")
    }
    .padding(.bottom, 12)
    .frame(width: Self.width, height: Self.height)
    .background(Color.clear)
  }
}
