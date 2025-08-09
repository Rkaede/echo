import AVFoundation
import SwiftUI

struct OnboardingView: View {
  @ObservedObject private var settings = SettingsManager.shared
  @State private var currentStep = 0
  @State private var apiKeyInput = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      if currentStep == 0 {
        WelcomeStepView(
          apiKeyInput: $apiKeyInput,
          onNext: {
            // Ensure API key is loaded before setting
            settings.ensureAPIKeyLoaded()
            settings.apiKey = apiKeyInput
            currentStep = 1
          }
        )
      } else if currentStep == 1 {
        PermissionsStepView(
          onNext: {
            currentStep = 2
          },
          onBack: {
            currentStep = 0
          }
        )
      } else if currentStep == 2 {
        TestingStepView(
          onComplete: {
            // Mark onboarding as completed
            settings.hasCompletedOnboarding = true
            dismiss()
          },
          onBack: {
            currentStep = 1
          }
        )
      }
    }
    .background(Color(NSColor.windowBackgroundColor))
    .onAppear {
      // Pre-fill API key input if user already has a saved key
      settings.ensureAPIKeyLoaded()
      apiKeyInput = settings.apiKey
    }
  }
}

struct WelcomeStepView: View {
  @Binding var apiKeyInput: String
  let onNext: () -> Void

  private var isValidAPIKey: Bool {
    apiKeyInput.count == Constants.API.groqAPIKeyLength
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header section
      HStack(spacing: 20) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [.blue.opacity(0.1), .blue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 60, height: 60)

          Image(systemName: "waveform")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.blue)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Welcome to Echo")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(.primary)

          Text("Transform your voice into text instantly")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Spacer()
      }
      .padding(.vertical, 20)
      .padding(.horizontal, 50)
      .background(Color.blue.opacity(0.03))
      .overlay(
        Rectangle()
          .frame(height: 1)
          .foregroundColor(.blue.opacity(0.1)),
        alignment: .bottom
      )

      // Content section
      GeometryReader { geometry in
        VStack(spacing: 0) {
          Spacer(minLength: 20)

          // API Key input section
          VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Image(systemName: "key.fill")
                  .foregroundColor(.blue)
                  .font(.system(size: 16))
                Text("Groq API Key")
                  .font(.headline)
                  .fontWeight(.semibold)
              }
              VStack(alignment: .leading, spacing: 8) {
                Text("We use Groq's lightning-fast API for speech-to-text transcription.")
                  .font(.caption)
                  .foregroundColor(.secondary)

                HStack(spacing: 4) {
                  Text("Get your free API key at")
                    .font(.caption)
                    .foregroundColor(.secondary)
                  Link("console.groq.com", destination: URL(string: "https://console.groq.com")!)
                    .font(.caption)
                    .foregroundColor(.blue)
                }

              }

              VStack(spacing: 8) {
                SecureField("Enter your \(Constants.API.groqAPIKeyLength)-character API key", text: $apiKeyInput)
                  .textFieldStyle(.plain)
                  .font(.system(.body, design: .monospaced))
                  .padding(14)
                  .background(Color(NSColor.textBackgroundColor))
                  .overlay(
                    RoundedRectangle(cornerRadius: 10)
                      .stroke(
                        isValidAPIKey ? .green : .gray.opacity(0.3),
                        lineWidth: isValidAPIKey ? 2 : 1)
                  )
                  .cornerRadius(10)

                if isValidAPIKey {
                  HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundColor(.green)
                      .font(.system(size: 14))
                    Text("Valid API key")
                      .font(.caption)
                      .foregroundColor(.green)
                    Spacer()
                  }
                }
              }

              VStack(alignment: .leading, spacing: 8) {

                HStack(spacing: 4) {
                  Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                  Text(
                    "We'll save your API key safely in the system keychain - just enter your password when prompted."
                  )
                  .font(.caption)
                  .foregroundColor(.secondary)
                }
              }
            }
            .frame(maxWidth: 400)
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(16)
          }

          Spacer(minLength: 20)

          // Button section
          HStack {
            Spacer()

            Button(action: onNext) {
              HStack(spacing: 8) {
                Text("Continue")
                  .fontWeight(.semibold)
                Image(systemName: "arrow.right")
                  .font(.system(size: 14, weight: .semibold))
              }
              .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValidAPIKey)
          }
          .padding(.bottom, 30)
        }
        .padding(.horizontal, 50)
      }
    }
  }
}

struct PermissionsStepView: View {
  let onNext: () -> Void
  let onBack: () -> Void
  @State private var microphonePermission: PermissionStatus = .unknown
  @State private var accessibilityPermission: PermissionStatus = .unknown

  enum PermissionStatus {
    case unknown
    case granted
    case denied
  }
  
  private func permissionStatusToAppStatus(_ status: PermissionStatus) -> AppPermissionStatus {
    switch status {
    case .unknown: return .unknown
    case .granted: return .granted
    case .denied: return .denied
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header section
      HStack(spacing: 20) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [.orange.opacity(0.1), .orange.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 60, height: 60)

          Image(systemName: "shield.checkered")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.orange)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("Permissions needed")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(.primary)

          Text("To transcribe your audio, we need a few permissions.")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Spacer()
      }
      .padding(.vertical, 20)
      .padding(.horizontal, 50)
      .background(Color.orange.opacity(0.03))
      .overlay(
        Rectangle()
          .frame(height: 1)
          .foregroundColor(.orange.opacity(0.1)),
        alignment: .bottom
      )

