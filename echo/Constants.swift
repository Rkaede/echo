import Foundation
import SwiftUI

struct Constants {
  struct Overlay {
    static let idleWidth: CGFloat = 40
    static let idleHeight: CGFloat = 10
    static let activeWidth: CGFloat = 220
    static let activeHeight: CGFloat = 32
    static let previewFrameHeight: CGFloat = 54
  }

  struct Colors {
    static let muted = Color.gray.opacity(0.8)
    static let muted2 = Color(hue: 0.12, saturation: 0.04, brightness: 0.9)
    // overlay colors
    static let red = Color(red: 1.0, green: 0.0, blue: 0.29, opacity: 1.0)
    static let green = Color(red: 0.463, green: 1.0, blue: 0.114, opacity: 1.0)
  }

  struct Windows {
    static let onboardingWidth: CGFloat = 600
    static let onboardingHeight: CGFloat = 440
    static let settingsWidth: CGFloat = 800
    static let settingsHeight: CGFloat = 600
  }

  struct API {
    static let groqAPIKeyLength = 56
    static let whisperModel = "whisper-large-v3-turbo"
  }

}
