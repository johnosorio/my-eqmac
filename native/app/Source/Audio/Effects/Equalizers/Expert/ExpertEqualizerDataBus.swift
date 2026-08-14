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

    self.on(.GET, "/settings") { _, _ in
      return JSON([
        "showDefaultPresets": self.state.showDefaultPresets
      ])
    }

    self.on(.POST, "/settings") { data, _ in
      let show = data["showDefaultPresets"] as? Bool ?? data["show"] as? Bool
      if (show == nil) {
        throw "Invalid 'showDefaultPresets' parameter. Must be a boolean."
      }

      Application.dispatchAction(ExpertEqualizerAction.setShowDefaultPresets(show!))
      return "Expert Equalizer Settings have been set"
    }

    self.on(.GET, "/settings/show-default-presets") { _, _ in
      return [ "show": self.state.showDefaultPresets ]
    }

    self.on(.POST, "/settings/show-default-presets") { data, _ in
      let show = data["show"] as? Bool
      if (show == nil) {
        throw "Invalid 'show' parameter. Must be a boolean."
      }

      Application.dispatchAction(ExpertEqualizerAction.setShowDefaultPresets(show!))
      return "Expert Equalizer Settings have been set"
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

    self.on(.GET, "/presets/export") { data, res in
      File.save(extensions: ["json"]) { file in
        if file != nil {
          let presets = JSON(ExpertEqualizer.userPresets.map { $0.dictionary })
          let json = presets.rawString()!
          do {
            try json.write(to: file!, atomically: true, encoding: .utf8)
            res.send(JSON("Exported \(presets.count) Presets"))
          } catch {
            res.error("Something went wrong")
          }
        } else {
          res.error("Cancelled")
        }
      }
      return nil
    }

    self.on(.GET, "/presets/import") { data, res in
      File.select() { file in
        if file == nil {
          res.error("No file selected")
          return
        }
        if file!.pathExtension != "json" {
          res.error("Invalid File format, must be a JSON")
          return
        }

        if let json = try? String(contentsOf: file!) {
          let presets = JSON(parseJSON: json).arrayValue
          var imported = 0
          for preset in presets {
            if let name = preset["name"].string, let payload = try? self.getPresetPayload(preset) {
              if preset["id"].string == "manual" {
                ExpertEqualizer.updatePreset(id: "manual", global: payload.global, bands: payload.bands)
              } else {
                _ = ExpertEqualizer.createPreset(name: name, global: payload.global, bands: payload.bands)
              }
              imported += 1
            }
          }
          res.send(JSON("Imported \(imported) Presets"))
        } else {
          res.error("File is not readable format.")
        }
      }
      return nil
    }

    presetsChangedListener = ExpertEqualizer.presetsChanged.on { presets in
      self.send(to: "/presets", data: JSON(ExpertEqualizer.presets.map { $0.dictionary }))
    }

    selectedPresetChangedListener = ExpertEqualizer.selectedPresetChanged.on { preset in
      self.send(to: "/presets/selected", data: JSON(preset.dictionary))
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
      try validate(global: global, bands: bands)
      return (global, bands)
    }

    if let gains = data["gains"] as? [String: Any],
       let global = gains["global"] as? Double,
       let bandsData = gains["bands"] as? [[String: Any]] {
      let bands = try bandsData.map { try getBand($0) }
      try validate(global: global, bands: bands)
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

  private func validate(global: Double, bands: [ExpertEqualizerPresetBand]) throws {
    if bands.isEmpty || bands.count > ExpertEqualizer.maximumBands {
      throw "Invalid 'bands' parameter, must contain between 1 and \(ExpertEqualizer.maximumBands) bands"
    }
    if !(-24.0...24.0).contains(global) {
      throw "Invalid 'global' parameter, must be between -24.0 and 24.0"
    }
  }
}
