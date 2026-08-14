//
//  ExpertEqualizerState.swift
//  eqMac
//

import Foundation
import ReSwift

struct ExpertEqualizerState: State {
  var selectedPresetId: String = "flat"
  var transition: Bool = false
}

enum ExpertEqualizerAction: Action {
  case selectPreset(String, Bool)
}

func ExpertEqualizerStateReducer(action: Action, state: ExpertEqualizerState?) -> ExpertEqualizerState {
  var state = state ?? ExpertEqualizerState()

  switch action as? ExpertEqualizerAction {
  case .selectPreset(let id, let transition)?:
    state.selectedPresetId = id
    state.transition = transition
  case .none:
    break
  }

  return state
}
