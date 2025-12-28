enum WordLlmMode {
  distractors,
  tier,
}

extension WordLlmModeLabel on WordLlmMode {
  String get label {
    switch (this) {
      case WordLlmMode.distractors:
        return 'Regenerate Distractors';
      case WordLlmMode.tier:
        return 'Auto Tier';
    }
  }
}
