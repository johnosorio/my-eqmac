//
//  ExpertEqualizer.swift
//  eqMac
//

import Foundation
import ReSwift
import EmitterKit
import SwiftyUserDefaults
import AVFoundation

class ExpertEqualizer: Equalizer, StoreSubscriber {
  static let maximumBands = EXPERT_EQUALIZER_MAXIMUM_BANDS
  static let channelProcessor = ExpertChannelEqualizerProcessor()

  static var defaultPresets: [ExpertEqualizerPreset] {
    return EXPERT_EQUALIZER_DEFAULT_PRESETS
  }

  static var userPresets: [ExpertEqualizerPreset] {
    get {
      return Storage[.expertEqualizerPresets] ?? []
    }
    set (newPresets) {
      Storage[.expertEqualizerPresets] = newPresets
      presetsChanged.emit(presets)
    }
  }

  static var presets: [ExpertEqualizerPreset] {
    get {
      var presets: [ExpertEqualizerPreset] = self.userPresets
      let hasManual = presets.contains { $0.id == "manual" }
      if (!hasManual) {
        presets.append(ExpertEqualizerPreset(
          id: "manual",
          name: "Manual",
          isDefault: true,
          global: 0,
          bands: EXPERT_EQUALIZER_DEFAULT_BANDS
        ))
      }
      if (Application.store.state.effects.equalizers.expert.showDefaultPresets) {
        presets += self.defaultPresets
      } else if let flatPreset = self.defaultPresets.first(where: { $0.id == "flat" }) {
        presets.append(flatPreset)
      }
      return presets
    }
  }

  static func getPreset (id: String) -> ExpertEqualizerPreset? {
    return self.presets.first(where: { $0.id == id })
  }

  static func createPreset (
    name: String,
    global: Double,
    bands: [ExpertEqualizerPresetBand],
    channels: [String: [ExpertEqualizerPresetBand]]? = nil
  ) -> ExpertEqualizerPreset {
    let preset = ExpertEqualizerPreset(
      id: UUID().uuidString,
      name: name,
      isDefault: false,
      global: global,
      bands: bands,
      channels: channels
    )
    self.userPresets.append(preset)
    presetsChanged.emit(presets)
    return preset
  }

  static func updatePreset (
    id: String,
    global: Double,
    bands: [ExpertEqualizerPresetBand],
    channels: [String: [ExpertEqualizerPresetBand]]? = nil
  ) {
    var presets = self.userPresets
    if var preset = self.getPreset(id: id) {
      preset = ExpertEqualizerPreset(
        id: id,
        name: preset.name,
        isDefault: false,
        global: global,
        bands: bands,
        channels: channels
      )
      presets.removeAll(where: { $0.id == preset.id })
      presets.append(preset)
      self.userPresets = presets
      presetsChanged.emit(presets)
    }
  }

  static func setSelectedPreset(global: Double, bands: [ExpertEqualizerPresetBand], transition: Bool = false) -> ExpertEqualizerPreset {
    let selectedId = Application.store.state.effects.equalizers.expert.selectedPresetId
    if let selectedPreset = self.getPreset(id: selectedId), !selectedPreset.isDefault {
      self.updatePreset(id: selectedPreset.id, global: global, bands: bands)
      Application.dispatchAction(ExpertEqualizerAction.selectPreset(selectedPreset.id, transition))
      return self.getPreset(id: selectedPreset.id)!
    }

    let existingManual = self.getPreset(id: "manual")
    let preset = ExpertEqualizerPreset(
      id: "manual",
      name: existingManual?.name ?? "Manual",
      isDefault: false,
      global: global,
      bands: bands
    )
    var presets = self.userPresets
    presets.removeAll(where: { $0.id == preset.id })
    presets.append(preset)
    self.userPresets = presets
    Application.dispatchAction(ExpertEqualizerAction.selectPreset(preset.id, transition))
    return preset
  }

  static func addBandToSelectedPreset(_ band: ExpertEqualizerPresetBand) -> ExpertEqualizerPreset {
    let preset = self.getSelectedPreset()
    var bands = preset.bands
    bands.append(band)
    return setSelectedPreset(global: preset.global, bands: bands, transition: true)
  }

