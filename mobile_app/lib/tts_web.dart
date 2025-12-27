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
  late StreamSubscription<html.Event> sub;
  sub = synthesis.onVoicesChanged.listen((_) {
    final updated = synthesis.getVoices();
    if (updated.isNotEmpty && !completer.isCompleted) {
      completer.complete(mapVoices(updated));
    }
  });

  Future.delayed(const Duration(seconds: 2)).then((_) {
    if (!completer.isCompleted) {
      completer.complete(mapVoices(synthesis.getVoices()));
    }
  });

  final result = await completer.future;
  await sub.cancel();
  return result;
}
