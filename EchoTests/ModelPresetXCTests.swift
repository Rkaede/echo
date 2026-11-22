import XCTest

@testable import Echo

final class ModelPresetXCTests: XCTestCase {
  func testPresetsUseOfferedOpenRouterModels() throws {
    for preset in ModelPreset.all {
      let transcription = try XCTUnwrap(TranscriptionData.option(for: preset.transcriptionModel))
      XCTAssertEqual(transcription.provider, .openRouter, preset.title)

      let cleanUp = PostProcessingModelOption.resolve(preset.postProcessingModel)
      XCTAssertEqual(cleanUp.value, preset.postProcessingModel, "\(preset.title) clean-up model isn't offered")
      XCTAssertEqual(cleanUp.provider, .openRouter, preset.title)
    }
  }

  func testAccurateIsRecommended() {
    XCTAssertEqual(ModelPreset.recommended, .accurate)
  }
}
