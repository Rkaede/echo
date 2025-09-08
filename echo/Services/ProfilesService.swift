import Foundation
import AppKit

@MainActor
class ProfilesService: ObservableObject {
    static let shared = ProfilesService()

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfile: Profile?

    private let repo = ProfilesRepository()
    private let settings = SettingsManager.shared

    private init() {
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await load()
        // Seed a default profile if none exist
        if profiles.isEmpty {
            var seeds = loadDefaultProfileSeeds()
            if seeds.isEmpty {
                seeds = [makeDefaultSeed()]
            }
            await seedProfilesIfNeeded(seeds)
            await load()
        }
        refreshActiveProfile()
    }

    func load() async {
        let all = await repo.list()
        await MainActor.run { self.profiles = all }
    }

    func getDefault() async -> Profile? {
        await repo.getDefault()
    }

    func setActive(_ id: String) async {
        if let p = profiles.first(where: { $0.id == id && $0.isEnabled }) {
            activeProfile = p
        } else {
            refreshActiveProfile()
        }
    }

    func setDefault(_ id: String) async throws {
        try await repo.setDefault(id)
        await load()
        refreshActiveProfile(preferredId: id)
    }

    func create(title: String,
                transcriptionModel: String,
                postEnabled: Bool,
                prompt: String,
                postProcessingModel: String = PostProcessingModelOption.defaultOptionValue,
                shortcut: String? = nil,
                isDefault: Bool = false,
                isEnabled: Bool = true,
                iconName: String? = nil,
                iconColor: String? = nil) async throws {
        var normalizedShortcut: String? = nil
        if let sc = shortcut, !sc.isEmpty { normalizedShortcut = ShortcutUtils.normalize(sc) }

        let now = Date()
        let profile = Profile(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            isDefault: isDefault,
            isEnabled: isEnabled,
            shortcut: normalizedShortcut,
            transcriptionModel: transcriptionModel,
            postProcessingEnabled: postEnabled,
            postProcessingPrompt: prompt,
            postProcessingModel: postProcessingModel.isEmpty ? PostProcessingModelOption.defaultOptionValue : postProcessingModel,
            iconName: iconName,
            iconColor: iconColor,
            createdAt: now,
            updatedAt: now
        )
        try validate(profile: profile, ignoreId: nil)
        _ = try await repo.create(profile)
        await load()
    }

    func update(profile: Profile) async throws {
        try validate(profile: profile, ignoreId: profile.id)
        _ = try await repo.update(profile.id, patch: profile)
        await load()
        refreshActiveProfile(preferredId: activeProfile?.id)
    }

