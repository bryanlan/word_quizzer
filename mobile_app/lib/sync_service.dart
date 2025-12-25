import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'db_helper.dart';

class SyncSummary {
  final int wordsCreated;
  final int wordsUpdated;
  final int distractorsCreated;
  final int examplesCreated;
  final int studyLogCreated;
  final int statusLogCreated;
  final bool hadSecondPass;

  SyncSummary({
    required this.wordsCreated,
    required this.wordsUpdated,
    required this.distractorsCreated,
    required this.examplesCreated,
    required this.studyLogCreated,
    required this.statusLogCreated,
    required this.hadSecondPass,
  });
}

class SyncService {
  final String baseUrl;
  final String token;

  SyncService({
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
      'Content-Type': 'application/json',
    };
  }

  Future<void> testAuth() async {
    final url = Uri.parse('${_normalizeUrl(baseUrl)}/sync/export');
    final response = await http.get(url, headers: _headers());
    if (response.statusCode != 200) {
      throw Exception('Auth failed: ${response.statusCode}');
    }
  }

  Future<SyncSummary> sync() async {
    final exportData = await _fetchExport();
    final db = await DatabaseHelper.instance.database;
    final newWordStems = await _mergeServerData(db, exportData);

    final primaryPayload = await _buildPayload(db, requireServerId: true);
    final primaryResult = await _sendImport(primaryPayload);

    var hadSecondPass = false;
    var finalResult = primaryResult;

    if (newWordStems.isNotEmpty) {
      final newWordPayload = await _buildPayload(
        db,
        requireServerId: false,
        wordStems: newWordStems,
      );
      if (newWordPayload['words'] != null &&
          (newWordPayload['words'] as List).isNotEmpty) {
        await _sendImport(newWordPayload);
        final refreshed = await _fetchExport();
        await _mergeServerData(db, refreshed);
        final secondPayload = await _buildPayload(
          db,
          requireServerId: true,
          wordStems: newWordStems,
        );
        finalResult = await _sendImport(secondPayload);
        hadSecondPass = true;
      }
    }

    return SyncSummary(
      wordsCreated: finalResult['words_created'] ?? 0,
      wordsUpdated: finalResult['words_updated'] ?? 0,
      distractorsCreated: finalResult['distractors_created'] ?? 0,
      examplesCreated: finalResult['examples_created'] ?? 0,
      studyLogCreated: finalResult['study_log_created'] ?? 0,
      statusLogCreated: finalResult['status_log_created'] ?? 0,
      hadSecondPass: hadSecondPass,
    );
  }

