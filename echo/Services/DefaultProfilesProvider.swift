import Foundation

enum DefaultProfilesProvider {
  private struct SeedProfile: Decodable {
    let title: String
    let isDefault: Bool?
    let isEnabled: Bool?
    let shortcut: String?
    let transcriptionModel: String?
    let postProcessingEnabled: Bool?
    let postProcessingPrompt: String?
    let postProcessingModel: String?
    let iconName: String?
    let iconColor: String?
  }

  static func load(
    defaultTranscriptionModel: String,
    defaultPostProcessingModel: String
  ) -> [Profile] {
    guard let url = Bundle.main.url(forResource: "default_profiles", withExtension: "json") else {
      print("DefaultProfilesProvider: default_profiles.json not found in bundle")
      return []
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let seeds = try decoder.decode([SeedProfile].self, from: data)
      return buildProfiles(
        from: seeds,
        defaultTranscriptionModel: defaultTranscriptionModel,
        defaultPostProcessingModel: defaultPostProcessingModel
      )
    } catch {
      print("DefaultProfilesProvider: Failed to load default profiles: \(error)")
      return []
    }
  }

  private static func buildProfiles(
    from seeds: [SeedProfile],
    defaultTranscriptionModel: String,
    defaultPostProcessingModel: String
  ) -> [Profile] {
    guard !seeds.isEmpty else { return [] }

    let now = Date()
    var profiles: [Profile] = seeds.map { seed in
      let trimmedTitle = seed.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedShortcut = seed.shortcut
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { value -> String? in
          guard !value.isEmpty else { return nil }
          return ShortcutUtils.normalize(value)
        }

      let transcriptionModel = seed.transcriptionModel
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }
        ?? defaultTranscriptionModel

      let postProcessingPrompt = seed.postProcessingPrompt
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }
        ?? "{{TRANSCRIPTION}}"

      let postProcessingModel = seed.postProcessingModel
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }
        ?? defaultPostProcessingModel

      let iconName = seed.iconName
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }

      let iconColor = seed.iconColor
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.isEmpty ? nil : $0 }

      return Profile(
        id: UUID().uuidString,
        title: trimmedTitle,
        isDefault: seed.isDefault ?? false,
        isEnabled: seed.isEnabled ?? true,
        shortcut: normalizedShortcut,
        transcriptionModel: transcriptionModel,
        postProcessingEnabled: seed.postProcessingEnabled ?? false,
        postProcessingPrompt: postProcessingPrompt,
        postProcessingModel: postProcessingModel,
        iconName: iconName,
        iconColor: iconColor,
        createdAt: now,
        updatedAt: now
      )
    }

    enforceSingleDefault(&profiles)
    return profiles
  }

  private static func enforceSingleDefault(_ profiles: inout [Profile]) {
    guard !profiles.isEmpty else { return }

    if let defaultIndex = profiles.firstIndex(where: { $0.isDefault }) {
      for index in profiles.indices where index != defaultIndex {
        profiles[index].isDefault = false
      }
      return
    }

    if let enabledIndex = profiles.firstIndex(where: { $0.isEnabled }) {
      profiles[enabledIndex].isDefault = true
      return
    }

    profiles[0].isDefault = true
    profiles[0].isEnabled = true
  }
}
