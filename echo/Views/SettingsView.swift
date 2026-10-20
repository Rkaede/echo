import AVFoundation
import AppKit
import SwiftUI

// Helper to configure NSWindow for full height content
struct FullHeightWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        // Configure window to allow content in title bar area
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
      }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    // Check again in case window wasn't ready on first call
    if let window = nsView.window {
      window.styleMask.insert(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.toolbar = nil
    }
  }
}

enum SettingsSection: String, CaseIterable, Identifiable {
  case general = "General"
  case shortcuts = "Shortcuts"
  case sound = "Sound"
  case profiles = "Profiles"
  case history = "History"
  case permissions = "Permissions"
  case about = "About"

  var id: String { rawValue }

  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .shortcuts: return "keyboard"
    case .sound: return "speaker.2"
    case .profiles: return "person.crop.square"
    case .history: return "clock.arrow.circlepath"
    case .permissions: return "lock.shield"
    case .about: return "info.circle"
    }
  }
}

struct SettingsView: View {
  @ObservedObject private var settings = SettingsManager.shared
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var selectedSection: SettingsSection? = .profiles

  var body: some View {
    ZStack {
      // Window configurator to enable full height content
      FullHeightWindowConfigurator()
        .frame(width: 0, height: 0)

      HSplitView {
        // Sidebar
        List(selection: $selectedSection) {
          ForEach(SettingsSection.allCases) { section in
            Label(section.rawValue, systemImage: section.icon)
              .tag(section)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 4)
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 180, idealWidth: 180, maxWidth: 240)
        .gesture(WindowDragGesture())

        // Detail
        ScrollView {
          destinationView(for: selectedSection ?? .profiles)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 450, maxWidth: .infinity)
        .ignoresSafeArea(.all)
        .background(Color.clear)
        .gesture(WindowDragGesture())
      }
    }
    .frame(
      minWidth: Constants.Windows.settingsWidth, minHeight: Constants.Windows.settingsHeight,
      maxHeight: .infinity
    )
    .ignoresSafeArea(.all)
    .environmentObject(updateManager)
  }

