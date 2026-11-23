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

    func activateProfile(id: String) {
        guard let profile = profiles.first(where: { $0.id == id && $0.isEnabled }) else {
            print("ProfilesService: Cannot activate profile with id \(id) - not found or disabled")
            return
        }
        activeProfile = profile
        print("ProfilesService: Activated profile '\(profile.title)' via shortcut")
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

        try ShortcutUtils.validate(profile.shortcut, against:
            profiles.filter { $0.id != ignoreId }.map(\.shortcut) + [
                settings.notesModeShortcut,
                settings.previousProfileShortcut,
                settings.nextProfileShortcut
            ])

        // model (basic check against current supported)
        // For now, accept anything; integration can narrow this to Constants.API models
        guard !profile.transcriptionModel.isEmpty else { throw ProfileValidationError.invalidModel }

        let trimmedPPModel = profile.postProcessingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPPModel.isEmpty else { throw ProfileValidationError.invalidPostProcessingModel }
        // A model Echo no longer offers is allowed: profiles saved by an earlier version still
        // hold one, `PostProcessingModelOption.resolve` runs them on the default, and the
        // editor replaces it on its next save. Rejecting it here would block every other
        // change to such a profile (its shortcut, turning it on or off, duplicating it).
        if PostProcessingModelOption.allOptions.contains(where: { $0.value == trimmedPPModel && $0.disabled }) {
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

    private var preferredDefaultProvider: APIProvider {
        settings.ensureAPIKeyLoaded()
        if !settings.hasAPIKey && settings.hasOpenRouterAPIKey {
            return .openRouter
        }
        return .groq
    }

    private var defaultTranscriptionModelForSeed: String {
        settings.ensureAPIKeyLoaded()
        return TranscriptionData.newProfileModel(
            selected: settings.selectedModel,
            hasGroqKey: settings.hasAPIKey,
            hasOpenRouterKey: settings.hasOpenRouterAPIKey
        )
    }

    private var defaultPostProcessingModelForSeed: String {
        PostProcessingModelOption.defaultOption(for: preferredDefaultProvider).value
    }

    /// Points every profile at a preset's models and turns clean-up on for the default profile,
    /// since the preset's accuracy depends on it. Other profiles keep their clean-up setting.
    func apply(_ preset: ModelPreset) async {
        await load()
        for var profile in profiles {
            profile.transcriptionModel = preset.transcriptionModel
            profile.postProcessingModel = preset.postProcessingModel
            if profile.isDefault {
                profile.postProcessingEnabled = true
            }
            profile.updatedAt = Date()
            _ = try? await repo.update(profile.id, patch: profile)
        }
        await load()
        refreshActiveProfile(preferredId: activeProfile?.id)
    }

    // Seed default profile from legacy settings
    private func makeDefaultSeed() -> Profile {
        let now = Date()
        let prompt = PostProcessingData.defaultPrompt
        return Profile(
            id: UUID().uuidString,
            title: "Default",
            isDefault: true,
            isEnabled: true,
            shortcut: "alt+space", // mirrors current toggle hotkey
            transcriptionModel: defaultTranscriptionModelForSeed,
            postProcessingEnabled: false,
            postProcessingPrompt: prompt,
            postProcessingModel: defaultPostProcessingModelForSeed,
            iconName: nil,
            iconColor: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func loadDefaultProfileSeeds() -> [Profile] {
        DefaultProfilesProvider.load(
            defaultTranscriptionModel: defaultTranscriptionModelForSeed,
            defaultPostProcessingModel: defaultPostProcessingModelForSeed
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

        // Profiles are switched while recording. A profile whose speech-to-text provider has
        // no key saved could not transcribe the recording, so it is passed over.
        settings.ensureAPIKeyLoaded()
        let next = Self.profileToSwitchTo(
            from: activeProfile?.id, in: enabledProfiles, direction: direction
        ) { profile in
            settings.hasAPIKey(for: TranscriptionData.provider(for: profile.transcriptionModel))
        }
        if let next {
            activeProfile = next
        }
    }

    /// The profile `direction` steps (1 or -1) on from the current one, wrapping round and
    /// passing over any that `canTranscribe` rejects. Nil when there is no other profile to
    /// switch to. Without a current profile it is the first one that can transcribe.
    nonisolated static func profileToSwitchTo(
        from currentID: String?, in profiles: [Profile], direction: Int,
        canTranscribe: (Profile) -> Bool
    ) -> Profile? {
        guard let currentID, let index = profiles.firstIndex(where: { $0.id == currentID }) else {
            return profiles.first(where: canTranscribe)
        }
        let count = profiles.count
        for step in 1..<count {
            let candidate = profiles[((index + direction * step) % count + count) % count]
            if canTranscribe(candidate) { return candidate }
        }
        return nil
    }
}
