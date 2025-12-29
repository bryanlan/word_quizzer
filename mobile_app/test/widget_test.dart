import 'package:flutter_test/flutter_test.dart';

import 'package:vocab_master/llm_modes.dart';

void main() {
  test('WordLlmMode labels are present', () {
    expect(WordLlmMode.values, hasLength(4));
    for (final mode in WordLlmMode.values) {
      expect(mode.label, isNotEmpty);
    }
  });
}
