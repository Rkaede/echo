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
    accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
  }
  
  func requestMicrophonePermission() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        self.microphoneStatus = granted ? .granted : .denied
      }
    }
  }
  
  func requestAccessibilityPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    bringAccessibilityPromptForward()

    // Start a timer to check periodically since there's no callback
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
      let isTrusted = AXIsProcessTrusted()
      if isTrusted {
        DispatchQueue.main.async {
          self.accessibilityStatus = .granted
        }
        timer.invalidate()
      }
    }
  }
  
  /// The system shows the accessibility prompt from its own background process at the normal
  /// window level and doesn't activate it, so it can open behind every other window. Hand
  /// activation to that process once its window is on screen. Checks for up to 3 seconds.
  private func bringAccessibilityPromptForward(attempt: Int = 0) {
    let promptBundleID = "com.apple.accessibility.universalAccessAuthWarn"
    if let prompt = NSRunningApplication.runningApplications(withBundleIdentifier: promptBundleID).first,
      Self.hasOnScreenWindow(pid: prompt.processIdentifier)
    {
      NSApp.yieldActivation(to: prompt)
      prompt.activate(from: .current, options: [])
      return
    }
    guard attempt < 12 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      self.bringAccessibilityPromptForward(attempt: attempt + 1)
    }
  }

  private static func hasOnScreenWindow(pid: pid_t) -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }
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