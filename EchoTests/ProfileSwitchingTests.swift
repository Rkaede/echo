import Foundation
import Testing

@testable import Echo

@Suite("Switching profiles while recording")
struct ProfileSwitchingTests {
  private func profile(_ id: String, model: String) -> Profile {
    Profile(
      id: id, title: id, isDefault: false, isEnabled: true, shortcut: nil,
      transcriptionModel: model, postProcessingEnabled: false,
      postProcessingPrompt: PostProcessingData.defaultPrompt,
      postProcessingModel: PostProcessingModelOption.defaultOptionValue,
      createdAt: Date(), updatedAt: Date()
    )
  }

  private var profiles: [Profile] {
    [
      profile("groq-a", model: "whisper-large-v3-turbo"),
      profile("openrouter", model: "microsoft/mai-transcribe-2"),
      profile("groq-b", model: "whisper-large-v3"),
    ]
  }

  /// Only a Groq key is saved, so the OpenRouter profile cannot transcribe.
  private func hasGroqKeyOnly(_ profile: Profile) -> Bool {
    TranscriptionData.provider(for: profile.transcriptionModel) == .groq
  }

  @Test func nextAndPreviousStepThroughEveryProfileWhenAllHaveKeys() {
    let next = ProfilesService.profileToSwitchTo(
      from: "groq-a", in: profiles, direction: 1, canTranscribe: { _ in true })
    #expect(next?.id == "openrouter")

    let previous = ProfilesService.profileToSwitchTo(
      from: "groq-a", in: profiles, direction: -1, canTranscribe: { _ in true })
    #expect(previous?.id == "groq-b")
  }

  @Test func aProfileWhoseProviderHasNoKeyIsPassedOver() {
    let next = ProfilesService.profileToSwitchTo(
      from: "groq-a", in: profiles, direction: 1, canTranscribe: hasGroqKeyOnly)
    #expect(next?.id == "groq-b")

    let previous = ProfilesService.profileToSwitchTo(
      from: "groq-b", in: profiles, direction: -1, canTranscribe: hasGroqKeyOnly)
    #expect(previous?.id == "groq-a")
  }

  @Test func theActiveProfileStaysWhenNoOtherCanTranscribe() {
    let two = Array(profiles.prefix(2))
    #expect(
      ProfilesService.profileToSwitchTo(
        from: "groq-a", in: two, direction: 1, canTranscribe: hasGroqKeyOnly) == nil)
    #expect(
      ProfilesService.profileToSwitchTo(
        from: "groq-a", in: [profiles[0]], direction: 1, canTranscribe: { _ in true }) == nil)
  }

  @Test func withoutAnActiveProfileTheFirstUsableOneIsChosen() {
    let chosen = ProfilesService.profileToSwitchTo(
      from: nil, in: Array(profiles.dropFirst()), direction: 1, canTranscribe: hasGroqKeyOnly)
    #expect(chosen?.id == "groq-b")
  }
}
