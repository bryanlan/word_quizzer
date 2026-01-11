import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

typedef SpeechTranscriptCallback = void Function(String transcript);

enum DictationMode {
  webSpeech,
  iosKeyboard,
  unsupported,
}

class SpeechDictation {
  JSObject? _recognition;
  bool _isListening = false;
  final Map<int, String> _finalSegments = {};
  String _interimSegment = '';
  bool _shouldContinue = false;
  bool _startSeen = false;
  Timer? _startTimeout;

  DictationMode get mode => _detectMode();

  bool get usesWebSpeech => mode == DictationMode.webSpeech;

  bool get isSupported {
    return mode != DictationMode.unsupported;
  }

  bool get isListening => _isListening;

  DictationMode _detectMode() {
    final hasWebSpeech = _hasWebSpeech();
    final isIOS = _isIOS();
    final isStandalone = _isStandalone();

    if (isIOS && isStandalone) {
      return DictationMode.iosKeyboard;
    }
    if (!hasWebSpeech) {
      return isIOS ? DictationMode.iosKeyboard : DictationMode.unsupported;
    }
    return DictationMode.webSpeech;
  }

  bool _hasWebSpeech() {
    final windowObj = JSObject.fromInteropObject(html.window);
    return windowObj.has('SpeechRecognition') || windowObj.has('webkitSpeechRecognition');
  }

  bool _isIOS() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  bool _isStandalone() {
    final displayStandalone =
        html.window.matchMedia('(display-mode: standalone)').matches;
    final navObj = JSObject.fromInteropObject(html.window.navigator);
    final standaloneAny = navObj['standalone'];
    final legacyStandalone =
        standaloneAny is JSBoolean ? standaloneAny.toDart : standaloneAny == true;
    return displayStandalone || legacyStandalone;
  }

  Future<bool> requestPermission() async {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      return false;
    }
    try {
      final stream = await mediaDevices.getUserMedia({'audio': true});
      for (final track in stream.getTracks()) {
        track.stop();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void start({
    required SpeechTranscriptCallback onTranscript,
    required void Function(Object error) onError,
    required void Function() onEnd,
    String lang = 'en-US',
  }) {
    if (mode != DictationMode.webSpeech) {
      onError(StateError(_modeErrorMessage()));
      return;
    }

    _disposeRecognition();
    _resetSegments();
    _shouldContinue = true;

    final windowObj = JSObject.fromInteropObject(html.window);
    final ctorAny = windowObj.has('SpeechRecognition')
        ? windowObj['SpeechRecognition']
        : windowObj['webkitSpeechRecognition'];
    if (ctorAny == null) {
      onError(StateError('Speech recognition constructor not found.'));
      return;
    }
    final ctor = ctorAny as JSFunction;
    final recognition = ctor.callAsConstructor<JSObject>();

    _recognition = recognition;
    _isListening = true;
    _startSeen = false;

    recognition['continuous'] = true.toJS;
    recognition['interimResults'] = true.toJS;
    recognition['lang'] = lang.toJS;
    recognition['maxAlternatives'] = 1.toJS;

    recognition['onstart'] = ((JSAny? _) {
      _startSeen = true;
      _startTimeout?.cancel();
    }).toJS;

    recognition['onresult'] = ((JSAny? event) {
      final transcript = _updateTranscript(event);
      if (transcript.isNotEmpty) {
        onTranscript(transcript);
      }
    }).toJS;

    recognition['onerror'] = ((JSAny? event) {
      _shouldContinue = false;
      final message = _extractError(event);
      onError(StateError(_mapErrorMessage(message)));
    }).toJS;

    recognition['onend'] = ((JSAny? _) {
      _isListening = false;
      if (_shouldContinue) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (_shouldContinue && _recognition != null) {
            _startRecognition(onError);
          }
        });
      } else {
        _recognition = null;
        onEnd();
      }
    }).toJS;