  Future<Map<String, dynamic>> _fetchExport() async {
    final url = Uri.parse('${_normalizeUrl(baseUrl)}/sync/export');
    final response = await http.get(url, headers: _headers());
    if (response.statusCode != 200) {
      throw Exception('Export failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded;
  }

  Future<Map<String, dynamic>> _sendImport(Map<String, dynamic> payload) async {
    final url = Uri.parse('${_normalizeUrl(baseUrl)}/sync/import');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Import failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  DateTime _parseDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Set<String>> _mergeServerData(
    Database db,
    Map<String, dynamic> exportData,
  ) async {
    final localWords = await db.query(
      'words',
      columns: [
        'id',
        'word_stem',
        'original_context',
        'book_title',
        'definition',
        'phonetic',
        'status',
        'bucket_date',
        'next_review_date',
        'difficulty_score',
        'priority_tier',
        'status_correct_streak',
        'manual_flag',
        'server_word_id',
        'updated_at',
      ],
    );

    final localByStem = <String, Map<String, dynamic>>{};
    for (final row in localWords) {
      final stem = (row['word_stem'] ?? '').toString();
      if (stem.isEmpty) {
        continue;
      }
      localByStem[stem] = Map<String, dynamic>.from(row);
    }

    final serverWords = (exportData['words'] as List<dynamic>? ?? [])
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final serverByStem = <String, Map<String, dynamic>>{};
    final serverIdToStem = <int, String>{};
    for (final row in serverWords) {
      final stem = (row['word_stem'] ?? '').toString();
      if (stem.isEmpty) {
        continue;
      }
      serverByStem[stem] = row;
      final id = row['id'];
      if (id is int) {
        serverIdToStem[id] = stem;
      }
    }

    final serverExamples = (exportData['examples'] as List<dynamic>? ?? [])
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final serverDistractors = (exportData['distractors'] as List<dynamic>? ?? [])
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final localExamples = await db.query(
      'examples',
      columns: ['word_id', 'sentence'],
    );
    final localDistractors = await db.query(
      'distractors',
      columns: ['word_id', 'text'],
    );

    final localExamplesByWordId = <int, List<String>>{};
    for (final row in localExamples) {
      final wordId = row['word_id'] as int?;
      final sentence = row['sentence']?.toString() ?? '';
      if (wordId == null || sentence.isEmpty) {
        continue;
      }
      localExamplesByWordId.putIfAbsent(wordId, () => []).add(sentence);
    }

    final localDistractorsByWordId = <int, List<String>>{};
    for (final row in localDistractors) {
      final wordId = row['word_id'] as int?;
      final text = row['text']?.toString() ?? '';
      if (wordId == null || text.isEmpty) {
        continue;
      }
      localDistractorsByWordId.putIfAbsent(wordId, () => []).add(text);
    }

    final serverExamplesByStem = <String, List<String>>{};
    for (final row in serverExamples) {
      final wordId = row['word_id'];
      if (wordId is! int) {
        continue;
      }
      final stem = serverIdToStem[wordId];
      if (stem == null) {
        continue;
      }
      final sentence = row['sentence']?.toString() ?? '';
      if (sentence.isEmpty) {
        continue;
      }
      serverExamplesByStem.putIfAbsent(stem, () => []).add(sentence);
    }

    final serverDistractorsByStem = <String, List<String>>{};
    for (final row in serverDistractors) {
      final wordId = row['word_id'];
      if (wordId is! int) {
        continue;
      }
      final stem = serverIdToStem[wordId];
      if (stem == null) {
        continue;
      }
      final text = row['text']?.toString() ?? '';
      if (text.isEmpty) {
        continue;
      }
      serverDistractorsByStem.putIfAbsent(stem, () => []).add(text);
    }

    final stems = <String>{...localByStem.keys, ...serverByStem.keys};
    final now = DateTime.now().toIso8601String();
    final newWordStems = <String>{};

    await db.transaction((txn) async {
      for (final stem in stems) {
        final local = localByStem[stem];
        final server = serverByStem[stem];
        final localUpdated = _parseDateTime(local?['updated_at']?.toString());
        final serverUpdated = _parseDateTime(server?['updated_at']?.toString());
        final useLocal = server == null || localUpdated.isAfter(serverUpdated);

        int localId;
        if (local != null) {
          localId = local['id'] as int;
        } else {
          localId = await txn.insert('words', {
            'word_stem': stem,
            'original_context': server?['original_context'],
            'book_title': server?['book_title'],
            'definition': server?['definition'],
            'phonetic': server?['phonetic'],
            'status': server?['status'] ?? 'New',
            'bucket_date': server?['bucket_date'],
            'next_review_date': server?['next_review_date'],
            'difficulty_score': server?['difficulty_score'],
            'priority_tier': server?['priority_tier'],
            'status_correct_streak': server?['status_correct_streak'] ?? 0,
            'manual_flag': server?['manual_flag'] == true ? 1 : 0,
            'server_word_id': server?['id'],
            'updated_at': server?['updated_at'] ?? now,
          });
        }

        if (useLocal) {
          if (server == null) {
            newWordStems.add(stem);
          }
          await txn.update(
            'words',
            {
              'server_word_id': server?['id'],
              'updated_at': (local?['updated_at'] ?? now).toString(),
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
        } else {
          await txn.update(
            'words',
            {
              'original_context': server['original_context'],
              'book_title': server['book_title'],
              'definition': server['definition'],
              'phonetic': server['phonetic'],
              'status': server['status'] ?? 'New',
              'bucket_date': server['bucket_date'],
              'next_review_date': server['next_review_date'],
              'difficulty_score': server['difficulty_score'],
              'priority_tier': server['priority_tier'],
              'status_correct_streak': server['status_correct_streak'] ?? 0,
              'manual_flag': server['manual_flag'] == true ? 1 : 0,
              'server_word_id': server['id'],
              'updated_at': server['updated_at'] ?? now,
            },
            where: 'id = ?',
            whereArgs: [localId],
          );
        }

        final selectedExamples = useLocal
            ? (localExamplesByWordId[localId] ?? [])
            : (serverExamplesByStem[stem] ?? []);
        final selectedDistractors = useLocal
            ? (localDistractorsByWordId[localId] ?? [])
            : (serverDistractorsByStem[stem] ?? []);

        await txn.delete('examples', where: 'word_id = ?', whereArgs: [localId]);
        for (final sentence in selectedExamples) {
          await txn.insert('examples', {
            'word_id': localId,
            'sentence': sentence,
          });
        }

        await txn.delete('distractors', where: 'word_id = ?', whereArgs: [localId]);
        for (final text in selectedDistractors) {
          await txn.insert('distractors', {
            'word_id': localId,
            'text': text,
          });
        }
      }

      final localWordIdByStemFinal = <String, int>{};
      final stemByLocalId = <int, String>{};
      final wordRows = await txn.query('words', columns: ['id', 'word_stem']);
      for (final row in wordRows) {
        final stem = (row['word_stem'] ?? '').toString();
        final id = row['id'] as int?;
        if (stem.isNotEmpty && id != null) {
          localWordIdByStemFinal[stem] = id;
          stemByLocalId[id] = stem;
        }
      }

      final localStudyRows = await txn.query(
        'study_log',
        columns: ['word_id', 'result', 'timestamp', 'session_id'],
      );
      final localStudyKeys = <String>{};
      for (final row in localStudyRows) {
        final wordId = row['word_id'] as int?;
        final stem = wordId == null ? null : stemByLocalId[wordId];
        if (stem == null || stem.isEmpty) {
          continue;
        }
        final key = [
          stem,
          row['result']?.toString() ?? '',
          row['timestamp']?.toString() ?? '',
          row['session_id']?.toString() ?? ''
        ].join('|');
        localStudyKeys.add(key);
      }

      final serverStudyRows = (exportData['study_log'] as List<dynamic>? ?? [])
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      for (final row in serverStudyRows) {
        final serverWordId = row['word_id'];
        if (serverWordId is! int) {
          continue;
        }
        final stem = serverIdToStem[serverWordId];
        if (stem == null) {
          continue;
        }
        final localId = localWordIdByStemFinal[stem];
        if (localId == null) {
          continue;
        }
        final key = [
          stem,
          row['result']?.toString() ?? '',
          row['timestamp']?.toString() ?? '',
          row['session_id']?.toString() ?? ''
        ].join('|');
        if (localStudyKeys.contains(key)) {
          continue;
        }
        localStudyKeys.add(key);
        await txn.insert('study_log', {
          'word_id': localId,
          'result': row['result'] ?? 'Correct',
          'timestamp': row['timestamp'] ?? now,
          'session_id': row['session_id'],
        });
      }

      final localStatusRows = await txn.query(
        'status_log',
        columns: ['word_id', 'from_status', 'to_status', 'timestamp'],
      );
      final localStatusKeys = <String>{};
      for (final row in localStatusRows) {
        final wordId = row['word_id'] as int?;
        final stem = wordId == null ? null : stemByLocalId[wordId];
        if (stem == null || stem.isEmpty) {
          continue;
        }
        final key = [
          stem,
          row['from_status']?.toString() ?? '',
          row['to_status']?.toString() ?? '',
          row['timestamp']?.toString() ?? '',
        ].join('|');
        localStatusKeys.add(key);
      }

      final serverStatusRows = (exportData['status_log'] as List<dynamic>? ?? [])
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      for (final row in serverStatusRows) {
        final serverWordId = row['word_id'];
        if (serverWordId is! int) {
          continue;
        }
        final stem = serverIdToStem[serverWordId];
        if (stem == null) {
          continue;
        }
        final localId = localWordIdByStemFinal[stem];
        if (localId == null) {
          continue;
        }
        final key = [
          stem,
          row['from_status']?.toString() ?? '',
          row['to_status']?.toString() ?? '',
          row['timestamp']?.toString() ?? '',
        ].join('|');
        if (localStatusKeys.contains(key)) {
          continue;
        }
        localStatusKeys.add(key);
        await txn.insert('status_log', {
          'word_id': localId,
          'from_status': row['from_status'],
          'to_status': row['to_status'],
          'timestamp': row['timestamp'] ?? now,
        });
      }
    });

    return newWordStems;
  }

  Future<Map<String, dynamic>> _buildPayload(
    Database db, {
    required bool requireServerId,
    Set<String>? wordStems,
  }) async {
    final whereParts = <String>[];
    final args = <Object?>[];
    if (requireServerId) {
      whereParts.add('server_word_id IS NOT NULL');
    } else {
      whereParts.add('server_word_id IS NULL');
    }

    if (wordStems != null && wordStems.isNotEmpty) {
      final placeholders = List.filled(wordStems.length, '?').join(',');
      whereParts.add('word_stem IN ($placeholders)');
      args.addAll(wordStems);
    }

    final whereClause = whereParts.isEmpty ? null : whereParts.join(' AND ');
    final words = await db.query(
      'words',
      columns: [
        'id',
        'word_stem',
        'original_context',
        'book_title',
        'definition',
        'phonetic',
        'status',
        'bucket_date',
        'next_review_date',
        'difficulty_score',
        'priority_tier',
        'status_correct_streak',
        'manual_flag',
        'server_word_id',
      ],
      where: whereClause,
      whereArgs: args,
    );

    final wordIds = words.map((w) => w['id'] as int).toList();
    final wordIdByLocalId = <int, int>{};
    for (final row in words) {
      final localId = row['id'] as int;
      final serverId = row['server_word_id'] as int?;
      if (serverId != null) {
        wordIdByLocalId[localId] = serverId;
      }
    }

    List<Map<String, dynamic>> examples = [];
    List<Map<String, dynamic>> distractors = [];
    List<Map<String, dynamic>> studyLog = [];
    List<Map<String, dynamic>> statusLog = [];

    if (requireServerId && wordIds.isNotEmpty) {
      final placeholders = List.filled(wordIds.length, '?').join(',');
      final exampleRows = await db.rawQuery('''
        SELECT e.sentence, e.word_id
        FROM examples e
        WHERE e.word_id IN ($placeholders)
      ''', wordIds);
      examples = exampleRows.map((row) {
        final localId = row['word_id'] as int;
        return {
          'word_id': wordIdByLocalId[localId],
          'sentence': row['sentence'],
        };
      }).where((row) => row['word_id'] != null).toList();

      final distractorRows = await db.rawQuery('''
        SELECT d.text, d.word_id
        FROM distractors d
        WHERE d.word_id IN ($placeholders)
      ''', wordIds);
      distractors = distractorRows.map((row) {
        final localId = row['word_id'] as int;
        return {
          'word_id': wordIdByLocalId[localId],
          'text': row['text'],
        };
      }).where((row) => row['word_id'] != null).toList();

      final studyRows = await db.rawQuery('''
        SELECT l.result, l.timestamp, l.session_id, l.word_id
        FROM study_log l
        WHERE l.word_id IN ($placeholders)
      ''', wordIds);
      studyLog = studyRows.map((row) {
        final localId = row['word_id'] as int;
        return {
          'word_id': wordIdByLocalId[localId],
          'result': row['result'],
          'session_id': row['session_id'],
          'timestamp': row['timestamp'],
        };
      }).where((row) => row['word_id'] != null).toList();

      final statusRows = await db.rawQuery('''
        SELECT l.from_status, l.to_status, l.timestamp, l.word_id
        FROM status_log l
        WHERE l.word_id IN ($placeholders)
      ''', wordIds);
      statusLog = statusRows.map((row) {
        final localId = row['word_id'] as int;
        return {
          'word_id': wordIdByLocalId[localId],
          'from_status': row['from_status'],
          'to_status': row['to_status'],
          'timestamp': row['timestamp'],
        };
      }).where((row) => row['word_id'] != null).toList();
    }

    final wordPayload = words.map((row) {
      return {
        'word_stem': row['word_stem'],
        'original_context': row['original_context'],
        'book_title': row['book_title'],
        'definition': row['definition'],
        'phonetic': row['phonetic'],
        'status': row['status'],
        'bucket_date': row['bucket_date'],
        'next_review_date': row['next_review_date'],
        'difficulty_score': row['difficulty_score'],
        'priority_tier': row['priority_tier'],
        'status_correct_streak': row['status_correct_streak'] ?? 0,
        'manual_flag': (row['manual_flag'] == 1 || row['manual_flag'] == true),
      };
    }).toList();

    return {
      'words': wordPayload,
      'distractors': distractors,
      'examples': examples,
      'study_log': studyLog,
      'status_log': statusLog,
      'insults': [],
    };
  }
}