  @ViewBuilder
  private func destinationView(for section: SettingsSection) -> some View {
    switch section {
    case .general:
      GeneralSettingsView()
    case .shortcuts:
      ShortcutsSettingsView()
    case .sound:
      SoundSettingsView()
    case .profiles:
      ProfilesSettingsView()
    case .history:
      HistorySettingsView()
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
  @StateObject private var audioInputDeviceManager = AudioInputDeviceManager.shared

  var body: some View {
    Form {
      Section("Startup") {
        LaunchAtLogin.Toggle()
      }

      Section("API Configuration") {
        SecureField("Groq API Key", text: $settings.apiKey)
          .textFieldStyle(.roundedBorder)

        Text("Enter your Groq API key for speech-to-text transcription")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Microphone") {
        Picker(
          "Preferred microphone",
          selection: Binding(
            get: { settings.selectedInputDeviceUID },
            set: { uid in
              settings.selectedInputDeviceUID = uid
              settings.selectedInputDeviceName =
                audioInputDeviceManager.devices.first(where: { $0.uid == uid })?.name ?? ""
              resetDuplicateFallbackIfNeeded()
            }
          )
        ) {
          Text("System Default").tag("")

          if shouldShowUnavailablePreferredDevice {
            Text("\(unavailablePreferredDeviceName) (Unavailable)")
              .tag(settings.selectedInputDeviceUID)
          }

          ForEach(audioInputDeviceManager.devices) { device in
            Text(device.name).tag(device.uid)
          }
        }
        .onAppear {
          audioInputDeviceManager.refreshDevices()
          resetDuplicateFallbackIfNeeded()
        }

        Picker(
          "Fallback microphone",
          selection: Binding(
            get: { settings.fallbackInputDeviceUID },
            set: { uid in
              settings.fallbackInputDeviceUID = uid
              settings.fallbackInputDeviceName =
                audioInputDeviceManager.devices.first(where: { $0.uid == uid })?.name ?? ""
            }
          )
        ) {
          Text("System Default").tag("")

          if shouldShowUnavailableFallbackDevice {
            Text("\(unavailableFallbackDeviceName) (Unavailable)")
              .tag(settings.fallbackInputDeviceUID)
          }

          ForEach(
            audioInputDeviceManager.devices.filter {
              $0.uid != settings.selectedInputDeviceUID
            }
          ) { device in
            Text(device.name).tag(device.uid)
          }
        }
        .disabled(settings.selectedInputDeviceUID.isEmpty)

        Text(
          "Echo uses the preferred microphone when it is available, then the fallback microphone, then the macOS system default."
        )
        .font(.caption)
        .foregroundColor(.secondary)

        Picker(
          "Engine idle behavior",
          selection: Binding(
            get: { settings.audioEngineIdlePolicy },
            set: { settings.audioEngineIdlePolicy = $0 }
          )
        ) {
          Text("Stop when idle").tag(AudioEngineIdlePolicy.stopWhenIdle)
          Text("Idle timeout").tag(AudioEngineIdlePolicy.idleTimeout)
          Text("Always on").tag(AudioEngineIdlePolicy.alwaysOn)
        }

        if settings.audioEngineIdlePolicy == .idleTimeout {
          let presets = SettingsManager.audioEngineIdleTimeoutPresets
          let currentIndex = SettingsManager.idleTimeoutPresetIndex(
            closestTo: settings.audioEngineIdleTimeoutSeconds
          )

          VStack(alignment: .leading, spacing: 4) {
            Text(
              "Idle timeout: \(SettingsManager.formattedIdleTimeout(seconds: presets[currentIndex]))"
            )

            Slider(
              value: Binding(
                get: { Double(currentIndex) },
                set: { settings.audioEngineIdleTimeoutSeconds = presets[Int($0.rounded())] }
              ),
              in: 0...Double(presets.count - 1),
              step: 1
            ) {
              EmptyView()
            } minimumValueLabel: {
              Text("30 sec").font(.caption).foregroundColor(.secondary)
            } maximumValueLabel: {
              Text("30 min").font(.caption).foregroundColor(.secondary)
            }
          }
        }

        Text(
          "Controls how long Echo keeps the audio engine running after activity. Stopping clears the mic indicator but may increase start latency and Bluetooth mode switches."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Clipboard") {
        Toggle("Restore clipboard after pasting", isOn: $settings.restoreClipboard)

        Text(
          "When enabled, the clipboard will be restored to its previous content after transcribed text is pasted."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Updates") {
        Toggle(
          "Check for updates automatically",
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

        Text("Version \(Bundle.main.appVersion)")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Troubleshooting") {
        HStack {
          Button("Open Logs Folder") {
            LoggingService.shared.openLogsFolder()
          }
          .buttonStyle(.bordered)

          Spacer()
        }

        Text("Contains diagnostic logs for troubleshooting issues.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 0))
  }

  private var shouldShowUnavailablePreferredDevice: Bool {
    !settings.selectedInputDeviceUID.isEmpty
      && !audioInputDeviceManager.devices.contains(where: { $0.uid == settings.selectedInputDeviceUID })
  }

  private var unavailablePreferredDeviceName: String {
    settings.selectedInputDeviceName.isEmpty
      ? "Preferred microphone"
      : settings.selectedInputDeviceName
  }

  private var shouldShowUnavailableFallbackDevice: Bool {
    !settings.fallbackInputDeviceUID.isEmpty
      && settings.fallbackInputDeviceUID != settings.selectedInputDeviceUID
      && !audioInputDeviceManager.devices.contains(where: {
        $0.uid == settings.fallbackInputDeviceUID
      })
  }

  private var unavailableFallbackDeviceName: String {
    settings.fallbackInputDeviceName.isEmpty
      ? "Fallback microphone"
      : settings.fallbackInputDeviceName
  }

  private func resetDuplicateFallbackIfNeeded() {
    guard !settings.selectedInputDeviceUID.isEmpty,
      settings.selectedInputDeviceUID == settings.fallbackInputDeviceUID
    else { return }

    settings.fallbackInputDeviceUID = ""
    settings.fallbackInputDeviceName = ""
  }
}

struct ShortcutsSettingsView: View {
  @ObservedObject private var settings = SettingsManager.shared
  @ObservedObject private var profilesService = ProfilesService.shared
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section("Profiles") {
        ForEach(profilesService.profiles) { profile in
          LabeledContent {
            ShortcutRecorderView(shortcut: shortcutBinding(for: profile))
              .disabled(true)
              .frame(width: 220)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(profile.title)

                if profile.isDefault {
                  Text("Default")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                }

                if !profile.isEnabled {
                  Text("Disabled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
              }

              Text(
                "Saved shortcut (inactive)"
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
        }

        LabeledContent("Previous profile") {
          ShortcutRecorderView(shortcut: previousProfileShortcutBinding)
            .frame(width: 220)
        }

        LabeledContent("Next profile") {
          ShortcutRecorderView(shortcut: nextProfileShortcutBinding)
            .frame(width: 220)
        }

        Text(
          "Recording uses Fn with the active profile. Previous and next profile shortcuts apply while recording. Legacy profile recording shortcuts remain saved but are inactive."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Notes Mode") {
        LabeledContent("Toggle notes mode") {
          ShortcutRecorderView(shortcut: notesModeShortcutBinding)
            .frame(width: 220)
        }

        Text(
          "While notes mode is on, each recording is added to a note with a screenshot instead of being pasted. Hold Shift while recording and drag to draw on the screen: the drawing is included in that recording's screenshot, which is cropped to the area you marked."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }

      Section("Fixed Shortcuts") {
        LabeledContent("Record (tap or hold)") {
          shortcutLabel("fn")
        }

        LabeledContent("Cancel recording") {
          shortcutLabel("esc")
        }

        Text("Tap Fn and release within 300 ms to keep recording; press Fn again to stop. Hold Fn for 300 ms or longer and release to stop. These shortcuts are fixed.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if let errorMessage {
        Section {
          Text(errorMessage)
            .font(.caption)
            .foregroundColor(.red)
        }
      }
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 0))
    .task {
      await profilesService.load()
    }
  }

  private func shortcutBinding(for profile: Profile) -> Binding<String?> {
    Binding(
      get: {
        profilesService.profiles.first(where: { $0.id == profile.id })?.shortcut
          ?? profile.shortcut
      },
      set: { newValue in
        updateShortcut(newValue, for: profile.id)
      }
    )
  }

  private var notesModeShortcutBinding: Binding<String?> {
    Binding(
      get: {
        settings.notesModeShortcut.isEmpty ? nil : settings.notesModeShortcut
      },
      set: { newValue in
        let normalized = normalizedShortcut(newValue)

        if let normalized, ShortcutUtils.reserved.contains(normalized) {
          errorMessage = ProfileValidationError.reservedShortcut.localizedDescription
          return
        }

        if let normalized,
          normalized == normalizedShortcut(settings.previousProfileShortcut)
            || normalized == normalizedShortcut(settings.nextProfileShortcut)
        {
          errorMessage = ProfileValidationError.duplicateShortcut.localizedDescription
          return
        }

        settings.notesModeShortcut = normalized ?? ""
        GlobalShortcutMonitor.shared.loadNotesModeShortcut(normalized)
        errorMessage = nil
      }
    )
  }

  private func updateShortcut(_ shortcut: String?, for profileID: String) {
    let normalized = normalizedShortcut(shortcut)

    if let normalized,
      normalized == normalizedShortcut(settings.notesModeShortcut)
        || normalized == normalizedShortcut(settings.previousProfileShortcut)
        || normalized == normalizedShortcut(settings.nextProfileShortcut)
    {
      errorMessage = ProfileValidationError.duplicateShortcut.localizedDescription
      return
    }

    Task { @MainActor in
      guard var profile = profilesService.profiles.first(where: { $0.id == profileID }) else {
        return
      }

      profile.shortcut = normalized
      profile.updatedAt = Date()

      do {
        try await profilesService.update(profile: profile)
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private var previousProfileShortcutBinding: Binding<String?> {
    Binding(
      get: {
        normalizedShortcut(settings.previousProfileShortcut)
      },
      set: { newValue in
        updateProfileNavigationShortcut(newValue, isPrevious: true)
      }
    )
  }

  private var nextProfileShortcutBinding: Binding<String?> {
    Binding(
      get: {
        normalizedShortcut(settings.nextProfileShortcut)
      },
      set: { newValue in
        updateProfileNavigationShortcut(newValue, isPrevious: false)
      }
    )
  }

  private func updateProfileNavigationShortcut(_ shortcut: String?, isPrevious: Bool) {
    let normalized = normalizedShortcut(shortcut)
    let otherShortcut =
      normalizedShortcut(
        isPrevious ? settings.nextProfileShortcut : settings.previousProfileShortcut
      )

    if let normalized,
      ShortcutUtils.reserved.contains(normalized)
        || normalized == normalizedShortcut(settings.notesModeShortcut)
        || normalized == otherShortcut
    {
      errorMessage =
        ShortcutUtils.reserved.contains(normalized)
        ? ProfileValidationError.reservedShortcut.localizedDescription
        : ProfileValidationError.duplicateShortcut.localizedDescription
      return
    }

    if isPrevious {
      settings.previousProfileShortcut = normalized ?? ""
    } else {
      settings.nextProfileShortcut = normalized ?? ""
    }

    GlobalShortcutMonitor.shared.loadProfileNavigationShortcuts(
      previous: normalizedShortcut(settings.previousProfileShortcut),
      next: normalizedShortcut(settings.nextProfileShortcut)
    )
    errorMessage = nil
  }

  private func normalizedShortcut(_ shortcut: String?) -> String? {
    guard let shortcut, !shortcut.isEmpty else { return nil }
    return ShortcutUtils.normalize(shortcut)
  }

  private func shortcutLabel(_ text: String) -> some View {
    Text(text)
      .font(.body.monospaced())
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Color.secondary.opacity(0.1))
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
          Text(
            "Echo needs these permissions to function properly. You can grant them here or open System Settings to manage them manually."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
      }
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 0))
    .onAppear {
      permissionManager.checkAllPermissions()
    }
  }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
  let formatter = RelativeDateTimeFormatter()
  formatter.unitsStyle = .abbreviated
  return formatter
}()

struct AboutView: View {
  @EnvironmentObject private var updateManager: UpdateManager

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
        Text("Version \(Bundle.main.appVersion)")
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

      // Attribution
      VStack(spacing: 8) {
        Divider()

        VStack(spacing: 4) {
          Text("Acknowledgments")
            .font(.headline)
            .fontWeight(.semibold)

          VStack(spacing: 2) {
            Text("Sound effects obtained from")
              .font(.caption)
              .foregroundColor(.secondary)

            Link("Zapsplat", destination: URL(string: "https://www.zapsplat.com")!)
              .font(.caption)
              .foregroundColor(.accentColor)
          }
        }
      }
      .padding(.top, 8)

    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

struct HistorySettingsView: View {
  @StateObject private var historyManager = HistoryManager.shared
  @ObservedObject private var settings = SettingsManager.shared
  @StateObject private var audioStorage = AudioStorageManager.shared
  @Environment(\.openWindow) private var openWindow
  @State private var showingDeleteAllAlert = false
  @State private var showingDeleteAllAudioAlert = false
  @State private var showingFolderPicker = false

  var body: some View {
    Form {
      Section("History") {
        Toggle("Enable History", isOn: $settings.enableHistory)

        Text("When enabled, transcriptions will be automatically saved to your local history.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section("Audio Files") {
        Toggle("Save audio with transcriptions", isOn: $settings.saveAudioWithHistory)
          .disabled(!settings.enableHistory)

        if settings.enableHistory {
          Text(
            "When enabled, audio recordings will be saved alongside transcriptions for playback later."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        } else {
          Text("Enable History first to save audio recordings.")
            .font(.caption)
            .foregroundColor(.orange)
        }

        if settings.saveAudioWithHistory && settings.enableHistory {
          VStack(alignment: .leading, spacing: 12) {
            // Storage location
            VStack(alignment: .leading, spacing: 6) {
              Text("Storage Location:")
                .font(.subheadline)
                .fontWeight(.medium)

              HStack {
                Text(currentStoragePath)
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)

                Spacer()

                Button("Change...") {
                  showingFolderPicker = true
                }
                .buttonStyle(.bordered)
              }
            }

            // Storage usage
            HStack {

              Spacer()

              Button("Reveal in Finder") {
                audioStorage.openStorageDirectory()
              }
              .buttonStyle(.bordered)
            }
          }
          .padding(.top, 8)
        }
      }

      Section("Data Management") {

        // Audio Files Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Audio Recordings")
            .font(.subheadline)
            .fontWeight(.medium)

          Text(
            "\(audioStorage.getAudioFileCount()) audio files (\(audioStorage.formattedStorageUsage))"
          )
          .font(.caption)
          .foregroundColor(.secondary)

          HStack(spacing: 12) {
            Button("Delete Audio Only", role: .destructive) {
              showingDeleteAllAudioAlert = true
            }
            .buttonStyle(.bordered)
            .disabled(audioStorage.getAudioFileCount() == 0)

            Spacer()
          }

          Text(
            "Removes saved audio files but keeps transcription text history."
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }

        // Complete Data Section
        VStack(alignment: .leading, spacing: 12) {
          Text("Complete History")
            .font(.subheadline)
            .fontWeight(.medium)

          HStack(spacing: 12) {
            Button("Delete Everything", role: .destructive) {
              showingDeleteAllAlert = true
            }
            .buttonStyle(.bordered)
            .disabled(historyManager.totalCount == 0)

            Spacer()
          }

          Text("Removes all transcription history and all audio files.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 0))
    .fileImporter(
      isPresented: $showingFolderPicker,
      allowedContentTypes: [.folder],
      onCompletion: { result in
        switch result {
        case .success(let url):
          if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }

            // Use the new setCustomStorageDirectory method which handles security-scoped bookmarks
            if let errorMessage = audioStorage.setCustomStorageDirectory(url) {
              print("Invalid storage path selected: \(errorMessage)")
              // Could show an error alert here
            }
          }
        case .failure(let error):
          print("Failed to select storage directory: \(error)")
        }
      }
    )
    .alert("Clear All Data", isPresented: $showingDeleteAllAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Clear All", role: .destructive) {
        historyManager.deleteAllTranscriptions()
        if settings.saveAudioWithHistory {
          audioStorage.deleteAllAudioFiles()
        }
      }
    } message: {
      Text(
        "This will permanently remove all transcription history\(settings.saveAudioWithHistory ? " and their audio recordings" : ""). This action cannot be undone."
      )
    }
    .alert("Clear Audio Recordings", isPresented: $showingDeleteAllAudioAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Clear", role: .destructive) {
        audioStorage.deleteAllAudioFiles()
      }
    } message: {
      Text(
        "This will permanently remove all saved audio files but keep the transcription text history. This action cannot be undone."
      )
    }
  }

  private var currentStoragePath: String {
    if settings.audioStoragePath.isEmpty {
      return audioStorage.defaultStorageDirectory.path
    }
    return settings.audioStoragePath
  }
}

struct SoundSettingsView: View {
  @ObservedObject private var settings = SettingsManager.shared
  @StateObject private var soundManager = SoundManager.shared

  var body: some View {
    Form {
      Section("Sound Options") {
        Toggle("Enable sound effects", isOn: $settings.soundEnabled)

        Text("Play sounds when recording starts and transcription completes")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if settings.soundEnabled {
        Section("Sounds") {
          HStack {
            Text("Recording start:")

            Spacer()

            SoundPickerMenu(
              selection: $settings.recordingStartSound,
              label: "Recording Start Sound"
            )

            if settings.recordingStartSound != "none" {
              Button(action: {
                soundManager.testRecordingStartSound()
              }) {
                Image(systemName: "play.circle")
                  .font(.system(size: 16))
              }
              .buttonStyle(.plain)
            }
          }

          HStack {
            Text("Transcription complete:")

            Spacer()

            SoundPickerMenu(
              selection: $settings.transcriptionCompleteSound,
              label: "Transcription Complete Sound"
            )

            if settings.transcriptionCompleteSound != "none" {
              Button(action: {
                soundManager.testTranscriptionCompleteSound()
              }) {
                Image(systemName: "play.circle")
                  .font(.system(size: 16))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding(EdgeInsets(top: 24, leading: 20, bottom: 20, trailing: 0))
  }
}

struct SoundPickerMenu: View {
  @Binding var selection: String
  let label: String
  @State private var isExpanded = false
  @StateObject private var soundManager = SoundManager.shared
  @State private var previewPlayer: AVAudioPlayer?
  @State private var hoverTask: Task<Void, Never>?

  private var selectedOption: SoundOption? {
    SoundOption.allOptions.first { $0.id == selection }
  }

  var body: some View {
    Menu {
      ForEach(SoundOption.allOptions, id: \.id) { sound in
        Button(action: {
          selection = sound.id
        }) {
          HStack {
            Text(sound.label)
            // if sound.id == selection {
            //   Spacer()
            //   Image(systemName: "checkmark")
            // }
          }
        }
        .onHover { isHovering in
          // Cancel any existing hover task
          hoverTask?.cancel()

          if isHovering && sound.id != "none" {
            // Start a new task with 500ms delay
            hoverTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

              // Check if task was cancelled (user moved mouse away)
              if !Task.isCancelled {
                await MainActor.run {
                  playPreviewSound(for: sound.id)
                }
              }
            }
          }
        }
      }
    } label: {
      HStack {
        Text(selectedOption?.label ?? "None")
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(6)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  private func playPreviewSound(for soundId: String) {
    // Find the sound option
    guard let soundOption = SoundOption.allOptions.first(where: { $0.id == soundId }),
      !soundOption.fileName.isEmpty
    else {
      return
    }

    // Extract filename without extension
    let fileNameWithoutExtension = (soundOption.fileName as NSString).deletingPathExtension

    // Load the sound file from the main Resources folder
    guard
      let soundURL = Bundle.main.url(forResource: fileNameWithoutExtension, withExtension: "mp3")
    else {
      return
    }

    // Play the sound on main thread to maintain reference
    do {
      previewPlayer = try AVAudioPlayer(contentsOf: soundURL)
      previewPlayer?.volume = 0.5  // Lower volume for preview
      previewPlayer?.play()
    } catch {
      // Silently fail if sound can't be played
    }
  }
}

#if DEBUG
  import AppKit

  private final class _PreviewWindowAccessorView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      onWindowChanged?(window)
    }
  }

  private struct PreviewWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> _PreviewWindowAccessorView {
      let view = _PreviewWindowAccessorView()
      view.onWindowChanged = { window in
        guard
          let window,
          ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        else { return }

        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.remove(.titled)
        window.styleMask.insert(.borderless)
        window.isMovableByWindowBackground = true
        window.level = .floating
      }
      return view
    }

    func updateNSView(_ nsView: _PreviewWindowAccessorView, context: Context) {}
  }
#endif

#Preview {
  SettingsView()
    .frame(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
    .ignoresSafeArea()
    .environmentObject(UpdateManager(startImmediately: false))
    #if DEBUG
      .background(PreviewWindowConfigurator())
    #endif
}
