import AppKit
import SwiftUI

// Onboarding "Set D": a short conversation with Echo. Setup asks only for an OpenRouter key;
// English is the default language, so there is no language step.

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable {
  case welcome, apiKey, preset, microphone, accessibility, tryIt, done

  static let numberedStepCount = 5

  /// Position among the numbered steps shown as dots, or nil for welcome and done.
  var dotIndex: Int? {
    switch self {
    case .apiKey: return 0
    case .preset: return 1
    case .microphone: return 2
    case .accessibility: return 3
    case .tryIt: return 4
    case .welcome, .done: return nil
    }
  }

  var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

private enum Palette {
  static let background = Color(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF7 / 255)
  static let ink = Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
  static let ash = Color(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255)
  /// Echo's red: step dots, ticks, bullets and the selected preset.
  static let line = Color(red: 0xE1 / 255, green: 0x53 / 255, blue: 0x5F / 255)
  /// Deeper red for buttons so their white label passes contrast.
  static let button = Color(red: 0xC9 / 255, green: 0x3A / 255, blue: 0x47 / 255)
  static let buttonHover = Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0x3C / 255)
  static let dotUpcoming = Color(red: 0xEF / 255, green: 0xC9 / 255, blue: 0xCD / 255)
}

// MARK: - Onboarding

struct OnboardingView: View {
  @ObservedObject private var settings = SettingsManager.shared
  @ObservedObject private var permissions = PermissionManager.shared
  @State private var step: OnboardingStep
  @State private var openRouterKeyInput = ""
  @State private var preset = ModelPreset.recommended
  @State private var openAtLogin = true
  @Environment(\.dismiss) private var dismiss

  /// The footer's height plus its bottom margin.
  private static let footerInset: CGFloat = 68

  init(initialStep: OnboardingStep = .welcome) {
    _step = State(initialValue: initialStep)
  }

  var body: some View {
    ZStack(alignment: .top) {
      Palette.background

      Group {
        switch step {
        case .welcome:
          WelcomeStep(onStart: { go(to: .apiKey) })
        case .apiKey:
          APIKeyStep(
            keyInput: $openRouterKeyInput,
            canSkip: settings.hasAPIKey,
            onContinue: saveKeyAndContinue,
            onSkip: { go(to: .microphone) }
          )
        case .preset:
          PresetStep(selection: $preset)
        case .microphone:
          MicrophoneStep()
        case .accessibility:
          AccessibilityStep()
        case .tryIt:
          TryItStep()
        case .done:
          DoneStep(openAtLogin: $openAtLogin, onDone: finish)
        }
      }
      .id(step)
      // Centred in the window. The same inset top and bottom keeps it clear of the footer
      // without pulling the centre up.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.vertical, Self.footerInset)
      .padding(.horizontal, 80)

      if let dotIndex = step.dotIndex {
        OnboardingFooter(
          dotIndex: dotIndex,
          onBack: previousStep.map { previous in { go(to: previous) } },
          skip: footerSkip,
          next: footerContinue
        )
      }
    }
    // Dragging anywhere moves the window. Buttons, fields and the checkbox handle their own
    // clicks first, so they keep working; the first drag on an inactive window works too.
    .modifier(DragsWindow())
    // The content fills the whole window, up under the hidden title bar. The outer frame only
    // sizes the window: it adds the title bar's height to it, making 780×600 in all.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
    .frame(
      width: Constants.Windows.onboardingWidth,
      height: Constants.Windows.onboardingHeight - Constants.Windows.titleBarHeight
    )
    .foregroundStyle(Palette.ash)
    .environment(\.colorScheme, .light)
    .background(WindowFinder { window in OnboardingPresence.show(window) })
    .onAppear {
      settings.ensureAPIKeyLoaded()
      openRouterKeyInput = settings.openRouterAPIKey
    }
    .onDisappear { OnboardingPresence.hide() }
  }

  /// Accessibility is the only step people may skip, until it is allowed.
  private var footerSkip: (() -> Void)? {
    step == .accessibility && permissions.accessibilityStatus != .granted
      ? { go(to: .tryIt) } : nil
  }