      GeometryReader { geometry in
        VStack(spacing: 0) {
          Spacer(minLength: 20)

          // Permissions section
          VStack(spacing: 16) {
            PermissionStatusView(
              title: "Microphone",
              description: "We need to borrow your mic to work our speech-to-text magic ✨",
              icon: "mic.fill",
              iconColor: .blue,
              status: permissionStatusToAppStatus(microphonePermission),
              onEnable: requestMicrophonePermission
            )

            PermissionStatusView(
              title: "Accessibility",
              description: "Allow us to place transcribed text straight into your apps.",
              icon: "accessibility",
              iconColor: .green,
              status: permissionStatusToAppStatus(accessibilityPermission),
              onEnable: requestAccessibilityPermission
            )
          }
          .frame(maxWidth: 480)

          Spacer(minLength: 20)

          // Button section
          HStack {
            Spacer()

            HStack(spacing: 12) {
              Button(action: onBack) {
                HStack(spacing: 8) {
                  Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                  Text("Back")
                    .fontWeight(.semibold)
                }
                .frame(minWidth: 80)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)

              Button(action: onNext) {
                HStack(spacing: 8) {
                  Text("Continue")
                    .fontWeight(.semibold)
                  Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                }
                .frame(minWidth: 120)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .disabled(microphonePermission != .granted || accessibilityPermission != .granted)
            }
          }
          .padding(.bottom, 30)
        }
        .padding(.horizontal, 50)
      }
    }
    .onAppear {
      checkPermissions()
    }
  }

  private func checkPermissions() {
    checkMicrophonePermission()
    checkAccessibilityPermission()
  }

  private func checkMicrophonePermission() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      microphonePermission = .granted
    case .denied, .restricted:
      microphonePermission = .denied
    case .notDetermined:
      microphonePermission = .unknown
    @unknown default:
      microphonePermission = .unknown
    }
  }

  private func checkAccessibilityPermission() {
    accessibilityPermission = AXIsProcessTrusted() ? .granted : .denied
  }

  private func requestMicrophonePermission() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        microphonePermission = granted ? .granted : .denied
      }
    }
  }

  private func requestAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

    // Start a timer to check periodically since there's no callback
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
      let isTrusted = AXIsProcessTrusted()
      if isTrusted {
        DispatchQueue.main.async {
          accessibilityPermission = .granted
        }
        timer.invalidate()
      }
    }
  }
}

struct TestingStepView: View {
  let onComplete: () -> Void
  let onBack: () -> Void
  @State private var testText = ""

  var body: some View {
    VStack(spacing: 0) {
      // Header section
      HStack(spacing: 20) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [.green.opacity(0.1), .green.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 60, height: 60)

          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(.green)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("You're all set")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(.primary)

          Text("Echo is ready to transcribe your voice instantly")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }

        Spacer()
      }
      .padding(.vertical, 20)
      .padding(.horizontal, 50)
      .background(Color.green.opacity(0.03))
      .overlay(
        Rectangle()
          .frame(height: 1)
          .foregroundColor(.green.opacity(0.1)),
        alignment: .bottom
      )

      GeometryReader { geometry in
        VStack(spacing: 0) {
          Spacer(minLength: 20)

          // Test section
          VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
          
                Text("Test it out 👇")
                  .font(.headline)
                  .fontWeight(.semibold)
                Spacer()
              }
    
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
              ZStack(alignment: .topLeading) {
                TextEditor(text: $testText)
                  .font(.body)
                  .padding(16)
                  .background(Color(NSColor.textBackgroundColor))
                  .cornerRadius(12)
                  .scrollIndicators(.never)
                  .overlay(
                    RoundedRectangle(cornerRadius: 12)
                      .stroke(
                        testText.isEmpty ? .gray.opacity(0.3) : .blue.opacity(0.5), lineWidth: 1)
                  )
                  .frame(height: 100)

                if testText.isEmpty {
                  Text("Click in here and press the shortcut to start recording")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
                }
              }

              HStack(spacing: 12) {
                HStack(spacing: 8) {
                  ZStack {
                    RoundedRectangle(cornerRadius: 6)
                      .fill(.blue.opacity(0.1))
                      .frame(width: 32, height: 24)

                    Text("⌥")
                      .font(.system(size: 14, weight: .semibold))
                      .foregroundColor(.blue)
                  }

                  Text("+")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                  ZStack {
                    RoundedRectangle(cornerRadius: 6)
                      .fill(.blue.opacity(0.1))
                      .frame(width: 40, height: 24)

                    Text("Space")
                      .font(.system(size: 11, weight: .semibold))
                      .foregroundColor(.blue)
                  }

                  Text("to start/stop recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
              }
              .padding(.horizontal, 4)
            }
          }
          .frame(maxWidth: 420)
          .padding(20)
          .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
          .cornerRadius(16)

          Spacer(minLength: 20)

          // Button section
          HStack {
            Spacer()

            HStack(spacing: 12) {
              Button(action: onBack) {
                HStack(spacing: 8) {
                  Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                  Text("Back")
                    .fontWeight(.semibold)
                }
                .frame(minWidth: 80)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)

              Button(action: onComplete) {
                HStack(spacing: 8) {
                  Text("Finish")
                    .fontWeight(.semibold)
                }
                .frame(minWidth: 80)
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
            }
          }
          .padding(.bottom, 30)
        }
        .padding(.horizontal, 50)
      }
    }
  }
}


#Preview("Welcome Step") {
  WelcomeStepView(
    apiKeyInput: .constant(""),
    onNext: {}
  )
  .frame(width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight)
}

#Preview("Permissions Step") {
  PermissionsStepView(
    onNext: {},
    onBack: {}
  )
  .frame(width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight)
}

#Preview("Testing Step") {
  TestingStepView(
    onComplete: {},
    onBack: {}
  )
  .frame(width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight)
}

#Preview("Full Onboarding") {
  OnboardingView()
    .frame(width: Constants.Windows.onboardingWidth, height: Constants.Windows.onboardingHeight)
}
