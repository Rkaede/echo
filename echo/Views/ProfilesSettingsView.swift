import Foundation
import SwiftUI

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

struct ProfilesSettingsView: View {
  // Use ObservedObject for a shared singleton
  @ObservedObject private var service = ProfilesService.shared
  @State private var errorMessage: String?
  // Draft editor state
  @State private var draft: Profile? = nil
  @State private var isNewDraft: Bool = false
  @State private var originalProfile: Profile? = nil
  @State private var isHoveringBackButton: Bool = false
  @State private var isResettingProfiles: Bool = false
  @State private var isShowingResetConfirmation: Bool = false
  private let backButtonSide: CGFloat = 28

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let binding = bindingForDraft() {
        // Detail view (draft editor)
        HStack(spacing: 8) {
          Button(action: { cancelEditing() }) {
            Image(systemName: "chevron.left")
              .foregroundColor(isHoveringBackButton ? .primary : .secondary)
              .padding(6)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(isHoveringBackButton ? Color.gray.opacity(0.15) : Color.clear)
              )
          }
          .frame(width: backButtonSide, height: backButtonSide)
          .buttonStyle(.plain)
          .onHover { hovering in
            isHoveringBackButton = hovering
          }

          Text(isNewDraft ? "New Profile" : binding.wrappedValue.title)
            .font(.headline)
            .padding(.leading, 4)
          Spacer()

          Button("Save") { saveDraft() }
            .buttonStyle(SettingsButton())
            .settingsButtonStyle(.primary)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 12)
        .overlay(
          Rectangle()
            .frame(height: 1)
            .foregroundColor(.secondary.opacity(0.1)),
          alignment: .bottom
        )

        ProfileEditor(profile: binding)

