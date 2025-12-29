enum WordLlmMode {
  enrich,
  tier,
  examples,
  distractors,
}

extension WordLlmModeLabel on WordLlmMode {
  String get label {
    switch (this) {
      case WordLlmMode.enrich:
        return 'Combined (definition + examples + distractors)';
      case WordLlmMode.examples:
        return 'Regenerate Examples';
      case WordLlmMode.distractors:
        return 'Regenerate Distractors';
      case WordLlmMode.tier:
        return 'Auto Tier';
    }
  }
}
