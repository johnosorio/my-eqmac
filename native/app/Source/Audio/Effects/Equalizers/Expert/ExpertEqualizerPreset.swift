//
//  ExpertEqualizerPreset.swift
//  eqMac
//

import Foundation
import SwiftyUserDefaults

let EXPERT_EQUALIZER_MAXIMUM_BANDS = 100

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

let EXPERT_EQUALIZER_DEFAULT_BANDS: [ExpertEqualizerPresetBand] = (0..<EXPERT_EQUALIZER_MAXIMUM_BANDS).map { index in
  let range = Double(EXPERT_EQUALIZER_MAXIMUM_BANDS - 1)
  let position = Double(index) / range
  let frequency = 20 * pow(1000, position)
  return ExpertEqualizerPresetBand(
    enabled: false,
    filterType: .peak,
    frequency: frequency,
    gain: 0,
    q: 1
  )
}

let EXPERT_EQUALIZER_DEFAULT_PRESETS: [ExpertEqualizerPreset] = [
  ExpertEqualizerPreset(
    id: "flat",
    name: "Flat",
    isDefault: true,
    global: 0,
    bands: EXPERT_EQUALIZER_DEFAULT_BANDS
  ),
]