    func remove(id: String) async throws {
        // Prevent deletion if it's the only profile
        if profiles.count == 1 { throw NSError(domain: "ProfilesService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot delete the only profile"]) }
        // If deleting default, require a new default (UI should handle confirmation; here we pick first other)
        let isDefault = profiles.first(where: { $0.id == id })?.isDefault == true
        try await repo.remove(id)
        await load()
        if isDefault, let first = profiles.first(where: { $0.isEnabled }) {
            try? await setDefault(first.id)
        }
        if activeProfile?.id == id {
            refreshActiveProfile()
        }
    }

    func resetToDefaults() async throws {
        var seeds = loadDefaultProfileSeeds()
        if seeds.isEmpty {
            seeds = [makeDefaultSeed()]
        }

        try await repo.reset(with: seeds)
        await load()
        refreshActiveProfile()
    }

    func assignApp(profileId: String, bundleId: String, appName: String) async throws {
        try await repo.assignApp(profileId: profileId, bundleId: bundleId, appName: appName)
    }

    func unassignApp(bundleId: String) async throws {
        try await repo.unassignApp(bundleId: bundleId)
    }

    func getProfileForApp(bundleId: String) async -> Profile? {
        await repo.getProfileForApp(bundleId: bundleId)
    }

    func activateNextProfile() {
        switchNextProfile(direction: 1)
    }

    func activatePreviousProfile() {
        switchNextProfile(direction: -1)
    }

    // MARK: - Validation

    private func validate(profile: Profile, ignoreId: String?) throws {
        // title
        let title = profile.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(title.count) else { throw ProfileValidationError.invalidTitle }
        let lcTitle = title.lowercased()
        if profiles.contains(where: { $0.title.lowercased() == lcTitle && $0.id != ignoreId }) {
            throw ProfileValidationError.duplicateTitle
        }

        // shortcut
        if let sc = profile.shortcut, !sc.isEmpty {
            let normalized = ShortcutUtils.normalize(sc)
            if ShortcutUtils.reserved.contains(normalized) { throw ProfileValidationError.reservedShortcut }
            if profiles.contains(where: { ($0.shortcut.map { ShortcutUtils.normalize($0) }) == normalized && $0.id != ignoreId }) {
                throw ProfileValidationError.duplicateShortcut
            }
        }

        // model (basic check against current supported)
        // For now, accept anything; integration can narrow this to Constants.API models
        guard !profile.transcriptionModel.isEmpty else { throw ProfileValidationError.invalidModel }

        let trimmedPPModel = profile.postProcessingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPPModel.isEmpty else { throw ProfileValidationError.invalidPostProcessingModel }
        if let option = PostProcessingModelOption.allOptions.first(where: { $0.value == trimmedPPModel }) {
            if option.disabled { throw ProfileValidationError.invalidPostProcessingModel }
        } else {
            throw ProfileValidationError.invalidPostProcessingModel
        }

        // icon/color simple validation
        if let color = profile.iconColor, color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProfileValidationError.invalidColor
        }

        // prompt placeholders
        if !ProfileValidator.validatePrompt(profile.postProcessingPrompt) {
            throw ProfileValidationError.invalidPromptPlaceholders
        }

        if profile.isDefault && !profile.isEnabled {
            throw ProfileValidationError.defaultMustBeEnabled
        }
    }

    // Seed default profile from legacy settings
    private func makeDefaultSeed() -> Profile {
        let now = Date()
        let defaultModel = settings.selectedModel
        let prompt = "{{TRANSCRIPTION}}" // basic prompt template
        return Profile(
            id: UUID().uuidString,
            title: "Default",
            isDefault: true,
            isEnabled: true,
            shortcut: "alt+space", // mirrors current toggle hotkey
            transcriptionModel: defaultModel,
            postProcessingEnabled: false,
            postProcessingPrompt: prompt,
            postProcessingModel: PostProcessingModelOption.defaultOptionValue,
            iconName: nil,
            iconColor: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func loadDefaultProfileSeeds() -> [Profile] {
        DefaultProfilesProvider.load(
            defaultTranscriptionModel: settings.selectedModel,
            defaultPostProcessingModel: PostProcessingModelOption.defaultOptionValue
        )
    }

    private func seedProfilesIfNeeded(_ seeds: [Profile]) async {
        guard !seeds.isEmpty else { return }

        var stagedProfiles: [Profile] = []
        var insertedAny = false

        for profile in seeds {
            do {
                profiles = stagedProfiles
                try validate(profile: profile, ignoreId: nil)
                _ = try await repo.create(profile)
                stagedProfiles.append(profile)
                insertedAny = true
            } catch {
                print("ProfilesService: Failed to seed profile \(profile.title): \(error)")
            }
        }

        if insertedAny {
            profiles = stagedProfiles
            return
        }

        let fallback = makeDefaultSeed()
        do {
            profiles = []
            try validate(profile: fallback, ignoreId: nil)
            _ = try await repo.create(fallback)
        } catch {
            print("ProfilesService: Fallback seed failed: \(error)")
        }
    }

    private func refreshActiveProfile(preferredId: String? = nil) {
        let enabledProfiles = profiles.filter { $0.isEnabled }
        if let preferredId,
           let preferred = enabledProfiles.first(where: { $0.id == preferredId }) {
            activeProfile = preferred
            return
        }
        if let def = enabledProfiles.first(where: { $0.isDefault }) {
            activeProfile = def
            return
        }
        activeProfile = enabledProfiles.first
    }

    private func switchNextProfile(direction: Int) {
        let enabledProfiles = profiles.filter { $0.isEnabled }
        guard !enabledProfiles.isEmpty else { return }

        guard let current = activeProfile,
              let idx = enabledProfiles.firstIndex(where: { $0.id == current.id })
        else {
            activeProfile = enabledProfiles.first
            return
        }

        let count = enabledProfiles.count
        guard count > 1 else { return }

        var nextIndex = (idx + direction) % count
        if nextIndex < 0 { nextIndex += count }

        activeProfile = enabledProfiles[nextIndex]
    }
}