  /// The footer's Continue button, enabled once the step has what it needs.
  private var footerContinue: FooterContinue? {
    switch step {
    case .apiKey:
      return FooterContinue(
        isEnabled: APIProvider.openRouter.isValidKeyFormat(openRouterKeyInput),
        action: saveKeyAndContinue)
    case .preset:
      return FooterContinue(isEnabled: true, action: applyPresetAndContinue)
    case .microphone:
      return FooterContinue(
        isEnabled: permissions.microphoneStatus == .granted, action: { go(to: .accessibility) })
    case .accessibility:
      return FooterContinue(
        isEnabled: permissions.accessibilityStatus == .granted, action: { go(to: .tryIt) })
    case .tryIt:
      return FooterContinue(isEnabled: true, action: { go(to: .done) })
    case .welcome, .done:
      return nil
    }
  }

  /// Back from the microphone skips the presets when there is no OpenRouter key, which
  /// happens when someone kept their Groq key instead.
  private var previousStep: OnboardingStep? {
    if step == .microphone && !APIProvider.openRouter.isValidKeyFormat(settings.openRouterAPIKey) {
      return .apiKey
    }
    return step.previous
  }

  private func go(to newStep: OnboardingStep) {
    // Steps switch instantly; the fades looked uneven from screen to screen.
    step = newStep
  }

  private func saveKeyAndContinue() {
    settings.ensureAPIKeyLoaded()
    settings.openRouterAPIKey = openRouterKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    go(to: .preset)
  }

  private func applyPresetAndContinue() {
    settings.selectedModel = preset.transcriptionModel
    let chosen = preset
    Task { await ProfilesService.shared.apply(chosen) }
    go(to: .microphone)
  }

  private func finish() {
    if LaunchAtLogin.isEnabled != openAtLogin {
      LaunchAtLogin.isEnabled = openAtLogin
    }
    settings.hasCompletedOnboarding = true
    dismiss()
  }
}

// MARK: - Steps

private struct WelcomeStep: View {
  let onStart: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Heading("Let’s set up Echo", large: true)
      Button("Get Started", action: onStart)
        .buttonStyle(RedPillButtonStyle())
        .keyboardShortcut(.defaultAction)
        .padding(.top, 40)
    }
  }
}

private struct APIKeyStep: View {
  @Binding var keyInput: String
  /// True when a Groq key is already saved, so OpenRouter is optional.
  let canSkip: Bool
  let onContinue: () -> Void
  let onSkip: () -> Void
  @FocusState private var fieldFocused: Bool

  private var isValid: Bool { APIProvider.openRouter.isValidKeyFormat(keyInput) }

  var body: some View {
    VStack(spacing: 0) {
      Heading("OpenRouter API Key")
      BodyText("Echo sends your recordings to OpenRouter to turn speech into text and tidy it up.")

      // 620 pt inside the box, so a whole OpenRouter key (about 73 characters, 591 pt) fits
      // beside the tick without scrolling.
      HStack(spacing: 8) {
        SecureField("sk-or-…", text: $keyInput)
          .textFieldStyle(.plain)
          .font(.system(size: 13, design: .monospaced))
          .foregroundStyle(Palette.ink)
          .focused($fieldFocused)
          .onSubmit { if isValid { onContinue() } }
          .accessibilityLabel("OpenRouter API key")

        Image(systemName: "checkmark")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Palette.line)
          .opacity(isValid ? 1 : 0)
          .accessibilityLabel("Key looks right")
          .accessibilityHidden(!isValid)
      }
      .frame(width: 620)
      .fieldBox()
      .onTapGesture { fieldFocused = true }
      .padding(.top, 30)

      HStack(spacing: 4) {
        Text("Get a key at")
        HoverLink("openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
      }
      .font(.system(size: 13))
      .frame(height: 18)
      .padding(.top, 12)

      if canSkip && !isValid {
        TextLinkButton("Keep using my Groq key", action: onSkip)
          .padding(.top, 24)
      }
    }
    .onAppear { fieldFocused = true }
  }
}

