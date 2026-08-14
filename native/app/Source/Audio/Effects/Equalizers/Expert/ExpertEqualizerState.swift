//
//  ExpertEqualizerState.swift
//  eqMac
//

import Foundation
import ReSwift
import Shared

struct ExpertEqualizerState: State {
  var selectedPresetId: String = "flat"
  var showDefaultPresets: Bool = true
  var transition: Bool = false
}

enum ExpertEqualizerAction: Action {
  case selectPreset(String, Bool)
  case setShowDefaultPresets(Bool)
}

func ExpertEqualizerStateReducer(action: Action, state: ExpertEqualizerState?) -> ExpertEqualizerState {
  var state = state ?? ExpertEqualizerState()

  switch action as? ExpertEqualizerAction {
  case .selectPreset(let id, let transition)?:
    state.selectedPresetId = id
    state.transition = transition
  case .setShowDefaultPresets(let show)?:
    state.showDefaultPresets = show
    Async.delay(100) {
      ExpertEqualizer.presetsChanged.emit(ExpertEqualizer.presets)
    }
  case .none:
    break
  }

  return state
}
