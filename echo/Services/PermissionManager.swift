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