private struct MicrophoneStep: View {
  @ObservedObject private var permissions = PermissionManager.shared

  var body: some View {
    VStack(spacing: 0) {
      Heading("Allow Echo to use your microphone")
      BodyText(
        permissions.microphoneStatus == .denied
          ? "Turn on Echo under Microphone in System Settings, then come back."
          : "Only active while you’re recording."
      )

      Group {
        switch permissions.microphoneStatus {
        case .granted:
          CheckStatus("Allowed").frame(height: 44)
        case .denied:
          Button("Open System Settings", action: permissions.openMicrophoneSettings)
            .buttonStyle(RedPillButtonStyle())
        case .unknown:
          Button("Allow Microphone", action: permissions.requestMicrophonePermission)
          .buttonStyle(RedPillButtonStyle())
        }
      }
      .padding(.top, 36)
    }
    .onAppear { permissions.checkMicrophonePermission() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      permissions.checkMicrophonePermission()
    }
  }
}

private struct AccessibilityStep: View {
  @ObservedObject private var permissions = PermissionManager.shared
  @State private var waiting = false

  var body: some View {
    VStack(spacing: 0) {
      Heading("Let Echo paste for you")
      BodyText("Lets Echo use the fn key and paste the transcription into any app.")

      if permissions.accessibilityStatus == .granted {
        CheckStatus("Allowed").frame(height: 44).padding(.top, 36)
      } else {
        Button(waiting || permissions.hasAskedForAccessibility ? "Open System Settings" : "Allow Accessibility") {
          waiting = true
          permissions.requestAccessibilityPermission()
        }
        .buttonStyle(RedPillButtonStyle())
        // Hung 18 pt below the button (which is 44 pt high) rather than stacked under it. An
        // overlay takes no part in the layout, so showing it does not make the step taller
        // and move what is above.
        .overlay(alignment: .top) {
          if waiting {
            WaitingStatus("Waiting for you to turn on Echo under Accessibility…")
              .fixedSize()
              .padding(.top, 44 + 18)
          }
        }
        .padding(.top, 36)
      }
    }
    .onAppear { permissions.checkAccessibilityPermission() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      permissions.checkAccessibilityPermission()
    }
  }
}

private struct TryItStep: View {
  @State private var testText = ""
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      Heading("Test it out")

      VStack(alignment: .leading, spacing: 6) {
        Bullet("Hold fn while you talk, then let go.")
        Bullet("Or tap fn, talk, then tap fn again when you’re done.")
      }
      .frame(width: 460, alignment: .leading)
      .padding(.top, 22)

      TextEditor(text: $testText)
        .textEditorStyle(.plain)
        .scrollContentBackground(.hidden)
        // With "Show scroll bars: Always" the field showed an empty scroll bar track.
        .scrollIndicators(.never)
        .font(.system(size: 15))
        .lineSpacing(3)
        .foregroundStyle(Palette.ink)
        .focused($fieldFocused)
        .accessibilityLabel("Dictation test field")
        .frame(width: 460 - 20, height: 112 - 20, alignment: .topLeading)
        .fieldBox()
        .onTapGesture { fieldFocused = true }
        .padding(.top, 14)

      CheckStatus("Pasted")
        .opacity(testText.isEmpty ? 0 : 1)
        .frame(height: 18)
        .padding(.top, 10)
    }
    .onAppear { fieldFocused = true }
  }
}

private struct Bullet: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("•").foregroundStyle(Palette.line)
      Text(text)
    }
    .font(.system(size: 13))
  }
}

private struct PresetStep: View {
  @Binding var selection: ModelPreset

  var body: some View {
    VStack(spacing: 0) {
      Heading("Choose a setup")
      BodyText("Both use your OpenRouter key. You can change models later in Settings.")

      HStack(spacing: 20) {
        ForEach(ModelPreset.all) { preset in
          PresetCard(preset: preset, isSelected: preset == selection) {
            selection = preset
          }
        }
      }
      .padding(.top, 18)
    }
  }
}

