typedef SpeechTranscriptCallback = void Function(String transcript);

enum DictationMode {
  webSpeech,
  iosKeyboard,
  unsupported,
}

class SpeechDictation {
  DictationMode get mode => DictationMode.unsupported;
  bool get isSupported => false;
  bool get usesWebSpeech => false;
  bool get isListening => false;

  Future<bool> requestPermission() async => false;

  void start({
    required SpeechTranscriptCallback onTranscript,
    required void Function(Object error) onError,
    required void Function() onEnd,
    String lang = 'en-US',
  }) {}

  void stop() {}

  void abort() {}
}
