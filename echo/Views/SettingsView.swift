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
  case providers = "Providers"
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
    case .providers: return "key"
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
  /// Fixed, so the sidebar can't be dragged wider than its items need.
  static let sidebarWidth: CGFloat = 180

  @ObservedObject private var settings = SettingsManager.shared
  @EnvironmentObject private var updateManager: UpdateManager
  @State private var selectedSection: SettingsSection? = .profiles

  var body: some View {
    ZStack {
      // Window configurator to enable full height content
      FullHeightWindowConfigurator()
        .frame(width: 0, height: 0)

      HSplitView {
        // Sidebar. Plain buttons rather than a List, whose blank area takes clicks itself and
        // would stop the window being dragged from there.
        VStack(alignment: .leading, spacing: 2) {
          ForEach(SettingsSection.allCases) { section in
            SettingsSidebarRow(
              section: section,
              isSelected: (selectedSection ?? .profiles) == section,
              select: { selectedSection = section }
            )
          }
          Spacer(minLength: 0)
        }
        // The sidebar already starts below the title bar, so the first item sits just under the
        // window's close, minimise and zoom buttons.
        .padding(.top, 4)
        .padding(.horizontal, 10)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: Self.sidebarWidth)

        // Detail
        ScrollView {
          destinationView(for: selectedSection ?? .profiles)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 450, maxWidth: .infinity)
        .ignoresSafeArea(.all)
        .background(Color.clear)
      }
    }
    // Drag from any empty space to move the window.
    .modifier(DragsWindow())
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
    case .providers:
      ProvidersSettingsView()
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

private struct SettingsSidebarRow: View {
  let section: SettingsSection
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        // A fixed column keeps the titles lined up whatever the icon's width.
        Image(systemName: section.icon)
          .frame(width: 18)
        Text(section.rawValue)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 7)
      .padding(.horizontal, 8)
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .background(
        RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor : Color.clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
    .settingsPanePadding()
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

/// API keys for the speech-to-text and clean-up providers. Models are chosen per profile.
struct ProvidersSettingsView: View {
  @ObservedObject private var settings = SettingsManager.shared

  var body: some View {
    Form {
      Section {
        Text("Each profile picks its own speech-to-text and clean-up models from these providers.")
          .foregroundColor(.secondary)
      }

      Section {
        SecureField("API Key", text: $settings.openRouterAPIKey)
          .textFieldStyle(.roundedBorder)
        Link("Get a key at openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
          .font(.caption)
      } header: {
        Text("OpenRouter")
      } footer: {
        Text("Includes all the latest models, but adds a little latency to each request.")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Section {
        SecureField("API Key", text: $settings.apiKey)
          .textFieldStyle(.roundedBorder)
        Link("Get a key at console.groq.com/keys", destination: URL(string: "https://console.groq.com/keys")!)
          .font(.caption)
      } header: {
        Text("Groq")
      } footer: {
        Text(
          "Runs Whisper and GPT OSS 20B directly on Groq. Calling them directly cuts about 100–300 ms from each transcription."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }
    }
    .formStyle(.grouped)
    .settingsPanePadding()
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
                profile.isEnabled ? "Start with this profile; stop recording" : "Enable this profile to use its shortcut"
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
          "Press a profile shortcut to select it and start dictation. Press a profile shortcut again to stop. Fn tap and hold controls remain available. Previous and next profile shortcuts apply while recording."
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
          "While notes mode is on, each recording is added to a note with a screenshot instead of being pasted. Drag to draw on the screen at any time while recording, without holding Shift. The drawing is included in that recording's screenshot, which is cropped to the area you marked. Stop recording to click normally in other apps."
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
    .settingsPanePadding()
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

        guard validateShortcut(normalized, against:
          profilesService.profiles.map(\.shortcut) + [
            settings.previousProfileShortcut, settings.nextProfileShortcut
          ]) else { return }

        settings.notesModeShortcut = normalized ?? ""
        GlobalShortcutMonitor.shared.loadNotesModeShortcut(normalized)
        errorMessage = nil
      }
    )
  }

  private func updateShortcut(_ shortcut: String?, for profileID: String) {
    let normalized = normalizedShortcut(shortcut)

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

    guard validateShortcut(normalized, against:
      profilesService.profiles.map(\.shortcut) + [settings.notesModeShortcut, otherShortcut]
    ) else { return }

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

  private func validateShortcut(_ shortcut: String?, against others: [String?]) -> Bool {
    do {
      try ShortcutUtils.validate(shortcut, against: others)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
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
    .settingsPanePadding()
    .onAppear {
      permissionManager.checkAllPermissions()
    }
  }
}

extension View {
  /// The inset every settings pane shares, so the grouped form cards line up from pane to pane.
  func settingsPanePadding() -> some View {
    padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 0))
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
            Text("Sound effects synthesized with")
              .font(.caption)
              .foregroundColor(.secondary)

            Link("Cuelume", destination: CuelumeCredit.repositoryURL)
              .font(.caption)
              .foregroundColor(.accentColor)

            Text("Copyright © 2026 Daniel Belyi. MIT License.")
              .font(.caption)
              .foregroundColor(.secondary)
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
    .settingsPanePadding()
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
        Section {
          Picker("Style:", selection: $settings.soundTheme) {
            ForEach(CuelumeTheme.allCases) { theme in
              Text(theme.label).tag(theme.rawValue)
            }
          }

          SoundRow(
            title: "Recording start:",
            pickerLabel: "Recording Start Sound",
            selection: $settings.recordingStartSound,
            play: soundManager.testRecordingStartSound
          )

          SoundRow(
            title: "Transcription complete:",
            pickerLabel: "Transcription Complete Sound",
            selection: $settings.transcriptionCompleteSound,
            play: soundManager.testTranscriptionCompleteSound
          )
        } header: {
          Text("Sounds")
        } footer: {
          CuelumeCredit()
        }
      }
    }
    .formStyle(.grouped)
    .settingsPanePadding()
  }
}

