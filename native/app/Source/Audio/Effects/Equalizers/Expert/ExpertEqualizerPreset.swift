//
//  ExpertEqualizerPreset.swift
//  eqMac
//

import Foundation
import SwiftyUserDefaults

enum ExpertEqualizerPresetBandFilterType: String, Codable {
  case peak = "PK"
  case lowShelf = "LS"
  case highShelf = "HS"
  case lowPass = "LP"
  case highPass = "HP"
}

struct ExpertEqualizerPresetBand: Codable, DefaultsSerializable, Equatable {
  let enabled: Bool
  let filterType: ExpertEqualizerPresetBandFilterType
  let frequency: Double
  let gain: Double
  let q: Double

  static func == (lhs: ExpertEqualizerPresetBand, rhs: ExpertEqualizerPresetBand) -> Bool {
    return lhs.enabled == rhs.enabled &&
      lhs.filterType == rhs.filterType &&
      lhs.frequency == rhs.frequency &&
      lhs.gain == rhs.gain &&
      lhs.q == rhs.q
  }
}

struct ExpertEqualizerPreset: Codable, DefaultsSerializable {
  let id: String
  let name: String
  let isDefault: Bool
  let global: Double
  let bands: [ExpertEqualizerPresetBand]
}

struct ExpertEqualizerPresetGroup: Codable, DefaultsSerializable {
  let id: String
  let name: String
  let presets: [ExpertEqualizerPreset]
}

let EXPERT_EQUALIZER_DEFAULT_BANDS: [ExpertEqualizerPresetBand] = [
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 32, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 64, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 125, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 250, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 500, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 1000, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 2000, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 4000, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 8000, gain: 0, q: 1),
  ExpertEqualizerPresetBand(enabled: true, filterType: .peak, frequency: 16000, gain: 0, q: 1),
]

let EXPERT_EQUALIZER_DEFAULT_PRESETS: [ExpertEqualizerPreset] = [
  ExpertEqualizerPreset(
    id: "flat",
    name: "Flat",
    isDefault: true,
    global: 0,
    bands: EXPERT_EQUALIZER_DEFAULT_BANDS
  ),
]
