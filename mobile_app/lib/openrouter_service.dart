import 'dart:convert';
import 'package:http/http.dart' as http;

class InvalidApiKeyException implements Exception {
  final String message;
  InvalidApiKeyException([this.message = 'Invalid API key']);
}

class OpenRouterResult {
  final String definition;
  final List<String> examples;
  final List<String> distractors;

  OpenRouterResult({
    required this.definition,
    required this.examples,
    required this.distractors,
  });
}

class OpenRouterService {
  final String apiKey;

  OpenRouterService(this.apiKey);

  Future<void> testKey() async {
    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'google/gemini-3-flash-preview',
        'messages': [
          {
            'role': 'user',
            'content': 'Reply with JSON: {"ok": true}. No other text.',
          }
        ],
        'max_tokens': 50,
        'reasoning': {'enabled': true},
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw InvalidApiKeyException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OpenRouter error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      final error = decoded['error'] as Map<String, dynamic>? ?? {};
      final message = (error['message'] ?? '').toString();
      if (message.toLowerCase().contains('key')) {
        throw InvalidApiKeyException(message);
      }
      throw Exception(message.isEmpty ? 'OpenRouter error' : message);
    }
  }

  Future<OpenRouterResult> enrichWord(String word) async {
    final prompt = _buildPrompt(word);
    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'google/gemini-3-flash-preview',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 40000,
        'reasoning': {'enabled': true},
        'response_format': {'type': 'json_object'},
      }),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw InvalidApiKeyException();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OpenRouter error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      final error = decoded['error'] as Map<String, dynamic>? ?? {};
      final message = (error['message'] ?? '').toString();
      if (message.toLowerCase().contains('key')) {
        throw InvalidApiKeyException(message);
      }
      throw Exception(message.isEmpty ? 'OpenRouter error' : message);
    }
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw Exception('OpenRouter returned no choices.');
    }
    final message = choices.first['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'];
    if (content is! String) {
      throw Exception('OpenRouter response missing content.');
    }

    final payload = jsonDecode(content) as Map<String, dynamic>;
    final wordPayload = _findWordPayload(payload, word);
    if (wordPayload == null) {
      throw Exception('OpenRouter response missing data for $word.');
    }

    final definition = _normalizeText(wordPayload['definition']);
    final examples = _normalizeList(wordPayload['examples']);
    final distractors = _normalizeList(wordPayload['distractors']);

    if (definition.isEmpty) {
      throw Exception('OpenRouter returned an empty definition.');
    }

    return OpenRouterResult(
      definition: definition,
      examples: examples,
      distractors: distractors,
    );
  }

  Map<String, dynamic>? _findWordPayload(Map<String, dynamic> payload, String word) {
    if (payload.containsKey(word)) {
      return payload[word] as Map<String, dynamic>?;
    }
    final lower = word.toLowerCase();
    for (final entry in payload.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value as Map<String, dynamic>?;
      }
    }
    if (payload.length == 1) {
      final value = payload.values.first;
      if (value is Map<String, dynamic>) {
        return value;
      }
    }
    return null;
  }

  String _normalizeText(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  List<String> _normalizeList(dynamic value) {
    final list = <String>[];
    if (value is List) {
      for (final item in value) {
        final text = item.toString().trim();
        if (text.isNotEmpty) {
          list.add(text);
        }
      }
      return list;
    }
    if (value is String) {
      final text = value.trim();
      if (text.isNotEmpty) {
        list.add(text);
      }
    }
    return list;
  }

  String _buildPrompt(String word) {
    return """
    For each word, return:
    - definition: 5-12 words, plain English, no filler.
    - distractors: 15 short definition-style phrases (5-12 words), same part of speech.
      Each distractor MUST be a definition-style clause with a verb (e.g., "being...", "having...", "marked by...", "characterized by...").
      Match the definition’s format and length (use a similar lead-in like "Relating to...", within ±2 words).
      Do NOT output noun-only fragments.
      Mix difficulty: 5 easy wrong, 7 medium, 3 hard-but-wrong.
      Avoid close synonyms or near-misses that could confuse learners.
      Do NOT use the target word or close variants.
      Avoid meta labels like category/genre/brand/model/app/software/name/address.
      EMPHATIC ANTI-PATTERNS (DO NOT DO THESE):
      - Do NOT output concrete objects or food/drink items (e.g., "sweet fruit aroma", "fizzy soda", "pastry").
      - Do NOT output scene fragments or physical places (e.g., "quiet forest glade", "busy train station").
      - Do NOT output single nouns or noun lists without definition-style wording.
      - Do NOT output generic labels (e.g., "a type of X", "kind of Y", "brand/model/name").
    - examples: 5 sentences, 12-25 words each, each must include the word (or inflected form).
      Provide helpful context for someone learning the word; use book-like usage.
      The context should NOT be a dead giveaway for the definition, and NOT useless for inferring meaning.
      Avoid bland, generic sentences.
    
    Words: $word
    
    Return ONLY a JSON object where the keys are the words and the values are objects with the following structure.
    Example response for a fictional word "vellumate":
    {
      "vellumate": {
        "definition": "Relating to formal, meticulous work in an official setting.",
        "distractors": [
          "Relating to seasonal weather patterns and forecasting",
          "Relating to theatrical performance and stagecraft traditions",
          "Relating to childhood play and social games",
          "Relating to culinary technique and slow cooking methods",
          "Relating to insect behavior and life cycles",
          "Relating to navigation safety and route planning",
          "Relating to financial markets and speculative trading",
          "Relating to marine biology and ecosystem balance",
          "Relating to architectural design and urban planning",
          "Relating to religious ceremony and liturgy",
          "Relating to bird migration and seasonal movement",
          "Relating to mechanical repair and equipment maintenance",
          "Relating to medical nutrition and recovery support",
          "Relating to software updates and release cycles",
          "Relating to group psychology and social behavior"
        ],
        "examples": [
          "By the end of the meeting, her vellumate tone slowed the rush and turned scattered talk into measured decisions.",
          "He approached the negotiations with a vellumate air, pausing often, preferring certainty over speed.",
          "After the audit notice arrived, the office adopted a vellumate style, careful and deliberate in every response.",
          "She chose a vellumate approach to the case, resisting shortcuts and insisting on clear steps.",
          "His vellumate habits made him the obvious choice for sensitive tasks demanding patience and restraint."
        ]
      }
    }
    {
      "word_stem": {
        "definition": "Short, punchy definition",
        "distractors": ["distractor 1", ..., "distractor 15"],
        "examples": ["sentence 1", ..., "sentence 5"]
      }
    }
    """;
  }
}