  static func updateBandInSelectedPreset(index: Int, band: ExpertEqualizerPresetBand) -> ExpertEqualizerPreset {
    let preset = self.getSelectedPreset()
    var bands = preset.bands
    bands[index] = band
    return setSelectedPreset(global: preset.global, bands: bands, transition: false)
  }

  static func deleteBandFromSelectedPreset(index: Int) -> ExpertEqualizerPreset {
    let preset = self.getSelectedPreset()
    var bands = preset.bands
    bands.remove(at: index)
    return setSelectedPreset(global: preset.global, bands: bands, transition: true)
  }

  static func setSelectedGlobalGain(_ global: Double) -> ExpertEqualizerPreset {
    let preset = self.getSelectedPreset()
    return setSelectedPreset(global: global, bands: preset.bands, transition: true)
  }

  static func autoGainSelectedPreset() -> ExpertEqualizerPreset {
    let preset = self.getSelectedPreset()
    let maxGain = preset.bands.filter { $0.enabled }.map { $0.gain }.max() ?? 0
    let global = -Swift.max(0, maxGain)
    return setSelectedPreset(global: global, bands: preset.bands, transition: true)
  }

  static func getSelectedPreset() -> ExpertEqualizerPreset {
    let selectedId = Application.store.state.effects.equalizers.expert.selectedPresetId
    return self.getPreset(id: selectedId) ?? self.getPreset(id: "flat")!
  }

  static func deletePreset (_ preset: ExpertEqualizerPreset) {
    self.userPresets.removeAll(where: { $0.id == preset.id })
    presetsChanged.emit(presets)
  }

  static func processChannelPreset(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
    channelProcessor.process(ioData: ioData, frameCount: frameCount)
  }

  static var presetsChanged = Event<[ExpertEqualizerPreset]>()
  static var selectedPresetChanged = Event<ExpertEqualizerPreset>()
  var selectedPresetChanged = Event<ExpertEqualizerPreset>()

  var channels: Int = 2
  var splitter: AVAudioNode?
  var eqs: [AVAudioUnitEQ] = []
  var mixer: AVAudioNode?
  var transition = false

  var selectedPreset: ExpertEqualizerPreset = ExpertEqualizer.getPreset(id: "flat")! {
    didSet {
      apply(preset: selectedPreset, transition: transition)
      selectedPresetChanged.emit(selectedPreset)
      ExpertEqualizer.selectedPresetChanged.emit(selectedPreset)
    }
  }

  var state: ExpertEqualizerState {
    return Application.store.state.effects.equalizers.expert
  }

  init () {
    Console.log("Creating Expert Equalizer")

    super.init(numberOfBands: ExpertEqualizer.maximumBands)
    resetBands(on: eq)
    eqs = [eq]

    if let preset = ExpertEqualizer.getPreset(id: self.state.selectedPresetId) {
      ({ self.selectedPreset = preset })()
    }
    setupStateListener()
  }

  func setupStateListener () {
    Application.store.subscribe(self) { subscription in
      subscription.select { state in state.effects.equalizers.expert }
    }
  }

  func newState(state: ExpertEqualizerState) {
    if let preset = ExpertEqualizer.getPreset(id: state.selectedPresetId) {
      if (selectedPreset.id != state.selectedPresetId || !sameBands(selectedPreset, preset)) {
        transition = state.transition
        selectedPreset = preset
      }
    }
  }

  private func apply(preset: ExpertEqualizerPreset, transition: Bool) {
    if let channels = preset.channels, !channels.isEmpty {
      globalGain = 0
      for eq in eqs {
        resetBands(on: eq)
      }
      ExpertEqualizer.channelProcessor.configure(
        global: preset.global,
        channels: channels,
        sampleRate: currentSampleRate()
      )
      return
    }

    ExpertEqualizer.channelProcessor.disable()
    if (transition) {
      Transition.perform(from: globalGain, to: preset.global) { gainStep in
        self.globalGain = gainStep
      }
    } else {
      globalGain = preset.global
    }

    for eq in eqs {
      apply(preset: preset, to: eq)
    }
  }

  private func apply(preset: ExpertEqualizerPreset, to eq: AVAudioUnitEQ) {
    for (index, band) in eq.bands.enumerated() {
      if (index < preset.bands.count) {
        apply(presetBand: preset.bands[index], to: band)
      } else {
        band.bypass = true
        band.gain = 0
      }
    }
  }

