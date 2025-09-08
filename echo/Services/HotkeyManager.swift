import AppKit
import Foundation
import HotKey
import SwiftUI

class HotkeyManager: ObservableObject {
  static let shared = HotkeyManager()

  private var toggleHotKey: HotKey?
  private var isToggleHotKeySuspended = false
  
  @Published var shouldTriggerRecording = false

  init() {
    setupToggleHotkey()
  }
  
  private func setupToggleHotkey() {
    print("HotkeyManager: Setting up Option+Space toggle hotkey")
    toggleHotKey = HotKey(key: .space, modifiers: [.option])

    toggleHotKey?.keyDownHandler = { [weak self] in
      print("HotkeyManager: Option+Space pressed")
      DispatchQueue.main.async {
        print("HotkeyManager: Toggling shouldTriggerRecording")
        self?.shouldTriggerRecording.toggle()
      }
    }

    print("HotkeyManager: Toggle hotkey setup complete")
  }

  func suspendToggleHotkey() {
    guard !isToggleHotKeySuspended else { return }
    print("HotkeyManager: Suspending toggle hotkey")
    isToggleHotKeySuspended = true
    toggleHotKey?.isPaused = true
  }

  func resumeToggleHotkey() {
    guard isToggleHotKeySuspended else { return }
    print("HotkeyManager: Resuming toggle hotkey")
    isToggleHotKeySuspended = false
    if let toggleHotKey {
      toggleHotKey.isPaused = false
    } else {
      setupToggleHotkey()
    }
  }
}
