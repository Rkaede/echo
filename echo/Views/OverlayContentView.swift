import SwiftUI

/// Wrapper view that observes AppState and provides reactive updates to the overlay panel.
///
/// The live mic level is deliberately not read here: `OverlayWaveformView` picks up
/// `AudioLevelMeter` from the environment on its own, so only the bars re-render on each
/// metering tick rather than this whole view.
struct OverlayContentView: View {
  @EnvironmentObject var appState: AppState
  @EnvironmentObject var profilesService: ProfilesService

  var body: some View {
    VStack {
      Spacer()
      OverlayView(
        status: appState.status,
        showingProfileName: appState.showingProfileName,
        showingProfileIconName: appState.showingProfileIconName,
        currentInputDevice: appState.currentInputDevice,
        activeProfileIconName: profilesService.activeProfile?.iconName,
        errorCategory: appState.errorCategory
      )
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
    .frame(width: 300, height: 72)
    .background(Color.clear)
  }
}
