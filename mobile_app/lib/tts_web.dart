import 'dart:async';
import 'dart:html' as html;
import 'tts_service.dart';

Future<List<TtsVoice>> getWebVoices() async {
  List<TtsVoice> mapVoices(List<html.SpeechSynthesisVoice> voices) {
    return voices
        .where((voice) => voice.name != null && voice.name!.trim().isNotEmpty)
        .map((voice) => TtsVoice(
              name: voice.name ?? '',
              locale: voice.lang ?? '',
              raw: {
                'name': voice.name ?? '',
                'locale': voice.lang ?? '',
              },
            ))
        .toList();
  }

  final synthesis = html.window.speechSynthesis;
  if (synthesis == null) {
    return [];
  }

  var voices = synthesis.getVoices();
  if (voices.isNotEmpty) {
    return mapVoices(voices);
  }

  final completer = Completer<List<TtsVoice>>();
  var attempts = 0;
  Timer? timer;
  timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    attempts += 1;
    final updated = synthesis.getVoices();
    if (updated.isNotEmpty) {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.complete(mapVoices(updated));
      }
      return;
    }
    if (attempts >= 10) {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.complete(mapVoices(updated));
      }
    }
  });

  return completer.future;
}
