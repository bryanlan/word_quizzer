import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'openrouter_service.dart';
import 'usage_grading.dart';

export 'usage_grading.dart';

class WordUsageGradingService {
  static const String _defaultServerUrl =
      'https://word-quizzer-api.bryanlangley.org';

  static Future<UsageGradeResult> gradeUsage({
    required String word,
    required String definition,
    required String sentence,
  }) async {
    if (kIsWeb) {
      return _gradeViaServer(word, definition, sentence);
    }

    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('openrouter_api_key') ?? '';
    if (key.trim().isEmpty) {
      throw Exception('Missing OpenRouter key.');
    }
    final service = OpenRouterService(key.trim());
    return service.gradeUsage(word: word, definition: definition, sentence: sentence);
  }

  static Future<UsageGradeResult> _gradeViaServer(
    String word,
    String definition,
    String sentence,
  ) async {
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('Not authenticated.');
    }
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('sync_server_url') ?? _defaultServerUrl;
    final url = Uri.parse('${_normalize(baseUrl)}/llm/grade-sentence');
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'word': word,
        'definition': definition,
        'sentence': sentence,
      }),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Not authenticated.');
    }
    if (response.statusCode == 404) {
      throw Exception('Server does not support sentence grading yet (404).');
    }
    if (response.statusCode == 412 || response.statusCode == 424) {
      throw Exception('Server OpenRouter key is missing.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _extractErrorMessage(response.body);
      final suffix = message.isEmpty ? '' : ' - $message';
      throw Exception('Server error: ${response.statusCode}$suffix');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final gradeRaw = decoded['grade']?.toString().trim().toLowerCase() ?? '';
    final feedback = decoded['feedback']?.toString().trim() ?? '';
    final whyWrong = _normalizeList(decoded['why_wrong']);
    final improvements = _normalizeList(decoded['improvements']);
    final correctedExample = decoded['corrected_example']?.toString().trim() ?? '';
    final similarExamples = _normalizeList(decoded['similar_examples']);
    final subtleties = _normalizeList(decoded['subtleties']);
    return UsageGradeResult(
      grade: _normalizeGrade(gradeRaw),
      feedback: feedback,
      whyWrong: whyWrong,
      improvements: improvements,
      correctedExample: correctedExample,
      similarExamples: similarExamples,
      subtleties: subtleties,
    );
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

  static String _normalizeGrade(String value) {
    switch (value) {
      case 'easy':
      case 'hard':
      case 'failed':
        return value;
      case 'fail':
        return 'failed';
      default:
        return 'failed';
    }
  }

  static List<String> _normalizeList(dynamic value) {
    if (value == null) {
      return const [];
    }
    final result = <String>[];
    if (value is List) {
      for (final item in value) {
        final text = item.toString().trim();
        if (text.isNotEmpty) {
          result.add(text);
        }
      }
      return result;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      result.add(text);
    }
    return result;
  }
}
