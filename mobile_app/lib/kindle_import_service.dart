import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class KindleImportSummary {
  final String importId;
  final int totalExtracted;
  final int newWords;
  final int repeatWords;
  final int ignoredByLlm;

  KindleImportSummary({
    required this.importId,
    required this.totalExtracted,
    required this.newWords,
    required this.repeatWords,
    required this.ignoredByLlm,
  });

  factory KindleImportSummary.fromMap(Map<String, dynamic> map) {
    return KindleImportSummary(
      importId: map['import_id']?.toString() ?? '',
      totalExtracted: map['total_extracted'] as int? ?? 0,
      newWords: map['new_words'] as int? ?? 0,
      repeatWords: map['repeat_words'] as int? ?? 0,
      ignoredByLlm: map['ignored_by_llm'] as int? ?? 0,
    );
  }
}

class ImportWord {
  final int id;
  final String word;

  ImportWord({
    required this.id,
    required this.word,
  });

  factory ImportWord.fromMap(Map<String, dynamic> map) {
    return ImportWord(
      id: map['id'] as int,
      word: map['word']?.toString() ?? '',
    );
  }
}

class ImportJob {
  final String jobId;
  final String status;
  final String message;
  final int processed;
  final int total;
  final Map<String, dynamic> result;

  ImportJob({
    required this.jobId,
    required this.status,
    required this.message,
    required this.processed,
    required this.total,
    required this.result,
  });

  factory ImportJob.fromMap(Map<String, dynamic> map) {
    final result = map['result'];
    return ImportJob(
      jobId: map['job_id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'unknown',
      message: map['message']?.toString() ?? map['step']?.toString() ?? '',
      processed: map['processed'] as int? ?? 0,
      total: map['total'] as int? ?? 0,
      result: result is Map<String, dynamic> ? result : <String, dynamic>{},
    );
  }
}

class KindleImportService {
  final String baseUrl;
  final String token;

  KindleImportService({
    required this.baseUrl,
    required this.token,
  });

  String _normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Map<String, String> _headers() {
    return {
      'Authorization': 'Bearer $token',
    };
  }

  Uri _buildUri(String path) {
    return Uri.parse('${_normalizeUrl(baseUrl)}$path');
  }

  Future<KindleImportSummary> uploadKindleFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _buildUri('/import/kindle'),
    );
    request.headers.addAll(_headers());
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw Exception('Import failed: ${response.statusCode} ${body.trim()}');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return KindleImportSummary.fromMap(decoded);
  }

  Future<ImportJob> startFilter(String importId) async {
    final response = await http.post(
      _buildUri('/import/$importId/filter'),
      headers: {
        ..._headers(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'mode': 'llm'}),
    );
    if (response.statusCode >= 400) {
      throw Exception('Filter start failed: ${response.statusCode} ${response.body}');
    }
    return ImportJob.fromMap(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ImportJob> startEnrichment(String importId) async {
    final response = await http.post(
      _buildUri('/import/$importId/enrich'),
      headers: {
        ..._headers(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'mode': 'full'}),
    );
    if (response.statusCode >= 400) {
      throw Exception('Enrichment start failed: ${response.statusCode} ${response.body}');
    }
    return ImportJob.fromMap(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ImportJob> getJob(String jobId) async {
    final response = await http.get(
      _buildUri('/import/jobs/$jobId'),
      headers: _headers(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Job fetch failed: ${response.statusCode} ${response.body}');
    }
    return ImportJob.fromMap(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<ImportWord>> getTriageWords(String importId) async {
    final response = await http.get(
      _buildUri('/import/$importId/triage'),
      headers: _headers(),
    );
    if (response.statusCode >= 400) {
      throw Exception('Triage fetch failed: ${response.statusCode} ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawWords = decoded['words'];
    if (rawWords is! List) {
      return [];
    }
    return rawWords
        .whereType<Map>()
        .map((row) => ImportWord.fromMap(row.cast<String, dynamic>()))
        .toList();
  }

  Future<void> submitTriage(
    String importId,
    List<Map<String, dynamic>> decisions,
  ) async {
    final response = await http.post(
      _buildUri('/import/$importId/triage'),
      headers: {
        ..._headers(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'decisions': decisions}),
    );
    if (response.statusCode >= 400) {
      throw Exception('Triage submit failed: ${response.statusCode} ${response.body}');
    }
  }
}
