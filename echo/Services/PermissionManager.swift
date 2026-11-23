import AVFoundation
import AppKit
import Foundation
import SwiftUI

enum AppPermissionStatus {
  case unknown
  case granted
  case denied
}

class PermissionManager: ObservableObject {
  static let shared = PermissionManager()
  
  @Published var microphoneStatus: AppPermissionStatus = .unknown
  @Published var accessibilityStatus: AppPermissionStatus = .unknown
  /// Whether Accessibility has been asked for since Echo launched.
  @Published private(set) var hasAskedForAccessibility = false

  private var accessibilityCheckTimer: Timer?
  private var settingsFallbackWorkItem: DispatchWorkItem?

  private init() {
    checkAllPermissions()
  }
  
  func checkAllPermissions() {
    checkMicrophonePermission()
    checkAccessibilityPermission()
  }
  
  func checkMicrophonePermission() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      microphoneStatus = .granted
    case .denied, .restricted:
      microphoneStatus = .denied
    case .notDetermined:
      microphoneStatus = .unknown
    @unknown default:
      microphoneStatus = .unknown
    }
  }
  
  func checkAccessibilityPermission() {
    let trusted = AXIsProcessTrusted()
    accessibilityStatus = trusted ? .granted : .denied
    if trusted {
      settingsFallbackWorkItem?.cancel()
      settingsFallbackWorkItem = nil
      accessibilityCheckTimer?.invalidate()
      accessibilityCheckTimer = nil
      GlobalShortcutMonitor.shared.startMonitoring()
    }
  }
  
  func requestMicrophonePermission() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        self.microphoneStatus = granted ? .granted : .denied
      }
    }
  }
  
  /// Asks for Accessibility, and falls back to opening System Settings if macOS does not show
  /// its own prompt on screen.
  ///
  /// Asking is what adds Echo to the Accessibility list, and which request does it depends on
  /// the macOS version. On macOS 27 it is the attempt to create the keyboard event tap; the
  /// Accessibility request alone left Echo off the list. Both are made here, when the user asks
  /// rather than at launch.
  ///
  /// The first time Echo asks, macOS shows its own dialog (`universalAccessAuthWarn`) with an
  /// "Open System Settings" button and registers Echo in the Accessibility list. Opening System
  /// Settings at the same time would put both on screen together, so we check briefly whether
  /// that dialog appears on the current Space and only open System Settings directly if it does
  /// not (for example, after an earlier launch already triggered it, or on a second click).
  func requestAccessibilityPermission() {
    settingsFallbackWorkItem?.cancel()
    settingsFallbackWorkItem = nil
    watchForAccessibilityPermission()

    if hasAskedForAccessibility {
      openAccessibilitySettings()
      return
    }

    hasAskedForAccessibility = true
    GlobalShortcutMonitor.shared.startMonitoring(askingForAccess: true)
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

    openAccessibilitySettingsIfPromptAbsent(attempt: 0)
  }

  private func openAccessibilitySettingsIfPromptAbsent(attempt: Int) {
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.settingsFallbackWorkItem = nil
      guard !AXIsProcessTrusted() else {
        self.checkAccessibilityPermission()
        return
      }
      if Self.isSystemAccessibilityPromptVisible() {
        return
      }
      if attempt < 5 {
        self.openAccessibilitySettingsIfPromptAbsent(attempt: attempt + 1)
      } else {
        self.openAccessibilitySettings()
      }
    }
    settingsFallbackWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
  }

  private static func isSystemAccessibilityPromptVisible() -> Bool {
    let promptBundleID = "com.apple.accessibility.universalAccessAuthWarn"
    let pids = Set(
      NSRunningApplication.runningApplications(withBundleIdentifier: promptBundleID)
        .map(\.processIdentifier)
    )
    guard !pids.isEmpty else { return false }
    let windows =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
      guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
        pids.contains(ownerPID)
      else { return false }
      if let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? CGFloat,
        let height = bounds["Height"] as? CGFloat
      {
        return width > 0 && height > 0
      }
      return true
    }
  }

  /// Checks each second until Accessibility is allowed, as macOS gives no notice of it.
  private func watchForAccessibilityPermission() {
    guard accessibilityCheckTimer == nil else { return }
    accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
      guard AXIsProcessTrusted() else { return }
      timer.invalidate()
      DispatchQueue.main.async {
        self?.accessibilityCheckTimer = nil
        self?.checkAccessibilityPermission()
      }
    }
  }

  func openMicrophoneSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
      NSWorkspace.shared.open(url)
    }
  }
  
  func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }
  
  var allPermissionsGranted: Bool {
    microphoneStatus == .granted && accessibilityStatus == .granted
  }
}