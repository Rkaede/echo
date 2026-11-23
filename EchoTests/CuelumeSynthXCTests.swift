import XCTest

@testable import Echo

/// A deterministic generator, so renders that draw randomness can be compared.
private struct FixedRandom: RandomNumberGenerator {
  var state: UInt64

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return state
  }
}

final class CuelumeSynthXCTests: XCTestCase {
  func testSeededRandomMatchesCuelume() {
    // The first values of Cuelume's `seeded(1)` in output.ts.
    var random = CuelumeSynth.SeededRandom(seed: 1)
    XCTAssertEqual(random.next(), 0.6270739405881613, accuracy: 1e-15)
    XCTAssertEqual(random.next(), 0.002735721180215478, accuracy: 1e-15)
    XCTAssertEqual(random.next(), 0.5274470399599522, accuracy: 1e-15)
  }

  func testEveryCueRendersAudibleFiniteStereoInEveryTheme() {
    for theme in CuelumeTheme.allCases {
      for cue in CuelumeCue.allCases {
        let rendering = CuelumeSynth.render(cue, theme: theme)
        let name = "\(theme.rawValue).\(cue.rawValue)"
        XCTAssertGreaterThan(rendering.frameCount, 0, name)
        XCTAssertEqual(rendering.left.count, rendering.right.count, name)
        let peak = (rendering.left + rendering.right).map(abs).max() ?? 0
        XCTAssertTrue(peak.isFinite, name)
        XCTAssertGreaterThan(peak, 0.01, name)
        XCTAssertLessThan(peak, 1, name)
      }
    }
  }

