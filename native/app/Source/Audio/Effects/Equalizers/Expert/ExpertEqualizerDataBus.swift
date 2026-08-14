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

    self.on(.GET, "/presets/groups") { _, _ in
      let groups = [
        ExpertEqualizerPresetGroup(
          id: "user",
          name: "User",
          presets: ExpertEqualizer.userPresets
        ),
        ExpertEqualizerPresetGroup(
          id: "default",
          name: "Default",
          presets: ExpertEqualizer.defaultPresets
        )
      ]
      return JSON(groups.map { $0.dictionary })
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
        ExpertEqualizer.updatePreset(id: id, global: payload.global, bands: payload.bands, channels: payload.channels)
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
        let preset = ExpertEqualizer.createPreset(
          name: name!,
          global: payload.global,
          bands: payload.bands,
          channels: payload.channels
        )
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

    self.on(.GET, "/bands") { _, _ in
      return JSON(ExpertEqualizer.getSelectedPreset().bands.map { $0.dictionary })
    }

    self.on(.POST, "/bands") { data, _ in
      let preset = ExpertEqualizer.getSelectedPreset()
      if preset.bands.count >= ExpertEqualizer.maximumBands {
        throw "Cannot add more than \(ExpertEqualizer.maximumBands) Expert Equalizer bands"
      }
      let band = try self.getBand(data)
      return JSON(ExpertEqualizer.addBandToSelectedPreset(band).dictionary)
    }

    self.on(.POST, "/bands/update") { data, _ in
      let index = try self.getBandIndex(data)
      let band = try self.getBandValue(data["band"])
      return JSON(ExpertEqualizer.updateBandInSelectedPreset(index: index, band: band).dictionary)
    }

    self.on(.DELETE, "/bands") { data, _ in
      let index = try self.getBandIndex(data)
      let preset = ExpertEqualizer.getSelectedPreset()
      if preset.bands.count <= 1 {
        throw "Cannot remove the last Expert Equalizer band"
      }
      return JSON(ExpertEqualizer.deleteBandFromSelectedPreset(index: index).dictionary)
    }

    self.on(.POST, "/global") { data, _ in
      let global = data["global"] as? Double
      if (global == nil) {
        throw "Invalid 'global' parameter, must be a Double"
      }
      if !(-24.0...24.0).contains(global!) {
        throw "Invalid 'global' parameter, must be between -24.0 and 24.0"
      }
      return JSON(ExpertEqualizer.setSelectedGlobalGain(global!).dictionary)
    }

    self.on(.POST, "/auto-gain") { _, _ in
      return JSON(ExpertEqualizer.autoGainSelectedPreset().dictionary)
    }

    self.on(.GET, "/response") { _, _ in
      return JSON(self.getResponse(preset: ExpertEqualizer.getSelectedPreset()))
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
        if !["json", "txt"].contains(file!.pathExtension.lowercased()) {
          res.error("Invalid File format, must be a JSON or TXT")
          return
        }

        if let content = try? String(contentsOf: file!) {
          do {
            let imported = try self.importPresets(from: content, fileExtension: file!.pathExtension)
            res.send(JSON("Imported \(imported) Presets"))
          } catch {
            res.error("\(error)")
          }
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

  private func importPresets(from content: String, fileExtension: String) throws -> Int {
    if fileExtension.lowercased() == "txt" {
      let preset = try parseTextPreset(content)
      let importedPreset = ExpertEqualizer.createPreset(
        name: preset.name,
        global: preset.global,
        bands: preset.bands,
        channels: preset.channels
      )
      Application.dispatchAction(ExpertEqualizerAction.selectPreset(importedPreset.id, true))
      return 1
    }

    let presets = JSON(parseJSON: content).arrayValue
    var imported = 0
    var lastImportedPresetId: String?
    for preset in presets {
      if let name = preset["name"].string, let payload = try? self.getPresetPayload(preset) {
        if preset["id"].string == "manual" {
          ExpertEqualizer.updatePreset(id: "manual", global: payload.global, bands: payload.bands, channels: payload.channels)
          lastImportedPresetId = "manual"
        } else {
          let importedPreset = ExpertEqualizer.createPreset(
            name: name,
            global: payload.global,
            bands: payload.bands,
            channels: payload.channels
          )
          lastImportedPresetId = importedPreset.id
        }
        imported += 1
      }
    }
    if let presetId = lastImportedPresetId {
      Application.dispatchAction(ExpertEqualizerAction.selectPreset(presetId, true))
    }
    return imported
  }

  private func parseTextPreset(
    _ content: String
  ) throws -> (name: String, global: Double, bands: [ExpertEqualizerPresetBand], channels: [String: [ExpertEqualizerPresetBand]]?) {
    var name: String?
    var global: Double?
    var bands: [ExpertEqualizerPresetBand] = []
    var channelBands: [String: [ExpertEqualizerPresetBand]] = [:]
    var currentChannel: String?

    for rawLine in content.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty {
        continue
      }

      if line.lowercased().hasPrefix("name:") {
        name = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        continue
      }

      if line.lowercased().hasPrefix("preamp:") {
        global = try readRequiredDouble(line, pattern: #"(?i)^preamp:\s*([-+]?\d+(?:[.,]\d+)?)\s*dB"#, description: "Preamp")
        continue
      }

      if line.lowercased().hasPrefix("channel:") {
        currentChannel = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if currentChannel!.isEmpty {
          throw "Invalid 'Channel' parameter"
        }
        if channelBands[currentChannel!] == nil {
          channelBands[currentChannel!] = []
        }
        continue
      }

      if line.lowercased().hasPrefix("filter ") {
        if let channel = currentChannel {
          let band = try parseTextPresetBand(line, index: channelBands[channel]?.count ?? 0)
          channelBands[channel, default: []].append(band)
        } else {
          let band = try parseTextPresetBand(line, index: bands.count)
          bands.append(band)
        }
      }
    }

    if name == nil || name!.isEmpty {
      throw "Missing 'Name' line"
    }
    if global == nil {
      throw "Missing 'Preamp' line"
    }

    if !channelBands.isEmpty {
      let activeChannels = try validateChannelBands(channelBands)
      bands = activeChannels["L"] ?? activeChannels["LEFT"] ?? activeChannels.sorted(by: { $0.key < $1.key }).first!.value
      return (name!, global!, bands, activeChannels)
    }

    try validate(global: global!, bands: bands)
    return (name!, global!, bands, nil)
  }

  private func validateChannelBands(_ channelBands: [String: [ExpertEqualizerPresetBand]]) throws -> [String: [ExpertEqualizerPresetBand]] {
    let activeChannels = channelBands.filter { !$0.value.isEmpty }
    if activeChannels.isEmpty {
      throw "Invalid 'Channel' parameter, no filters were provided"
    }
    for (_, bands) in activeChannels {
      try validate(global: 0, bands: bands)
    }
    return activeChannels
  }

  private func parseTextPresetBand(_ line: String, index: Int) throws -> ExpertEqualizerPresetBand {
    let enabledValue = try readRequiredString(
      line,
      pattern: #"(?i)^filter\s+\d+:\s*(ON|OFF)\s+"#,
      description: "Filter enabled"
    )
    let typeValue = try readRequiredString(
      line,
      pattern: #"(?i)^filter\s+\d+:\s*(?:ON|OFF)\s+([A-Z]{2})\s+"#,
      description: "Filter type"
    ).uppercased()
    let frequency = try readRequiredDouble(
      line,
      pattern: #"(?i)\bFc\s+([-+]?\d+(?:[.,]\d+)?)\s*Hz\b"#,
      description: "Fc"
    )
    let gain = try readRequiredDouble(
      line,
      pattern: #"(?i)\bGain\s+([-+]?\d+(?:[.,]\d+)?)\s*dB\b"#,
      description: "Gain"
    )
    let q = readDouble(
      line,
      pattern: #"(?i)\bQ\s+([-+]?\d+(?:[.,]\d+)?)\b"#
    ) ?? 1

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
      enabled: enabledValue.uppercased() == "ON",
      filterType: filterType,
      frequency: frequency,
      gain: gain,
      q: q,
      color: EXPERT_EQUALIZER_BAND_COLORS[index % EXPERT_EQUALIZER_BAND_COLORS.count]
    )
  }

  private func getPresetPayload (
    _ data: JSON?
  ) throws -> (global: Double, bands: [ExpertEqualizerPresetBand], channels: [String: [ExpertEqualizerPresetBand]]?) {
    if let global = data["global"] as? Double, let bandsData = data["bands"] as? [[String: Any]] {
      let bands = try bandsData.map { try getBand($0) }
      let channels = try getChannels(data)
      try validate(global: global, bands: bands)
      return (global, bands, channels)
    }

    if let gains = data["gains"] as? [String: Any],
       let global = gains["global"] as? Double,
       let bandsData = gains["bands"] as? [[String: Any]] {
      let bands = try bandsData.map { try getBand($0) }
      let channels = try getChannels(data)
      try validate(global: global, bands: bands)
      return (global, bands, channels)
    }

    throw "Invalid 'bands' parameter, must be an array of ExpertEqualizerPresetBand"
  }

  private func getChannels(_ data: JSON?) throws -> [String: [ExpertEqualizerPresetBand]]? {
    guard let channelsData = data["channels"] as? [String: Any] else {
      return nil
    }
    var channels: [String: [ExpertEqualizerPresetBand]] = [:]
    for (key, value) in channelsData {
      guard let bandsData = value as? [[String: Any]] else {
        throw "Invalid 'channels' parameter, channel values must be arrays of ExpertEqualizerPresetBand"
      }
      channels[key.uppercased()] = try bandsData.map { try getBand($0) }
    }
    return try validateChannelBands(channels)
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
    let color = data["color"] as? String ?? EXPERT_EQUALIZER_BAND_COLORS[0]
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
    if !isValidColor(color) {
      throw "Invalid 'color' parameter, must be a hex color"
    }

    return ExpertEqualizerPresetBand(
      enabled: enabled,
      filterType: filterType,
      frequency: frequency,
      gain: gain,
      q: q,
      color: color
    )
  }

  private func getBand (_ data: JSON?) throws -> ExpertEqualizerPresetBand {
    if let bandData = data?.dictionaryObject {
      return try getBand(bandData)
    }
    throw "Invalid 'band' parameter, must be an ExpertEqualizerPresetBand"
  }

  private func getBandValue (_ data: Any?) throws -> ExpertEqualizerPresetBand {
    if let bandData = data as? [String: Any] {
      return try getBand(bandData)
    }
    if let bandJson = data as? JSON {
      return try getBand(bandJson)
    }
    throw "Invalid 'band' parameter, must be an ExpertEqualizerPresetBand"
  }

  private func getBandIndex (_ data: JSON?) throws -> Int {
    let index = data["index"] as? Int
    if (index == nil) {
      throw "Invalid 'index' parameter, must be an Int"
    }
    let preset = ExpertEqualizer.getSelectedPreset()
    if !(0..<preset.bands.count).contains(index!) {
      throw "Invalid 'index' parameter, must reference an existing Expert Equalizer band"
    }
    return index!
  }

  private func readRequiredString(_ text: String, pattern: String, description: String) throws -> String {
    if let value = readString(text, pattern: pattern) {
      return value
    }
    throw "Invalid '\(description)' parameter"
  }

  private func readRequiredDouble(_ text: String, pattern: String, description: String) throws -> Double {
    if let value = readDouble(text, pattern: pattern) {
      return value
    }
    throw "Invalid '\(description)' parameter"
  }

  private func readDouble(_ text: String, pattern: String) -> Double? {
    if let value = readString(text, pattern: pattern) {
      return Double(value.replacingOccurrences(of: ",", with: "."))
    }
    return nil
  }

  private func readString(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
      return nil
    }
    guard let valueRange = Range(match.range(at: 1), in: text) else {
      return nil
    }
    return String(text[valueRange])
  }

  private func isValidColor(_ color: String) -> Bool {
    return color.range(
      of: "^#[0-9A-Fa-f]{6}$",
      options: .regularExpression
    ) != nil
  }

  private func validate(global: Double, bands: [ExpertEqualizerPresetBand]) throws {
    if bands.isEmpty || bands.count > ExpertEqualizer.maximumBands {
      throw "Invalid 'bands' parameter, must contain between 1 and \(ExpertEqualizer.maximumBands) bands"
    }
    if !(-24.0...24.0).contains(global) {
      throw "Invalid 'global' parameter, must be between -24.0 and 24.0"
    }
  }

  private func getResponse(preset: ExpertEqualizerPreset) -> [String: Any] {
    let points = (0..<240).map { index -> [String: Any] in
      let frequency = 20 * pow(1000, Double(index) / 239)
      let bandResponses = preset.bands.map { band -> Double in
        return responseGain(frequency: frequency, band: band)
      }
      let total = bandResponses.reduce(preset.global, +)
      return [
        "frequency": frequency,
        "gain": clamp(total, min: -36, max: 36),
        "bands": bandResponses.map { clamp($0, min: -36, max: 36) }
      ]
    }
    return [
      "global": preset.global,
      "points": points
    ]
  }

  private func responseGain(frequency: Double, band: ExpertEqualizerPresetBand) -> Double {
    if !band.enabled {
      return 0
    }
    let ratio = max(frequency, 20) / max(band.frequency, 20)
    let distance = log2(ratio)
    let width = max(0.05, bandwidthOctaves(forQ: band.q))
    switch band.filterType {
    case .peak:
      return band.gain / (1 + pow(distance / width, 2))
    case .lowShelf:
      return band.gain / (1 + pow(2, distance / width))
    case .highShelf:
      return band.gain / (1 + pow(2, -distance / width))
    case .lowPass:
      return -24 * max(0, distance / width)
    case .highPass:
      return -24 * max(0, -distance / width)
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
}
