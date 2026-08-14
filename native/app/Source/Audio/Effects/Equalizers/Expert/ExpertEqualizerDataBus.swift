//
//  ExpertEqualizerDataBus.swift
//  eqMac
//

import Foundation
import SwiftyJSON
import EmitterKit

class ExpertEqualizerDataBus: DataBus {
  var state: ExpertEqualizerState {
    return Application.store.state.effects.equalizers.expert
  }
  var presetsChangedListener: EventListener<[ExpertEqualizerPreset]>?
  var selectedPresetChangedListener: EventListener<ExpertEqualizerPreset>?

  required init (route: String, bridge: Bridge) {
    super.init(
      route: route,
      bridge: bridge
    )

    self.on(.GET, "/presets") { _, _ in
      return JSON(ExpertEqualizer.presets.map { $0.dictionary })
    }

    self.on(.GET, "/presets/selected") { _, _ in
      let preset = ExpertEqualizer.getPreset(id: self.state.selectedPresetId)
      return JSON(preset!.dictionary)
    }

    self.on(.POST, "/presets") { data, _ in
      let payload = try self.getPresetPayload(data)
      if let id = data["id"] as? String {
        if (ExpertEqualizer.defaultPresets.contains { $0.id == id }) {
          throw "Default Presets aren't updatable."
        }
        ExpertEqualizer.updatePreset(id: id, global: payload.global, bands: payload.bands)
        let select = data["select"] as? Bool
        if select == true {
          let transition = data["transition"] as? Bool
          Application.dispatchAction(ExpertEqualizerAction.selectPreset(id, transition ?? false))
        }
        return "Expert Equalizer Preset has been updated"
      } else {
        let name = data["name"] as? String
        if (name == nil) {
          throw "Invalid 'name' parameter, must be a String"
        }
        let preset = ExpertEqualizer.createPreset(name: name!, global: payload.global, bands: payload.bands)
        let select = data["select"] as? Bool
        if select == true {
          let transition = data["transition"] as? Bool
          Application.dispatchAction(ExpertEqualizerAction.selectPreset(preset.id, transition ?? false))
        }
        return JSON(preset.dictionary)
      }
    }

    self.on(.POST, "/presets/select") { data, _ in
      let preset = try self.getPreset(data)
      Application.dispatchAction(ExpertEqualizerAction.selectPreset(preset.id, true))
      return "Expert Equalizer Preset has been set."
    }

    self.on(.DELETE, "/presets") { data, _ in
      let preset = try self.getPreset(data)
      if (preset.isDefault) {
        throw "Default Presets aren't removable."
      }

      ExpertEqualizer.deletePreset(preset)
      Application.dispatchAction(ExpertEqualizerAction.selectPreset("flat", true))
      return "Expert Equalizer Preset has been deleted."
    }

    presetsChangedListener = ExpertEqualizer.presetsChanged.on { presets in
      self.send(to: "/presets", data: JSON(ExpertEqualizer.presets.map { $0.dictionary }))
    }
  }

  private func getPreset (_ data: JSON?) throws -> ExpertEqualizerPreset {
    if let id = data["id"] as? String {
      if let preset = ExpertEqualizer.getPreset(id: id) {
        return preset
      } else {
        throw "Could not find Preset with this ID"
      }
    } else {
      throw "Please provide a preset ID"
    }
  }

  private func getPresetPayload (_ data: JSON?) throws -> (global: Double, bands: [ExpertEqualizerPresetBand]) {
    if let global = data["global"] as? Double, let bandsData = data["bands"] as? [[String: Any]] {
      let bands = try bandsData.map { try getBand($0) }
      if bands.isEmpty || bands.count > ExpertEqualizer.maximumBands {
        throw "Invalid 'bands' parameter, must contain between 1 and \(ExpertEqualizer.maximumBands) bands"
      }
      if !(-24.0...24.0).contains(global) {
        throw "Invalid 'global' parameter, must be between -24.0 and 24.0"
      }
      return (global, bands)
    }

    if let gains = data["gains"] as? [String: Any],
       let global = gains["global"] as? Double,
       let bandsData = gains["bands"] as? [[String: Any]] {
      let bands = try bandsData.map { try getBand($0) }
      return (global, bands)
    }

    throw "Invalid 'bands' parameter, must be an array of ExpertEqualizerPresetBand"
  }

  private func getBand (_ data: [String: Any]) throws -> ExpertEqualizerPresetBand {
    guard let frequency = data["frequency"] as? Double else {
      throw "Invalid 'frequency' parameter, must be a Double"
    }
    guard let gain = data["gain"] as? Double else {
      throw "Invalid 'gain' parameter, must be a Double"
    }

    let enabled = data["enabled"] as? Bool ?? true
    let q = data["q"] as? Double ?? 1
    let typeValue = data["filterType"] as? String ?? data["type"] as? String ?? ExpertEqualizerPresetBandFilterType.peak.rawValue

    guard let filterType = ExpertEqualizerPresetBandFilterType(rawValue: typeValue) else {
      throw "Invalid 'filterType' parameter"
    }
    if !(20.0...20000.0).contains(frequency) {
      throw "Invalid 'frequency' parameter, must be between 20.0 and 20000.0"
    }
    if !(-24.0...24.0).contains(gain) {
      throw "Invalid 'gain' parameter, must be between -24.0 and 24.0"
    }
    if !(0.1...24.0).contains(q) {
      throw "Invalid 'q' parameter, must be between 0.1 and 24.0"
    }

    return ExpertEqualizerPresetBand(
      enabled: enabled,
      filterType: filterType,
      frequency: frequency,
      gain: gain,
      q: q
    )
  }
}