  func testSoftClipHoldsAtItsCeilingPastFullScale() {
    XCTAssertEqual(CuelumeSynth.softClip(0.5), 0.5)
    XCTAssertEqual(CuelumeSynth.softClip(-0.5), -0.5)
    XCTAssertEqual(CuelumeSynth.softClip(1), 0.85, accuracy: 1e-12)
    // Without the clamp a level of 2 came out as about -0.82: inverted.
    XCTAssertEqual(CuelumeSynth.softClip(2), 0.85, accuracy: 1e-12)
    XCTAssertEqual(CuelumeSynth.softClip(-1.3), -0.85, accuracy: 1e-12)
    let levels = stride(from: 0.0, through: 3.0, by: 0.01).map(CuelumeSynth.softClip)
    XCTAssertTrue(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 }, "never falls as the input rises")
  }

  func testRenderLastsForTheLongestLayerPlusTheRoom() {
    let recipe = CuelumeTheme.standard.recipe(for: .ready)
    let longest = recipe.layers.filter { $0.from <= .normal }
      .map { $0.attack + $0.decay * 1.1 + CuelumeSynth.sourceStopPadding }.max()!
    let rendering = CuelumeSynth.render(.ready, theme: .standard)
    XCTAssertLessThanOrEqual(
      rendering.duration, longest + CuelumeSynth.roomSeconds + 0.05 + 1 / CuelumeSynth.sampleRate)
  }

  func testEmphasisChoosesWhichLayersPlay() {
    let recipe = CuelumeTheme.standard.recipe(for: .tap)
    var rng = FixedRandom(state: 1)
    let subtle = CuelumeSynth.layers(for: recipe, emphasis: .subtle, using: &rng)
    let normal = CuelumeSynth.layers(for: recipe, emphasis: .normal, using: &rng)
    let strong = CuelumeSynth.layers(for: recipe, emphasis: .strong, using: &rng)
    XCTAssertEqual(subtle.count, recipe.layers.filter { $0.from == .subtle }.count)
    XCTAssertEqual(normal.count, recipe.layers.filter { $0.from != .strong }.count)
    XCTAssertEqual(strong.count, recipe.layers.count)
  }

  func testReleasePlaysAfterThePress() {
    let recipe = CuelumeTheme.press.recipe(for: .tap)
    XCTAssertFalse(recipe.release.isEmpty)
    var rng = FixedRandom(state: 1)
    let layers = CuelumeSynth.layers(for: recipe, emphasis: .normal, using: &rng)
    let playing = { (list: [CuelumeLayer]) in list.filter { $0.from <= .normal }.count }
    XCTAssertEqual(layers.count, playing(recipe.layers) + playing(recipe.release))
    XCTAssertEqual(layers.last?.offset, CuelumeSynth.releaseGap)
  }

  func testCuesWithVariationNeverPlayTheSameTwice() {
    var rng = FixedRandom(state: 7)
    let first = CuelumeSynth.render(.tap, theme: .standard, using: &rng)
    let second = CuelumeSynth.render(.tap, theme: .standard, using: &rng)
    XCTAssertNotEqual(first.left, second.left)
  }

  func testSameRandomnessRendersTheSameTake() {
    var first = FixedRandom(state: 3)
    var second = FixedRandom(state: 3)
    XCTAssertEqual(
      CuelumeSynth.render(.success, theme: .bubble, using: &first).left,
      CuelumeSynth.render(.success, theme: .bubble, using: &second).left)
  }

  func testEnvelopeSwellsThenFallsSixtyDecibelsOverTheDecay() {
    let layer = CuelumeLayer.tone(440, attack: 0.01, decay: 0.5, peak: 0.2)
    XCTAssertEqual(CuelumeSynth.envelope(layer, at: 0), 0)
    XCTAssertEqual(CuelumeSynth.envelope(layer, at: 0.005), 0.1, accuracy: 1e-12)
    XCTAssertEqual(CuelumeSynth.envelope(layer, at: 0.01), 0.2, accuracy: 1e-12)
    XCTAssertEqual(CuelumeSynth.envelope(layer, at: 0.51), 0.2 / 1000, accuracy: 1e-9)
  }

  func testGlideIsExponential() {
    let layer = CuelumeLayer.tone(
      480, attack: 0.001, decay: 0.03, peak: 0.02, glideTo: 300, glideTime: 0.018)
    XCTAssertEqual(CuelumeSynth.pitch(layer, at: 0), 480)
    XCTAssertEqual(CuelumeSynth.pitch(layer, at: 0.009), (480 * 300).squareRoot(), accuracy: 1e-9)
    XCTAssertEqual(CuelumeSynth.pitch(layer, at: 0.1), 300)
  }

  func testLowpassPassesDCAndHighpassBlocksIt() {
    let dc = [Double](repeating: 1, count: 48_000)
    let low = CuelumeBiquad(.lowpass, frequency: 1000, q: CuelumeSynth.flatQ).process(dc)
    let high = CuelumeBiquad(.highpass, frequency: 40, q: CuelumeSynth.flatQ).process(dc)
    XCTAssertEqual(low.last!, 1, accuracy: 1e-6)
    XCTAssertEqual(high.last!, 0, accuracy: 1e-6)
  }

  func testFFTConvolutionMatchesDirectConvolution() {
    let signal: [Float] = (0..<300).map { Float(sin(Double($0) * 0.37)) }
    let kernel: [Float] = (0..<50).map { Float(exp(-Double($0) / 10)) }
    let fast = CuelumeSynth.convolve(signal, kernel)
    XCTAssertEqual(fast.count, signal.count)
    for i in signal.indices {
      var direct: Float = 0
      for j in kernel.indices where i - j >= 0 { direct += signal[i - j] * kernel[j] }
      XCTAssertEqual(fast[i], direct, accuracy: 1e-4)
    }
  }

  func testRoomsAreIndependentChannels() {
    XCTAssertEqual(CuelumeSynth.rooms.count, 2)
    XCTAssertEqual(
      CuelumeSynth.rooms[0].count, Int(CuelumeSynth.roomSeconds * CuelumeSynth.sampleRate))
    XCTAssertNotEqual(CuelumeSynth.rooms[0], CuelumeSynth.rooms[1])
  }

  func testRenderingMakesAStereoBuffer() throws {
    let rendering = CuelumeSynth.render(.ready, theme: .standard)
    let buffer = try XCTUnwrap(rendering.makeBuffer())
    XCTAssertEqual(buffer.format.channelCount, 2)
    XCTAssertEqual(buffer.format.sampleRate, CuelumeSynth.sampleRate)
    XCTAssertEqual(Int(buffer.frameLength), rendering.frameCount)
    XCTAssertEqual(buffer.floatChannelData?[1][100], rendering.right[100])
  }

  // MARK: - Sound options

  func testOldClickSoundsMigrateToTheDefaults() {
    for click in ["click01", "click02", "click03", "click04"] {
      XCTAssertEqual(
        SoundOption.migratedID(click, fallback: .defaultRecordingStart),
        SoundOption.defaultRecordingStart.id)
    }
    XCTAssertEqual(SoundOption.migratedID("success", fallback: .defaultRecordingStart), "success")
    XCTAssertEqual(SoundOption.migratedID("none", fallback: .defaultRecordingStart), "none")
  }

  func testPickerOffersNoneThenEachCueOnce() {
    XCTAssertEqual(SoundOption.allOptions.first, SoundOption.none)
    let ids = SoundOption.allOptions.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertNotNil(SoundOption.option(id: SoundOption.defaultRecordingStart.id))
    XCTAssertNotNil(SoundOption.option(id: SoundOption.defaultTranscriptionComplete.id))
  }
}
