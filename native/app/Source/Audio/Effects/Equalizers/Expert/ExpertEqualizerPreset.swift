//
//  ExpertEqualizerPreset.swift
//  eqMac
//

import Foundation
import SwiftyUserDefaults

let EXPERT_EQUALIZER_MAXIMUM_BANDS = 100
let EXPERT_EQUALIZER_BAND_COLORS = [
  "#00E0A4",
  "#FFB020",
  "#FFE600",
  "#A7F432",
  "#1DFF42",
  "#15E67A",
  "#28D7F0",
  "#3E51FF",
  "#6B2CFF",
  "#FF4E6A",
]

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
  let color: String

  init(
    enabled: Bool,
    filterType: ExpertEqualizerPresetBandFilterType,
    frequency: Double,
    gain: Double,
    q: Double,
    color: String = EXPERT_EQUALIZER_BAND_COLORS[0]
  ) {
    self.enabled = enabled
    self.filterType = filterType
    self.frequency = frequency
    self.gain = gain
    self.q = q
    self.color = color
  }

  enum CodingKeys: String, CodingKey {
    case enabled
    case filterType
    case frequency
    case gain
    case q
    case color
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decode(Bool.self, forKey: .enabled)
    filterType = try container.decode(ExpertEqualizerPresetBandFilterType.self, forKey: .filterType)
    frequency = try container.decode(Double.self, forKey: .frequency)
    gain = try container.decode(Double.self, forKey: .gain)
    q = try container.decode(Double.self, forKey: .q)
    color = try container.decodeIfPresent(String.self, forKey: .color) ?? EXPERT_EQUALIZER_BAND_COLORS[0]
  }

  static func == (lhs: ExpertEqualizerPresetBand, rhs: ExpertEqualizerPresetBand) -> Bool {
    return lhs.enabled == rhs.enabled &&
      lhs.filterType == rhs.filterType &&
      lhs.frequency == rhs.frequency &&
      lhs.gain == rhs.gain &&
      lhs.q == rhs.q &&
      lhs.color == rhs.color
  }
}

struct ExpertEqualizerPreset: Codable, DefaultsSerializable {
  let id: String
  let name: String
  let isDefault: Bool
  let global: Double
  let bands: [ExpertEqualizerPresetBand]
  let channels: [String: [ExpertEqualizerPresetBand]]?

  init(
    id: String,
    name: String,
    isDefault: Bool,
    global: Double,
    bands: [ExpertEqualizerPresetBand],
    channels: [String: [ExpertEqualizerPresetBand]]? = nil
  ) {
    self.id = id
    self.name = name
    self.isDefault = isDefault
    self.global = global
    self.bands = bands
    self.channels = channels
  }
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
    q: 1,
    color: EXPERT_EQUALIZER_BAND_COLORS[index % EXPERT_EQUALIZER_BAND_COLORS.count]
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
