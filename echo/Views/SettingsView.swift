import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
  case general = "General"
  case transcription = "Transcription"
  case permissions = "Permissions"
  case about = "About"
  
  var id: String { rawValue }
  
  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .transcription: return "waveform"
    case .permissions: return "lock.shield"
    case .about: return "info.circle"
    }
  }
}

struct SettingsView: View {
  @ObservedObject private var settings = SettingsManager.shared
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var selectedSection: SettingsSection? = .general

  var body: some View {
    HStack(spacing: 0) {
      // Custom Sidebar
      VStack(alignment: .leading, spacing: 0) {
        // Sidebar List
        List(SettingsSection.allCases, selection: $selectedSection) { section in
          Button(action: {
            selectedSection = section
          }) {
            HStack {
              Label(section.rawValue, systemImage: section.icon)
              Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
          .listRowBackground(
            RoundedRectangle(cornerRadius: 4)
              .fill(selectedSection == section ? Color.accentColor.opacity(0.15) : Color.clear)
              .padding(.horizontal, 8)
          )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, 28) // Compensate for toolbar area
      }
      .frame(width: 180)
      .background(Color(NSColor.windowBackgroundColor))
      .gesture(WindowDragGesture())
      
      // Separator
      Divider()
      
      // Detail View
      VStack(alignment: .leading, spacing: 0) {
        
        // Detail Content
        destinationView(for: selectedSection ?? .general)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(minWidth: 450, maxWidth: .infinity)
      .background(Color(NSColor.clear))
      .gesture(WindowDragGesture())
    }
    .ignoresSafeArea()
    .frame(minWidth: Constants.Windows.settingsWidth, minHeight: Constants.Windows.settingsHeight)
    .environmentObject(updateManager)
  }
  
  @ViewBuilder
  private func destinationView(for section: SettingsSection) -> some View {
    switch section {
    case .general:
      GeneralSettingsView()
    case .transcription:
      TranscriptionSettingsView()
    case .permissions:
      PermissionsSettingsView()
    case .about:
      AboutView()
    }
  }
}

struct GeneralSettingsView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  @Environment(\.openWindow) private var openWindow
  @ObservedObject private var settings = SettingsManager.shared

  var body: some View {
    Form {
      Section("Startup") {
        LaunchAtLogin.Toggle()
      }
      
      Section("Clipboard") {
        Toggle("Restore clipboard after pasting", isOn: $settings.restoreClipboard)
        
        Text("When enabled, the clipboard will be restored to its previous content after transcribed text is pasted.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      
      Section("Updates") {
        Toggle("Check for updates automatically", 
               isOn: $updateManager.automaticChecksEnabled)
        
        HStack {
          Button("Check for Updates...") {
            updateManager.checkForUpdates()
          }
          .disabled(!updateManager.canCheckForUpdates)
          
          Spacer()
          
          if let lastCheckDate = updateManager.lastUpdateCheckDate {
            Text("Last checked: \(lastCheckDate, formatter: relativeDateFormatter)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        
        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Onboarding") {
        VStack(alignment: .leading, spacing: 8) {
          Button("Revisit onboarding") {
            // Mark onboarding as incomplete and present the window
            SettingsManager.shared.hasCompletedOnboarding = false
            openWindow(id: "onboarding")
          }
          Text("Run the initial setup and guidance again. Your settings and API key will be preserved.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 24, leading: 20, bottom: 20, trailing: 20))
  }
}

struct PermissionsSettingsView: View {
  @StateObject private var permissionManager = PermissionManager.shared

  var body: some View {
    Form {
      Section {
        VStack(spacing: 16) {
          PermissionStatusView(
            title: "Microphone",
            description: "Required for recording audio",
            icon: "mic.fill",
            iconColor: .blue,
            status: permissionManager.microphoneStatus,
            onEnable: {
              permissionManager.requestMicrophonePermission()
            },
            onOpenSettings: {
              permissionManager.openMicrophoneSettings()
            },
            enableButtonLabel: "Grant",
            enabledLabel: "Granted"
          )
          
          PermissionStatusView(
            title: "Accessibility",
            description: "Required for automatic text pasting",
            icon: "accessibility",
            iconColor: .green,
            status: permissionManager.accessibilityStatus,
            onEnable: {
              permissionManager.requestAccessibilityPermission()
            },
            onOpenSettings: {
              permissionManager.openAccessibilitySettings()
            },
            enableButtonLabel: "Grant",
            enabledLabel: "Granted"
          )
        }
        .padding(.vertical, 8)
      } header: {
        VStack(alignment: .leading, spacing: 8) {
          Text("Required Permissions")
            .font(.headline)
            .fontWeight(.semibold)
          Text("Echo needs these permissions to function properly. You can grant them here or open System Settings to manage them manually.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
      }
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
    .onAppear {
      permissionManager.checkAllPermissions()
    }
  }
}

struct TranscriptionSettingsView: View {
  @ObservedObject private var settings = SettingsManager.shared

  let modelOptions = [
    ModelOption(
      value: "whisper-large-v3",
      label: "Whisper Large V3",
      supportedLanguages: "Multilingual",
      description:
        "Provides state-of-the-art performance with high accuracy for multilingual transcription and translation tasks.",
      costPerHour: 0.111,
      translationSupport: true,
      realTimeSpeedFactor: 189,
      wordErrorRate: "10.3%"
    ),
    ModelOption(
      value: "whisper-large-v3-turbo",
      label: "Whisper Large V3 Turbo",
      supportedLanguages: "Multilingual",
      description:
        "A fine-tuned version of a pruned Whisper Large V3 designed for fast, multilingual transcription tasks.",
      costPerHour: 0.04,
      translationSupport: false,
      realTimeSpeedFactor: 216,
      wordErrorRate: "12%"
    ),
    ModelOption(
      value: "distil-whisper-large-v3-en",
      label: "Distil-Whisper English",
      supportedLanguages: "English-only",
      description:
        "A distilled, or compressed, version of OpenAI's Whisper model, designed to provide faster, lower cost English speech recognition while maintaining comparable accuracy.",
      costPerHour: 0.02,
      translationSupport: false,
      realTimeSpeedFactor: 250,
      wordErrorRate: "13%"
    ),
  ]

  var selectedModel: ModelOption? {
    modelOptions.first { $0.value == settings.selectedModel }
  }

  var body: some View {
    Form {
      Section("API Configuration") {
        SecureField("Groq API Key", text: $settings.apiKey)
          .textFieldStyle(.roundedBorder)

        Text("Enter your Groq API key for speech-to-text transcription")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Model Selection") {
        Picker("Model", selection: $settings.selectedModel) {
          ForEach(modelOptions, id: \.value) { model in
            Text(model.label).tag(model.value)
          }
        }
        .pickerStyle(.menu)

        if let model = selectedModel {
          VStack(alignment: .leading, spacing: 8) {
            Text(model.description)
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(.bottom, 4)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8) {
              GridRow {
                Text("Languages:")
                  .font(.caption)
                  .fontWeight(.semibold)
                  .gridColumnAlignment(.trailing)
                Text(model.supportedLanguages)
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .gridColumnAlignment(.leading)
              }

              GridRow {
                Text("Cost per Hour:")
                  .font(.caption)
                  .fontWeight(.semibold)
                  .gridColumnAlignment(.trailing)
                Text("$\(String(format: "%.3f", model.costPerHour))")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .gridColumnAlignment(.leading)
              }

              GridRow {
                Text("Speed Factor:")
                  .font(.caption)
                  .fontWeight(.semibold)
                  .gridColumnAlignment(.trailing)
                Text("\(model.realTimeSpeedFactor)x real-time")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .gridColumnAlignment(.leading)
              }

              GridRow {
                Text("Word Error Rate:")
                  .font(.caption)
                  .fontWeight(.semibold)
                  .gridColumnAlignment(.trailing)
                Text(model.wordErrorRate)
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .gridColumnAlignment(.leading)
              }
            }
          }
          .padding(.top, 4)
        }
      }
      
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
    .onAppear {
      // Load API key when settings view appears
      settings.ensureAPIKeyLoaded()
    }
  }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
  let formatter = RelativeDateTimeFormatter()
  formatter.unitsStyle = .abbreviated
  return formatter
}()

struct ModelOption {
  let value: String
  let label: String
  let supportedLanguages: String
  let description: String
  let costPerHour: Double
  let translationSupport: Bool
  let realTimeSpeedFactor: Int
  let wordErrorRate: String
}

struct AboutView: View {
  @EnvironmentObject private var updateManager: UpdateManager
  
  var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
  }
  
  var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }
  
  var body: some View {
    VStack(spacing: 20) {
      // App Icon and Name
      VStack(spacing: 12) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 128, height: 128)
        
        Text("Echo")
          .font(.largeTitle)
          .fontWeight(.semibold)
      }
      .padding(.top, 20)
      
      // Version Information
      VStack(spacing: 8) {
        Text("Version \(appVersion)")
          .font(.system(.body, design: .monospaced))
        
        if let lastCheckDate = updateManager.lastUpdateCheckDate {
          Text("Last checked for updates: \(lastCheckDate, formatter: relativeDateFormatter)")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      
      // Links
      VStack(spacing: 4) {
        Link("GitHub Repository", destination: URL(string: "https://github.com/Rkaede/echo")!)
          .font(.body)
        
        Link("Report an Issue", destination: URL(string: "https://github.com/Rkaede/echo/issues")!)
          .font(.body)
      }
      
     
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}


#Preview {
  SettingsView()
    .frame(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
    .environmentObject(UpdateManager())
}
