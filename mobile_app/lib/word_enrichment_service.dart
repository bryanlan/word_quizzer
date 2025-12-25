import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'openrouter_service.dart';

class MissingApiKeyException implements Exception {
  final String message;
  MissingApiKeyException([this.message = 'Missing OpenRouter key']);
}

class NotAuthenticatedException implements Exception {
  final String message;
  NotAuthenticatedException([this.message = 'Not authenticated']);
}

class WordEnrichmentService {
  static const String _defaultServerUrl =
      'https://word-quizzer-api.bryanlangley.org';

  static Future<OpenRouterResult> enrichWord(String word) async {
    if (kIsWeb) {
      return _enrichViaServer(word);
    }
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('openrouter_api_key') ?? '';
    if (key.trim().isEmpty) {
      throw MissingApiKeyException();
    }
    final service = OpenRouterService(key.trim());
    return service.enrichWord(word);
  }

  static Future<void> setServerKey(String apiKey) async {
    if (!kIsWeb) {
      throw UnsupportedError('Server keys are managed on web only.');
    }
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      throw NotAuthenticatedException();
    }
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('sync_server_url') ?? _defaultServerUrl;
    final url = Uri.parse('${_normalize(baseUrl)}/llm/openrouter-key');
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'api_key': apiKey}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw NotAuthenticatedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<bool> serverKeyConfigured() async {
    if (!kIsWeb) {
      return true;
    }
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('sync_server_url') ?? _defaultServerUrl;
    final url = Uri.parse('${_normalize(baseUrl)}/llm/openrouter-key/status');
    final response = await http.get(url, headers: _headers(token));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['configured'] == true;
  }

  static Future<OpenRouterResult> _enrichViaServer(String word) async {
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      throw NotAuthenticatedException();
    }
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('sync_server_url') ?? _defaultServerUrl;
    final url = Uri.parse('${_normalize(baseUrl)}/llm/enrich-word');
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode({'word': word}),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw NotAuthenticatedException();
    }
    if (response.statusCode == 412 || response.statusCode == 424) {
      throw MissingApiKeyException('Server OpenRouter key is missing.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _extractErrorMessage(response.body);
      if (_looksLikeMissingKey(message)) {
        throw MissingApiKeyException('Server OpenRouter key is missing.');
      }
      final suffix = message.isEmpty ? '' : ' - $message';
      throw Exception('Server error: ${response.statusCode}$suffix');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final definition = decoded['definition']?.toString().trim() ?? '';
    final examples = _normalizeList(decoded['examples']);
    final distractors = _normalizeList(decoded['distractors']);
    if (definition.isEmpty) {
      throw Exception('Server response missing definition.');
    }
    return OpenRouterResult(
      definition: definition,
      examples: examples,
      distractors: distractors,
    );
  }

  static List<String> _normalizeList(dynamic value) {
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

  static String _normalize(String url) {
    final trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static Map<String, String> _headers(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static String _extractErrorMessage(String body) {
    if (body.trim().isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final candidates = [
          decoded['error'],
          decoded['detail'],
          decoded['message'],
        ];
        for (final candidate in candidates) {
          if (candidate == null) continue;
          if (candidate is String) {
            final text = candidate.trim();
            if (text.isNotEmpty) {
              return text;
            }
          } else if (candidate is Map<String, dynamic>) {
            final nested = candidate['message']?.toString().trim() ?? '';
            if (nested.isNotEmpty) {
              return nested;
            }
          }
        }
      }
    } catch (_) {
      // Fall back to raw body.
    }
    return body.trim();
  }

  static bool _looksLikeMissingKey(String message) {
    final lower = message.toLowerCase();
    return (lower.contains('openrouter') && lower.contains('key')) ||
        lower.contains('missing_key') ||
        lower.contains('missing key');
  }
}