    _startRecognition(onError);
  }

  void stop() {
    final recognition = _recognition;
    _isListening = false;
    _shouldContinue = false;
    _startTimeout?.cancel();
    if (recognition == null) {
      return;
    }
    try {
      recognition.callMethod<JSAny?>('stop'.toJS);
    } catch (_) {
      // ignore stop errors
    }
  }

  void abort() {
    final recognition = _recognition;
    _isListening = false;
    _shouldContinue = false;
    _startTimeout?.cancel();
    _recognition = null;
    _resetSegments();
    if (recognition == null) {
      return;
    }
    try {
      recognition.callMethod<JSAny?>('abort'.toJS);
    } catch (_) {
      // ignore abort errors
    }
  }

  void _startRecognition(void Function(Object error) onError) {
    final recognition = _recognition;
    if (recognition == null) {
      return;
    }
    _startTimeout?.cancel();
    _startSeen = false;
    _isListening = true;
    _startTimeout = Timer(const Duration(seconds: 1), () {
      if (!_startSeen) {
        _shouldContinue = false;
        try {
          recognition.callMethod<JSAny?>('abort'.toJS);
        } catch (_) {
          // ignore abort errors
        }
        onError(StateError('Speech recognition failed to start.'));
      }
    });
    try {
      recognition.callMethod<JSAny?>('start'.toJS);
    } catch (e) {
      _shouldContinue = false;
      _isListening = false;
      _recognition = null;
      onError(e);
    }
  }

  void _disposeRecognition() {
    _startTimeout?.cancel();
    final recognition = _recognition;
    _recognition = null;
    _isListening = false;
    if (recognition == null) {
      return;
    }
    try {
      recognition.callMethod<JSAny?>('abort'.toJS);
    } catch (_) {
      // ignore abort errors
    }
  }

  void _resetSegments() {
    _finalSegments.clear();
    _interimSegment = '';
  }

  String _mapErrorMessage(String code) {
    switch (code) {
      case 'not-allowed':
      case 'service-not-allowed':
        return 'Microphone permission denied.';
      case 'no-speech':
        return 'No speech detected. Try again.';
      case 'audio-capture':
        return 'No microphone found.';
      case 'network':
        return 'Speech service error. Check connection.';
      default:
        return 'Speech recognition error: $code';
    }
  }

  String _modeErrorMessage() {
    switch (mode) {
      case DictationMode.iosKeyboard:
        return 'Use the microphone on your keyboard to dictate.';
      case DictationMode.unsupported:
        return 'Dictation is not supported in this browser.';
      case DictationMode.webSpeech:
        return 'Speech recognition not available.';
    }
  }

  String _extractError(JSAny? event) {
    if (event == null) {
      return 'unknown';
    }
    final obj = event as JSObject;
    final value = obj['error'];
    if (value is JSString) {
      final text = value.toDart.trim();
      return text.isEmpty ? 'unknown' : text;
    }
    return value?.toString().trim().isNotEmpty == true ? value.toString() : 'unknown';
  }

  String _updateTranscript(JSAny? event) {
    if (event == null) {
      return '';
    }
    final obj = event as JSObject;
    final resultsAny = obj['results'];
    if (resultsAny == null) {
      return '';
    }
    final results = resultsAny as JSObject;
    final lengthAny = results['length'];
    final length = lengthAny is JSNumber ? lengthAny.toDartInt : 0;
    final resultIndexAny = obj['resultIndex'];
    final startIndex = resultIndexAny is JSNumber ? resultIndexAny.toDartInt : 0;

    _interimSegment = '';

    for (var i = startIndex; i < length; i++) {
      final resultAny = results.getProperty<JSAny?>(i.toJS);
      if (resultAny == null) continue;
      final result = resultAny as JSObject;
      final altAny = result.getProperty<JSAny?>(0.toJS);
      if (altAny == null) continue;
      final alt = altAny as JSObject;
      final transcriptAny = alt['transcript'];
      final transcript =
          transcriptAny is JSString ? transcriptAny.toDart : transcriptAny?.toString();
      final trimmed = transcript?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        final isFinalAny = result['isFinal'];
        final isFinal =
            isFinalAny is JSBoolean ? isFinalAny.toDart : isFinalAny == true;
        if (isFinal) {
          _finalSegments[i] = trimmed;
        } else {
          _interimSegment = trimmed;
        }
      }
    }

    final orderedKeys = _finalSegments.keys.toList()..sort();
    final parts = <String>[
      for (final key in orderedKeys) _finalSegments[key]!,
      if (_interimSegment.isNotEmpty) _interimSegment,
    ];
    return parts.join(' ').replaceAll(RegExp(r'\\s+'), ' ').trim();
  }
}