private struct PresetCard: View {
  let preset: ModelPreset
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(preset.title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.ink)
          Spacer()
          Text(preset.badge)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isSelected ? Palette.button : Palette.ash)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(isSelected ? Palette.line.opacity(0.12) : Color.black.opacity(0.05)))
        }
        .padding(.bottom, 8)

        PresetRow(label: "Speech-to-text", value: preset.transcriptionLabel)
        PresetRow(label: "Clean-up", value: preset.postProcessingLabel)
        PresetRow(label: "Languages", value: preset.languages)
        PresetRow(label: "Errors", value: preset.errorRate)
        PresetRow(label: "Typical wait", value: preset.typicalWait)
        PresetRow(label: "Cost", value: preset.cost, isLast: true)
      }
      .padding(16)
      .frame(width: 300)
      .background(
        RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.white : Color.white.opacity(0.45))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(isSelected ? Palette.line : Color.black.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

private struct PresetRow: View {
  let label: String
  let value: String
  var isLast = false

  var body: some View {
    HStack {
      Text(label)
      Spacer(minLength: 12)
      Text(value)
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
    }
    .font(.system(size: 13))
    .padding(.vertical, 5)
    .overlay(alignment: .bottom) {
      if !isLast {
        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
      }
    }
  }
}

private struct DoneStep: View {
  @Binding var openAtLogin: Bool
  let onDone: () -> Void

  var body: some View {
    VStack(spacing: 0) {
        Heading("Echo is ready", large: true)
        BodyText("It appears at the bottom of your screen when you hold fn.")
          .frame(maxWidth: 480)

        Toggle("Open Echo at login", isOn: $openAtLogin)
          .toggleStyle(RedCheckboxStyle())
          .font(.system(size: 13))
          .padding(.top, 24)

        Button("Done", action: onDone)
          .buttonStyle(RedPillButtonStyle())
          .keyboardShortcut(.defaultAction)
          .padding(.top, 22)
    }
  }
}

// MARK: - Footer

struct FooterContinue {
  let isEnabled: Bool
  let action: () -> Void
}

private struct OnboardingFooter: View {
  let dotIndex: Int
  let onBack: (() -> Void)?
  let skip: (() -> Void)?
  let next: FooterContinue?

  var body: some View {
    VStack {
      Spacer()
      HStack(spacing: 0) {
        HStack {
          if let onBack { TextLinkButton("Back", action: onBack) }
          Spacer()
        }
        .frame(width: 220)

        StepDots(current: dotIndex, count: OnboardingStep.numberedStepCount)
          .frame(maxWidth: .infinity)

        HStack(spacing: 20) {
          Spacer()
          if let skip { TextLinkButton("Skip", action: skip) }
          if let next {
            Button("Continue", action: next.action)
              .buttonStyle(RedPillButtonStyle())
              .keyboardShortcut(.defaultAction)
              .disabled(!next.isEnabled)
          }
        }
        .frame(width: 220)
      }
      .frame(height: 44)
      .padding(.horizontal, 32)
      .padding(.bottom, 24)
    }
  }
}

private struct StepDots: View {
  let current: Int
  let count: Int

  var body: some View {
    HStack(spacing: 8) {
      ForEach(0..<count, id: \.self) { index in
        let size: CGFloat = index == current ? 8 : 6
        Circle()
          .fill(index <= current ? Palette.line : Palette.dotUpcoming)
          .frame(width: size, height: size)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Step \(current + 1) of \(count)")
  }
}

// MARK: - Pieces

private struct Heading: View {
  let text: String
  let large: Bool

  init(_ text: String, large: Bool = false) {
    self.text = text
    self.large = large
  }

  var body: some View {
    Text(text)
      .font(.system(size: large ? 40 : 34, weight: .light))
      .tracking(large ? -0.6 : -0.34)
      .foregroundStyle(Palette.ink)
      .multilineTextAlignment(.center)
      .accessibilityAddTraits(.isHeader)
  }
}

private struct BodyText: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 16))
      .lineSpacing(4)
      .multilineTextAlignment(.center)
      .padding(.top, 14)
  }
}

