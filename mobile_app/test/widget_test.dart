import 'package:flutter_test/flutter_test.dart';

import 'package:vocab_master/llm_modes.dart';

void main() {
  test('WordLlmMode labels are present', () {
    expect(WordLlmMode.values, hasLength(2));
    expect(WordLlmMode.distractors.label, isNotEmpty);
    expect(WordLlmMode.tier.label, isNotEmpty);
  });
}
