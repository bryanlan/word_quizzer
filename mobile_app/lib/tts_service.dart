import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsVoice {
  final String name;
  final String locale;
  final Map<String, dynamic> raw;

  TtsVoice({
    required this.name,
    required this.locale,
    required this.raw,
  });

  String get key => '$name|$locale';

  String get label {
    if (locale.isEmpty) {
      return name;
    }
    return '$name ($locale)';
  }

  Map<String, String> toVoiceMap() {
    return {
      'name': name,
      'locale': locale,
    };
  }
}

class TtsService {
  static const String voiceKey = 'tts_voice';
  static const String _defaultLocale = 'en-US';

  static Future<void> configure(FlutterTts tts) async {
    await tts.setSpeechRate(0.5);
    final voices = await getVoices(tts);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(voiceKey);
    TtsVoice? selected;
    if (saved != null && saved.isNotEmpty) {
      selected = voices.firstWhere(
        (voice) => voice.key == saved,
        orElse: () => _selectBestVoice(voices) ?? voices.first,
      );
    } else {
      selected = _selectBestVoice(voices);
    }
    if (selected == null) {
      await tts.setLanguage(_defaultLocale);
      return;
    }
    if (selected.locale.isNotEmpty) {
      await tts.setLanguage(selected.locale);
    } else {
      await tts.setLanguage(_defaultLocale);
    }
    await tts.setVoice(selected.toVoiceMap());
  }

  static Future<List<TtsVoice>> getVoices(FlutterTts tts) async {
    final raw = await tts.getVoices;
    final voices = <TtsVoice>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          final name = (entry['name'] ?? entry['voice'] ?? '').toString().trim();
          final locale = (entry['locale'] ?? entry['language'] ?? '').toString().trim();
          if (name.isEmpty) {
            continue;
          }
          voices.add(TtsVoice(name: name, locale: locale, raw: Map<String, dynamic>.from(entry)));
        }
      }
    }
    if (voices.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 200));
      final retry = await tts.getVoices;
      if (retry is List) {
        for (final entry in retry) {
          if (entry is Map) {
            final name = (entry['name'] ?? entry['voice'] ?? '').toString().trim();
            final locale = (entry['locale'] ?? entry['language'] ?? '').toString().trim();
            if (name.isEmpty) {
              continue;
            }
            voices.add(TtsVoice(name: name, locale: locale, raw: Map<String, dynamic>.from(entry)));
          }
        }
      }
    }
    final deduped = <String, TtsVoice>{};
    for (final voice in voices) {
      deduped[voice.key] = voice;
    }
    final list = deduped.values.toList();
    list.sort((a, b) => a.label.compareTo(b.label));
    return list;
  }

  static TtsVoice? _selectBestVoice(List<TtsVoice> voices) {
    if (voices.isEmpty) {
      return null;
    }
    final candidates = voices.where((voice) {
      final locale = voice.locale.toLowerCase();
      return locale.startsWith('en') || locale.isEmpty;
    }).toList();
    final pool = candidates.isEmpty ? voices : candidates;
    TtsVoice? best;
    var bestScore = -999;
    for (final voice in pool) {
      final score = _scoreVoice(voice);
      if (score > bestScore) {
        bestScore = score;
        best = voice;
      }
    }
    return best;
  }

  static int _scoreVoice(TtsVoice voice) {
    final name = voice.name.toLowerCase();
    final locale = voice.locale.toLowerCase();
    var score = 0;
    if (locale == 'en-us') {
      score += 3;
    }
    if (name.contains('neural') || name.contains('wavenet') || name.contains('enhanced')) {
      score += 5;
    }
    if (name.contains('premium')) {
      score += 3;
    }
    if (name.contains('google')) {
      score += 2;
    }
    if (name.contains('compact') || name.contains('low')) {
      score -= 2;
    }
    return score;
  }
}