/// The white, outlined box shared by the key field and the try-it field.
private struct FieldBox: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(10)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 8))
  }
}

extension View {
  fileprivate func fieldBox() -> some View { modifier(FieldBox()) }
}

private struct CheckStatus: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "checkmark")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Palette.line)
        .accessibilityHidden(true)
      Text(text)
    }
    .font(.system(size: 13))
    .fixedSize()
  }
}

private struct WaitingStatus: View {
  let text: String
  @State private var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(_ text: String) { self.text = text }

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(Palette.line)
        .frame(width: 7, height: 7)
        .scaleEffect(pulsing ? 1 : 0.75)
        .opacity(pulsing ? 1 : 0.3)
        .accessibilityHidden(true)
      Text(text)
    }
    .font(.system(size: 13))
    .onAppear {
      guard !reduceMotion else {
        pulsing = true
        return
      }
      withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
        pulsing = true
      }
    }
  }
}

private struct RedPillButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(.white)
      .padding(.horizontal, 28)
      .frame(height: 44)
      .background(
        RoundedRectangle(cornerRadius: 22).fill(
          configuration.isPressed || (hovering && isEnabled) ? Palette.buttonHover : Palette.button)
      )
      .opacity(isEnabled ? 1 : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: 22))
      .onHover { hovering = $0 }
  }
}

/// A checkbox in Echo's red, which the system checkbox only shows while the window is key.
private struct RedCheckboxStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 4)
          .fill(configuration.isOn ? Palette.line : Color.white)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .strokeBorder(configuration.isOn ? Color.clear : Color.gray.opacity(0.5), lineWidth: 1)
          )
          .overlay {
            if configuration.isOn {
              Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
            }
          }
          .frame(width: 15, height: 15)
        configuration.label
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isToggle)
    .accessibilityValue(configuration.isOn ? "On" : "Off")
  }
}

/// A web link in the heading colour, underlined while the pointer is over it.
private struct HoverLink: View {
  let title: String
  let destination: URL
  @State private var hovering = false

  init(_ title: String, destination: URL) {
    self.title = title
    self.destination = destination
  }

  var body: some View {
    Link(destination: destination) {
      Text(title)
        .foregroundStyle(Palette.ink)
        .underline(hovering)
    }
    .pointerStyle(.link)
    .onHover { hovering = $0 }
  }
}

private struct TextLinkButton: View {
  let title: String
  let action: () -> Void
  @State private var hovering = false

  init(_ title: String, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13))
        .foregroundStyle(hovering ? Palette.ink : Palette.ash)
        .underline(hovering)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}

// MARK: - Window presence

/// Echo is a menu bar app with no Dock icon. During setup it shows one, like a regular app,
/// and brings the setup window in front of whatever else is open.
@MainActor
private enum OnboardingPresence {
  static func show(_ window: NSWindow) {
    NSApp.setActivationPolicy(.regular)
    // The policy change takes effect on the next run loop pass; activating in the same pass
    // leaves the window behind the frontmost app.
    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      // macOS may refuse to activate an app the user didn't click, so the window floats above
      // other apps until Echo becomes active (the user clicks it), then acts normally. A
      // window can be key while its app is inactive, so key status is not enough.
      window.level = .floating
      keyObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) { _ in
        MainActor.assumeIsolated { stopFloating(window) }
      }
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
      if NSApp.isActive { stopFloating(window) }
    }
  }

  static func hide() {
    if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    keyObserver = nil
    NSApp.setActivationPolicy(.accessory)
  }

  private static var keyObserver: NSObjectProtocol?

  private static func stopFloating(_ window: NSWindow) {
    window.level = .normal
    if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    keyObserver = nil
  }
}

// MARK: - Previews

#Preview("Onboarding") {
  OnboardingView()
}

#Preview("API Key") {
  OnboardingView(initialStep: .apiKey)
}

#Preview("Preset") {
  OnboardingView(initialStep: .preset)
}

#Preview("Try It") {
  OnboardingView(initialStep: .tryIt)
}

#Preview("Done") {
  OnboardingView(initialStep: .done)
}