  private func resetBands(on eq: AVAudioUnitEQ) {
    eq.globalGain = 0
    for band in eq.bands {
      band.bypass = true
      band.filterType = .parametric
      band.bandwidth = 1.0
      band.gain = 0
    }
  }

  private func apply(presetBand: ExpertEqualizerPresetBand, to band: AVAudioUnitEQFilterParameters) {
    band.filterType = avFilterType(for: presetBand.filterType)
    band.frequency = Float(clamp(presetBand.frequency, min: 20, max: 20000))
    band.gain = Float(clamp(presetBand.gain, min: -24, max: 24))
    band.bandwidth = Float(bandwidthOctaves(forQ: presetBand.q))
    band.bypass = !presetBand.enabled
  }

  private func avFilterType(for type: ExpertEqualizerPresetBandFilterType) -> AVAudioUnitEQFilterType {
    switch type {
    case .peak:
      return .parametric
    case .lowShelf:
      return .lowShelf
    case .highShelf:
      return .highShelf
    case .lowPass:
      return .lowPass
    case .highPass:
      return .highPass
    }
  }

  private func bandwidthOctaves(forQ q: Double) -> Double {
    let q = clamp(q, min: 0.1, max: 24)
    let q2 = q * q
    let value = (2 * q2 + 1 + sqrt(pow(2 * q2 + 1, 2) - 1)) / (2 * q2)
    return clamp(log2(value), min: 0.05, max: 5)
  }

  private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
    return Swift.max(minValue, Swift.min(maxValue, value))
  }

  private func sameBands(_ lhs: ExpertEqualizerPreset, _ rhs: ExpertEqualizerPreset) -> Bool {
    return lhs.global == rhs.global && lhs.bands == rhs.bands && lhs.channels == rhs.channels
  }

  private func currentSampleRate() -> Double {
    if let sampleRate = Application.output?.device.actualSampleRate() {
      return sampleRate
    }
    if let sampleRate = Application.selectedDevice?.actualSampleRate() {
      return sampleRate
    }
    if let sampleRate = Driver.device?.actualSampleRate() {
      return sampleRate
    }
    return 44100
  }

  typealias StoreSubscriberStateType = ExpertEqualizerState

  deinit {
    Application.store.unsubscribe(self)
  }
}

class ExpertChannelEqualizerProcessor {
  private let lock = NSLock()
  private var sampleRate: Double = 44100
  private var globalGain: Float = 1
  private var filtersByChannel: [[ExpertBiquadFilter]] = []

  func configure(global: Double, channels: [String: [ExpertEqualizerPresetBand]], sampleRate: Double) {
    lock.lock()
    defer { lock.unlock() }

    self.sampleRate = sampleRate
    globalGain = Float(pow(10, global / 20))
    filtersByChannel = [
      makeFilters(for: channelBands(channels, index: 0), sampleRate: sampleRate),
      makeFilters(for: channelBands(channels, index: 1), sampleRate: sampleRate),
    ]
  }

  func disable() {
    lock.lock()
    filtersByChannel = []
    globalGain = 1
    lock.unlock()
  }

  func process(ioData: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32) {
    lock.lock()
    defer { lock.unlock() }

    if filtersByChannel.isEmpty {
      return
    }

    let bufferList = UnsafeMutableAudioBufferListPointer(ioData)
    for channelIndex in 0 ..< bufferList.count {
      if channelIndex >= filtersByChannel.count {
        continue
      }
      var channelFilters = filtersByChannel[channelIndex]
      if channelFilters.isEmpty {
        continue
      }
      let audioBuffer = bufferList[channelIndex]
      guard let data = audioBuffer.mData else {
        continue
      }
      let samples = data.assumingMemoryBound(to: Float.self)
      let count = min(Int(frameCount), Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.stride)
      for sampleIndex in 0 ..< count {
        var sample = samples[sampleIndex] * globalGain
        for filterIndex in 0 ..< channelFilters.count {
          sample = channelFilters[filterIndex].process(sample)
        }
        samples[sampleIndex] = sample
      }
      filtersByChannel[channelIndex] = channelFilters
    }
  }