private struct SoundRow: View {
  let title: String
  let pickerLabel: String
  @Binding var selection: String
  let play: () -> Void

  var body: some View {
    HStack {
      Text(title)

      Spacer()

      SoundPickerMenu(selection: $selection, label: pickerLabel)

      if selection != SoundOption.none.id {
        Button(action: play) {
          Image(systemName: "play.circle")
            .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .help("Play sound")
      }
    }
  }
}

/// Credit for the sounds, which come from a Swift port of Cuelume (MIT License).
struct CuelumeCredit: View {
  static let repositoryURL = URL(string: "https://github.com/danielwh2/cuelume")!

  var body: some View {
    HStack(spacing: 4) {
      Text("Sounds synthesized with")
        .foregroundColor(.secondary)
      Link("Cuelume", destination: Self.repositoryURL)
        .foregroundColor(.accentColor)
      Text("by Daniel Belyi, MIT License.")
        .foregroundColor(.secondary)
    }
    .font(.caption)
  }
}

struct SoundPickerMenu: View {
  @Binding var selection: String
  let label: String
  @StateObject private var soundManager = SoundManager.shared
  @State private var hoverTask: Task<Void, Never>?

  private var selectedOption: SoundOption? {
    SoundOption.option(id: selection)
  }

  var body: some View {
    Menu {
      ForEach(SoundOption.allOptions) { sound in
        Button(sound.label) {
          selection = sound.id
        }
        .onHover { isHovering in
          hoverTask?.cancel()

          if isHovering, let cue = sound.cue {
            // Preview after a short pause, so sweeping past options stays quiet
            hoverTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000)
              if !Task.isCancelled {
                soundManager.preview(cue)
              }
            }
          }
        }
      }
    } label: {
      HStack {
        Text(selectedOption?.label ?? SoundOption.none.label)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color(NSColor.controlBackgroundColor))
      .cornerRadius(6)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel(label)
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
