import SwiftUI

/// Wrapper view that observes AppState and provides reactive updates to the overlay panel
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
        currentInputLevel: Float(appState.currentInputLevel),
        waveformSamples: appState.waveformSamples,
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