        if let error = errorMessage {
          Text(error).font(.caption).foregroundColor(.red)
        }
      } else {
        // List-only view (use Form to avoid nested ScrollView issues)
        VStack(spacing: 0) {
          HStack(spacing: 8) {
            Text("Profiles")
              .font(.headline)
            Spacer()
            Button(action: { startNewProfile() }) {
              Label("New", systemImage: "plus")
            }
            .buttonStyle(SettingsButton())
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .overlay(
            Rectangle()
              .frame(height: 1)
              .foregroundColor(.secondary.opacity(0.1)),
            alignment: .bottom
          )

          Form {
            Section {
              HStack(spacing: 8) {
                Image(systemName: "info.circle")
                  .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                  Text("The push-to-talk shortcut (Fn key) always uses the default profile.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                  Text("Switch between profiles during recording using the left/right arrow keys.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
              }
              .padding(.vertical, 4)
            }
            
            Section("Profiles") {
              ForEach(service.profiles, id: \.id) { p in
                Button(action: { startEditing(profile: p) }) {
                  HStack(spacing: 10) {
                    ProfileListIconView(iconName: p.iconName, colorToken: nil)
                      .opacity(p.isEnabled ? 1 : 0.4)

                    HStack(spacing: 6) {
                      Text(p.title)
                        .fontWeight(.medium)
                        .foregroundColor(p.isEnabled ? .primary : .secondary)

                      if p.isDefault {
                        Text("Default")
                          .font(.caption2)
                          .fontWeight(.semibold)
                          .foregroundColor(.accentColor)
                          .padding(.horizontal, 6)
                          .padding(.vertical, 2)
                          .background(Color.accentColor.opacity(0.15))
                          .clipShape(Capsule())
                      }

                      if !p.isEnabled {
                        Text("Disabled")
                          .font(.caption2)
                          .fontWeight(.semibold)
                          .foregroundColor(.secondary)
                          .padding(.horizontal, 6)
                          .padding(.vertical, 2)
                          .background(Color.secondary.opacity(0.12))
                          .clipShape(Capsule())
                      }

                      if p.postProcessingEnabled {
                        HStack(spacing: 2) {
                          Image(systemName: "wand.and.sparkles")
                          Text("AI")
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                      }
                    }
                    Spacer()
                    if let sc = p.shortcut, !sc.isEmpty {
                      let formattedShortcut = ShortcutRecorderView.displayText(for: sc)
                      Text(formattedShortcut).font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        .opacity(p.isEnabled ? 1 : 0.5)
                    }
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                  Button("Set Default") { Task { try? await service.setDefault(p.id) } }
                    .disabled(!p.isEnabled)
                  Button("Duplicate") { duplicateProfile(p) }
                  if p.isEnabled {
                    Button("Disable") { setEnabled(p, false) }
                  } else {
                    Button("Enable") { setEnabled(p, true) }
                  }
                  Divider()
                  Button("Delete", role: .destructive) { deleteProfile(p) }
                }
              }
            }

            Section {
              VStack(spacing: 12) {
                HStack(spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text("Reset to Defaults")
                      .font(.headline)
                      .foregroundColor(.primary)

                    Text("Replace all profiles with defaults.")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }

                  Spacer()

                  Button(action: {
                    isShowingResetConfirmation = true
                  }) {
                    if isResettingProfiles {
                      HStack(spacing: 6) {
                        ProgressView()
                          .scaleEffect(0.8)
                        Text("Resetting...")
                      }
                    } else {
                      Text("Reset")
                    }
                  }
                  .buttonStyle(SettingsButton())
                  .disabled(service.profiles.isEmpty || isResettingProfiles)
                }
              }
              .padding(.vertical, 8)
            }

            if let error = errorMessage {
              Section { Text(error).font(.caption).foregroundColor(.red) }
            }
          }
          .formStyle(.grouped)
        }
        .confirmationDialog(
          "Reset Profiles?",
          isPresented: $isShowingResetConfirmation,
          titleVisibility: .visible
        ) {
          Button("Reset Profiles", role: .destructive) {
            performProfileReset()
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "This will replace your current profiles with the defaults. App assignments and custom settings will be lost."
          )
        }
      }

      Spacer()
    }
    .padding(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))
    .task {
      // Ensure we have the latest data when this view appears
      await service.load()
    }
  }

  private func startNewProfile() {
    let now = Date()
    draft = Profile(
      id: UUID().uuidString,
      title: "New Profile",
      isDefault: service.profiles.isEmpty,
      isEnabled: true,
      shortcut: nil,
      transcriptionModel: SettingsManager.shared.selectedModel,
      postProcessingEnabled: false,
      postProcessingPrompt: "{{TRANSCRIPTION}}",
      postProcessingModel: PostProcessingModelOption.defaultOptionValue,
      iconName: nil,
      iconColor: nil,
      createdAt: now,
      updatedAt: now
    )
    originalProfile = nil
    isNewDraft = true
  }

  private func startEditing(profile: Profile) {
    draft = profile
    draft?.iconColor = nil
    originalProfile = profile
    isNewDraft = false
  }

  private func cancelEditing() {
    draft = nil
    originalProfile = nil
    isNewDraft = false
    errorMessage = nil
  }

  private func saveDraft() {
    guard var current = draft else { return }
    current.iconColor = nil
    draft = current
    Task {
      do {
        if isNewDraft {
          try await service.create(
            title: current.title,
            transcriptionModel: current.transcriptionModel,
            postEnabled: current.postProcessingEnabled,
            prompt: current.postProcessingPrompt,
            postProcessingModel: current.postProcessingModel,
            shortcut: current.shortcut,
            isDefault: current.isDefault,
            isEnabled: current.isEnabled,
            iconName: current.iconName,
            iconColor: current.iconColor
          )
        } else {
          try await service.update(profile: current)
        }
        cancelEditing()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func bindingForDraft() -> Binding<Profile>? {
    guard draft != nil else { return nil }
    return Binding(
      get: { draft! },
      set: { v in
        draft = v
        draft?.updatedAt = Date()
      }
    )
  }

  private func duplicateProfile(_ p: Profile) {
    Task {
      do {
        try await service.create(
          title: p.title + " Copy",
          transcriptionModel: p.transcriptionModel,
          postEnabled: p.postProcessingEnabled,
          prompt: p.postProcessingPrompt,
          postProcessingModel: p.postProcessingModel,
          shortcut: nil,
          isDefault: false,
          isEnabled: p.isEnabled,
          iconName: p.iconName,
          iconColor: nil
        )
      } catch { errorMessage = error.localizedDescription }
    }
  }

  private func setEnabled(_ profile: Profile, _ enabled: Bool) {
    Task {
      do {
        var updated = profile
        updated.isEnabled = enabled
        if !enabled { updated.isDefault = false }
        updated.updatedAt = Date()
        try await service.update(profile: updated)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func deleteProfile(_ p: Profile) {
    Task {
      do { try await service.remove(id: p.id) } catch { errorMessage = error.localizedDescription }
    }
  }

  private func performProfileReset() {
    guard !isResettingProfiles else { return }
    isShowingResetConfirmation = false
    isResettingProfiles = true
    Task { @MainActor in
      do {
        try await service.resetToDefaults()
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
      isResettingProfiles = false
    }
  }
}

private struct ProfileEditor: View {
  @Binding var profile: Profile
  @FocusState private var isPromptFocused: Bool

  private var selectedModel: ModelOption? {
    TranscriptionData.modelOptions.first { $0.value == profile.transcriptionModel }
  }

  private let postProcessingOptions = PostProcessingModelOption.allOptions

  private var selectedPostProcessingOption: PostProcessingModelOption? {
    postProcessingOptions.first { $0.value == profile.postProcessingModel }
      ?? PostProcessingModelOption.recommendedOption
  }

  var body: some View {
    Form {
      Section("General") {
        TextField(
          "Title",
          text: Binding(
            get: { profile.title },
            set: { v in profile.title = v }
          ))

        Toggle("Enabled", isOn: $profile.isEnabled)

        Toggle("Default", isOn: $profile.isDefault)
          .disabled(!profile.isEnabled)
        HStack {
          Text("Hotkey")
          Spacer(minLength: 12)
          ShortcutRecorderView(
            shortcut: Binding(
              get: { profile.shortcut },
              set: { newValue in profile.shortcut = newValue }
            )
          )
          .frame(maxWidth: 150, alignment: .trailing)
        }
      }

      Section("Transcription") {
        Picker("Model", selection: $profile.transcriptionModel) {
          ForEach(TranscriptionData.modelOptions, id: \.value) { model in
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

      Section("Appearance") {
        IconPickerView(
          iconName: Binding(
            get: { profile.iconName },
            set: { newValue in profile.iconName = newValue }
          ),
          colorToken: nil
        )
      }

      Section {
        HStack {
          Text("Post-Processing")
            .font(.headline)
          if profile.postProcessingEnabled {
            HStack(spacing: 2) {
              Image(systemName: "wand.and.sparkles")
              Text("AI")
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15))
            .clipShape(Capsule())
          }
          Spacer()
        }
        .padding(.bottom, 4)

        Toggle("Enable", isOn: $profile.postProcessingEnabled)

        VStack(alignment: .leading, spacing: 8) {
          Picker("Model", selection: $profile.postProcessingModel) {
            ForEach(postProcessingOptions, id: \.value) { option in
              Text(pickerLabel(for: option))
                .tag(option.value)
                .disabled(option.disabled)
            }
          }
          .pickerStyle(.menu)
        }

        VStack(alignment: .leading, spacing: 12) {

          TextEditor(
            text: Binding(
              get: { profile.postProcessingPrompt },
              set: { v in profile.postProcessingPrompt = v }
            )
          )
          .focused($isPromptFocused)
          .textEditorStyle(.plain)
          .font(.body)
          .frame(minHeight: 80)
          .scrollIndicators(.never)
        }
        .padding(10)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .allowsHitTesting(profile.postProcessingEnabled)
        .opacity(profile.postProcessingEnabled ? 1 : 0.55)
        .onChange(of: profile.postProcessingEnabled) { _, enabled in
          if !enabled {
            isPromptFocused = false
          } else {
            let trimmed = profile.postProcessingModel.trimmingCharacters(
              in: .whitespacesAndNewlines)
            if trimmed.isEmpty || !postProcessingOptions.contains(where: { $0.value == trimmed }) {
              profile.postProcessingModel = PostProcessingModelOption.defaultOptionValue
            }
          }
        }

        Text("Use {{TRANSCRIPTION}} for the transcription text.")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, 2)
    }
    .formStyle(.grouped)
    .onAppear {
      profile.iconColor = nil
      let trimmedModel = profile.postProcessingModel.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedModel.isEmpty
        || !postProcessingOptions.contains(where: { $0.value == trimmedModel })
      {
        profile.postProcessingModel = PostProcessingModelOption.defaultOptionValue
      }
    }
    .onChange(of: profile.isEnabled) { _, newValue in
      if !newValue {
        profile.isDefault = false
      }
    }
  }

  private func pickerLabel(for option: PostProcessingModelOption) -> String {
    if let badge = option.badge, !badge.isEmpty {
      return "\(option.label) (\(badge))"
    }
    return option.label
  }

}
#Preview {
  ProfilesSettingsView()
    .frame(width: Constants.Windows.settingsWidth, height: Constants.Windows.settingsHeight)
}

#if DEBUG
  import AppKit
  import SwiftUI

  private struct PreviewWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      DispatchQueue.main.async { [weak view] in
        guard
          let window = view?.window,
          ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        else { return }

        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.setContentSize(
          NSSize(
            width: Constants.Windows.settingsWidth,
            height: Constants.Windows.settingsHeight
          ))
      }
      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
  }
#endif
