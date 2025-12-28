enum WordLlmMode {
  full,
  definition,
  examples,
  distractors,
  tier,
}

extension WordLlmModeLabel on WordLlmMode {
  String get label {
    switch (this) {
      case WordLlmMode.full:
        return 'Full Refresh';
      case WordLlmMode.definition:
        return 'Definition';
      case WordLlmMode.examples:
        return 'Examples';
      case WordLlmMode.distractors:
        return 'Distractors';
      case WordLlmMode.tier:
        return 'Tier';
    }
  }
}