  private func channelBands(
    _ channels: [String: [ExpertEqualizerPresetBand]],
    index: Int
  ) -> [ExpertEqualizerPresetBand] {
    if index == 0 {
      return channels["L"] ?? channels["LEFT"] ?? channels["0"] ?? channels.sorted(by: { $0.key < $1.key }).first?.value ?? []
    }
    return channels["R"] ?? channels["RIGHT"] ?? channels["1"] ?? channels["L"] ?? channels["LEFT"] ?? []
  }

  private func makeFilters(for bands: [ExpertEqualizerPresetBand], sampleRate: Double) -> [ExpertBiquadFilter] {
    return bands
      .filter { $0.enabled }
      .compactMap { ExpertBiquadFilter(band: $0, sampleRate: sampleRate) }
  }
}

struct ExpertBiquadFilter {
  private let b0: Float
  private let b1: Float
  private let b2: Float
  private let a1: Float
  private let a2: Float
  private var z1: Float = 0
  private var z2: Float = 0

  init?(band: ExpertEqualizerPresetBand, sampleRate: Double) {
    let frequency = min(max(band.frequency, 20), sampleRate / 2 - 1)
    if frequency <= 0 {
      return nil
    }

    let q = max(0.1, min(24, band.q))
    let omega = 2 * Double.pi * frequency / sampleRate
    let sinOmega = sin(omega)
    let cosOmega = cos(omega)
    let alpha = sinOmega / (2 * q)
    let gain = band.gain
    let a = pow(10, gain / 40)

    let coefficients: (Double, Double, Double, Double, Double, Double)
    switch band.filterType {
    case .peak:
      coefficients = (
        1 + alpha * a,
        -2 * cosOmega,
        1 - alpha * a,
        1 + alpha / a,
        -2 * cosOmega,
        1 - alpha / a
      )
    case .lowPass:
      coefficients = (
        (1 - cosOmega) / 2,
        1 - cosOmega,
        (1 - cosOmega) / 2,
        1 + alpha,
        -2 * cosOmega,
        1 - alpha
      )
    case .highPass:
      coefficients = (
        (1 + cosOmega) / 2,
        -(1 + cosOmega),
        (1 + cosOmega) / 2,
        1 + alpha,
        -2 * cosOmega,
        1 - alpha
      )
    case .lowShelf:
      let sqrtA = sqrt(a)
      let shelfAlpha = sinOmega / 2 * sqrt(max(0, (a + 1 / a) * (1 / q - 1) + 2))
      coefficients = (
        a * ((a + 1) - (a - 1) * cosOmega + 2 * sqrtA * shelfAlpha),
        2 * a * ((a - 1) - (a + 1) * cosOmega),
        a * ((a + 1) - (a - 1) * cosOmega - 2 * sqrtA * shelfAlpha),
        (a + 1) + (a - 1) * cosOmega + 2 * sqrtA * shelfAlpha,
        -2 * ((a - 1) + (a + 1) * cosOmega),
        (a + 1) + (a - 1) * cosOmega - 2 * sqrtA * shelfAlpha
      )
    case .highShelf:
      let sqrtA = sqrt(a)
      let shelfAlpha = sinOmega / 2 * sqrt(max(0, (a + 1 / a) * (1 / q - 1) + 2))
      coefficients = (
        a * ((a + 1) + (a - 1) * cosOmega + 2 * sqrtA * shelfAlpha),
        -2 * a * ((a - 1) + (a + 1) * cosOmega),
        a * ((a + 1) + (a - 1) * cosOmega - 2 * sqrtA * shelfAlpha),
        (a + 1) - (a - 1) * cosOmega + 2 * sqrtA * shelfAlpha,
        2 * ((a - 1) - (a + 1) * cosOmega),
        (a + 1) - (a - 1) * cosOmega - 2 * sqrtA * shelfAlpha
      )
    }

    let a0 = coefficients.3
    b0 = Float(coefficients.0 / a0)
    b1 = Float(coefficients.1 / a0)
    b2 = Float(coefficients.2 / a0)
    a1 = Float(coefficients.4 / a0)
    a2 = Float(coefficients.5 / a0)
  }

  mutating func process(_ input: Float) -> Float {
    let output = b0 * input + z1
    z1 = b1 * input - a1 * output + z2
    z2 = b2 * input - a2 * output
    return output
  }
}
