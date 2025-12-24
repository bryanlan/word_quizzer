import 'dart:io';
import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<bool> _hasTable(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  Future<bool> hasTable(String tableName) async {
    final db = await database;
    return _hasTable(db, tableName);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    final db = await _initDB('vocab_master.db');
    await _ensureOnDeckStatusSchema(db);
    _database = db;
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    // Check if DB exists, if not, we can't do much until import
    return await openDatabase(path, version: 1);
  }

  Future<void> importDatabase(String sourcePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vocab_master.db');

    // Close existing connection if open
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }

    // Copy file
    File source = File(sourcePath);
    await source.copy(path);

    _database = await _initDB('vocab_master.db');
    await _ensureOnDeckStatusSchema(_database!);
  }

  Future<void> _ensureOnDeckStatusSchema(Database db) async {
    if (!await _hasTable(db, 'words')) {
      return;
    }

    final columns = await db.rawQuery("PRAGMA table_info(words)");
    final hasPriorityTier = columns.any((c) => c['name'] == 'priority_tier');
    final hasManualFlag = columns.any((c) => c['name'] == 'manual_flag');
    final hasStreak = columns.any((c) => c['name'] == 'status_correct_streak');

    final tableSqlRows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='words'"
    );
    final tableSql = tableSqlRows.isNotEmpty ? (tableSqlRows.first['sql']?.toString() ?? '') : '';
    final hasOnDeck = tableSql.toLowerCase().contains('on deck');

    if (hasOnDeck) {
      await db.transaction((txn) async {
        if (!hasPriorityTier) {
          await txn.execute("ALTER TABLE words ADD COLUMN priority_tier INTEGER");
        }
        if (!hasManualFlag) {
          await txn.execute("ALTER TABLE words ADD COLUMN manual_flag BOOLEAN DEFAULT 0");
        }
        if (!hasStreak) {
          await txn.execute("ALTER TABLE words ADD COLUMN status_correct_streak INTEGER DEFAULT 0");
        }
      });
      return;
    }

    await db.transaction((txn) async {
      await txn.execute("PRAGMA foreign_keys=OFF");
      await txn.execute("ALTER TABLE words RENAME TO words_old");
      await txn.execute("""
        CREATE TABLE words (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          word_stem TEXT UNIQUE NOT NULL,
          original_context TEXT,
          book_title TEXT,
          definition TEXT,
          phonetic TEXT,
          status TEXT CHECK(status IN ('New', 'On Deck', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored', 'Pau(S)ed')) DEFAULT 'New',
          bucket_date DATE,
          next_review_date DATE,
          difficulty_score INTEGER,
          priority_tier INTEGER,
          status_correct_streak INTEGER DEFAULT 0,
          manual_flag BOOLEAN DEFAULT 0
        );
      """);

      await txn.execute("""
        INSERT INTO words (
          id,
          word_stem,
          original_context,
          book_title,
          definition,
          phonetic,
          status,
          bucket_date,
          next_review_date,
          difficulty_score,
          priority_tier,
          status_correct_streak,
          manual_flag
        )
        SELECT
          id,
          word_stem,
          original_context,
          book_title,
          definition,
          phonetic,
          CASE WHEN status = 'Learning' THEN 'On Deck' ELSE status END,
          bucket_date,
          next_review_date,
          difficulty_score,
          ${hasPriorityTier ? 'priority_tier' : 'NULL'},
          ${hasStreak ? 'status_correct_streak' : '0'},
          ${hasManualFlag ? 'manual_flag' : '0'}
        FROM words_old;
      """);
      await txn.execute("DROP TABLE words_old");
      await txn.execute("PRAGMA foreign_keys=ON");
    });
  }

  List<int> _pickTieredIds(List<Map<String, dynamic>> rows, int count) {
    final rng = Random();
    final buckets = <int, List<int>>{};
    for (final row in rows) {
      final rawTier = row['priority_tier'];
      final tier = rawTier is int ? rawTier : int.tryParse(rawTier?.toString() ?? '') ?? 3;
      final normalizedTier = tier.clamp(1, 5);
      buckets.putIfAbsent(normalizedTier, () => []).add(row['id'] as int);
    }

    final picks = <int>[];
    var remaining = count;
    if (remaining < 0) {
      return picks;
    }

    for (var tier = 1; tier <= 5 && remaining > 0; tier++) {
      final ids = buckets[tier];
      if (ids == null || ids.isEmpty) {
        continue;
      }
      ids.shuffle(rng);
      while (ids.isNotEmpty && remaining > 0) {
        picks.add(ids.removeLast());
        remaining--;
      }
    }

    return picks;
  }

  Future<void> _promoteOnDeckToLearning(Database db, int activeLearningLimit) async {
    if (!await _hasTable(db, 'words')) {
      return;
    }

    final activeCount = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Learning'")
    ) ?? 0;
    final needed = activeLearningLimit - activeCount;
    if (needed <= 0) {
      return;
    }

    final candidates = await db.query(
      'words',
      columns: ['id', 'priority_tier'],
      where: "status = 'On Deck'",
    );
    if (candidates.isEmpty) {
      return;
    }

    final selectedIds = _pickTieredIds(candidates, needed);
    if (selectedIds.isEmpty) {
      return;
    }

    final now = DateTime.now().toIso8601String();
    final idList = selectedIds.join(',');
    await db.update(
      'words',
      {
        'status': 'Learning',
        'bucket_date': now,
        'next_review_date': null,
      },
      where: 'id IN ($idList)',
    );
  }

  Future<List<Word>> _fetchWordsForStatus(
    Database db, {
    required String status,
    required int limit,
    required bool dueOnly,
    required Set<int> excludeIds,
  }) async {
    if (limit <= 0) {
      return [];
    }

    final whereParts = <String>["status = ?"];
    final args = <Object>[status];

    if (dueOnly) {
      whereParts.add("(next_review_date IS NULL OR next_review_date <= DATE('now'))");
    }

    if (excludeIds.isNotEmpty) {
      final placeholders = List.filled(excludeIds.length, '?').join(',');
      whereParts.add("id NOT IN ($placeholders)");
      args.addAll(excludeIds);
    }

    final rows = await db.query(
      'words',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'RANDOM()',
      limit: limit,
    );

    return rows.map((json) => Word.fromMap(json)).toList();
  }

  Future<List<Word>> getDailyDeck() async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('active_limit') ?? 20;
    final int quizLength = prefs.getInt('quiz_length') ?? 20;
    int pctLearning = prefs.getInt('pct_learning') ?? 60;
    int pctProficient = prefs.getInt('pct_proficient') ?? 20;
    int pctAdept = prefs.getInt('pct_adept') ?? 15;
    int pctMastered = prefs.getInt('pct_mastered') ?? 5;

    if (quizLength <= 0) {
      return [];
    }

    await _promoteOnDeckToLearning(db, activeLearningLimit);

    final weights = <String, int>{
      'Learning': pctLearning,
      'Proficient': pctProficient,
      'Adept': pctAdept,
      'Mastered': pctMastered,
    };

    var totalWeight = weights.values.fold<int>(0, (sum, v) => sum + v);
    if (totalWeight <= 0) {
      pctLearning = 60;
      pctProficient = 20;
      pctAdept = 15;
      pctMastered = 5;
      weights['Learning'] = pctLearning;
      weights['Proficient'] = pctProficient;
      weights['Adept'] = pctAdept;
      weights['Mastered'] = pctMastered;
      totalWeight = 100;
    }

    final targets = <String, int>{};
    final order = ['Learning', 'Proficient', 'Adept', 'Mastered'];
    var allocated = 0;
    for (final status in order) {
      final count = ((quizLength * weights[status]!) / totalWeight).floor();
      targets[status] = count;
      allocated += count;
    }

    var remaining = quizLength - allocated;
    final remainderOrder = order.where((status) => weights[status]! > 0).toList();
    if (remainderOrder.isEmpty) {
      remainderOrder.addAll(order);
    }
    var remainderIndex = 0;
    while (remaining > 0) {
      final status = remainderOrder[remainderIndex % remainderOrder.length];
      targets[status] = (targets[status] ?? 0) + 1;
      remaining--;
      remainderIndex++;
    }

    final deck = <Word>[];
    final selectedIds = <int>{};

    for (final status in order) {
      final limit = targets[status] ?? 0;
      if (limit <= 0) {
        continue;
      }
      final words = await _fetchWordsForStatus(
        db,
        status: status,
        limit: limit,
        dueOnly: status != 'Learning',
        excludeIds: selectedIds,
      );
      for (final word in words) {
        selectedIds.add(word.id);
      }
      deck.addAll(words);
    }

    var fillRemaining = quizLength - deck.length;
    for (final status in order) {
      if (fillRemaining <= 0) {
        break;
      }
      final words = await _fetchWordsForStatus(
        db,
        status: status,
        limit: fillRemaining,
        dueOnly: status != 'Learning',
        excludeIds: selectedIds,
      );
      for (final word in words) {
        selectedIds.add(word.id);
      }
      deck.addAll(words);
      fillRemaining = quizLength - deck.length;
    }

    deck.shuffle();
    return deck;
  }

  Future<List<String>> getOptionsForWord(Word word) async {
    final db = await database;
    List<String> options = [];

    // Add Correct Definition
    if (word.definition != null) {
      options.add(word.definition!);
    } else {
      options.add("MISSING DEFINITION");
    }

    // Get specific distractors
    List<Map<String, dynamic>> distMaps = [];
    if (await _hasTable(db, 'distractors')) {
      distMaps = await db.query(
        'distractors',
        where: 'word_id = ?',
        whereArgs: [word.id],
        limit: 3,
      );
    }
    
    for (var m in distMaps) {
      options.add(m['text']);
    }

    // If we don't have enough specific distractors, fill with random definitions
    if (options.length < 4) {
      final List<Map<String, dynamic>> randomDefs = await db.rawQuery(
        'SELECT definition FROM words WHERE id != ? AND definition IS NOT NULL ORDER BY RANDOM() LIMIT ?',
        [word.id, 4 - options.length]
      );
      for (var m in randomDefs) {
        options.add(m['definition']);
      }
    }

    options.shuffle();
    return options;
  }

  Future<List<String>> getExamplesForWord(int wordId) async {
    final db = await database;
    if (!await _hasTable(db, 'examples')) {
      return [];
    }
    final rows = await db.query(
      'examples',
      columns: ['sentence'],
      where: 'word_id = ?',
      whereArgs: [wordId],
      orderBy: 'id ASC',
    );
    return rows
        .map((row) => (row['sentence'] ?? '').toString())
        .where((sentence) => sentence.trim().isNotEmpty)
        .toList();
  }

  Future<String> getRandomInsult() async {
    final db = await database;
    if (!await _hasTable(db, 'insults')) {
      return "You are wrong. Try again.";
    }
    final List<Map<String, dynamic>> maps = await db.query('insults', orderBy: 'RANDOM()', limit: 1);
    if (maps.isNotEmpty) {
      return maps.first['text'];
    }
    return "You are wrong. Try again.";
  }

  String _demoteStatus(String status) {
    switch (status) {
      case 'Mastered':
        return 'Adept';
      case 'Adept':
        return 'Proficient';
      case 'Proficient':
        return 'Learning';
      default:
        return 'Learning';
    }
  }

  String? _nextReviewDateForStatus(String status) {
    int daysToAdd = 0;
    if (status == 'Proficient') {
      daysToAdd = 1;
    } else if (status == 'Adept') {
      daysToAdd = 3;
    } else if (status == 'Mastered') {
      daysToAdd = 14;
    }

    if (daysToAdd == 0) {
      return null;
    }

    return DateTime.now()
        .add(Duration(days: daysToAdd))
        .toIso8601String()
        .split('T')[0];
  }

  Future<void> recordAnswer(int wordId, bool isCorrect, {bool allowStreakIncrement = true}) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return;
    }

    final rows = await db.query(
      'words',
      columns: ['status', 'status_correct_streak'],
      where: 'id = ?',
      whereArgs: [wordId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }

    String status = rows.first['status']?.toString() ?? 'Learning';
    int streak = rows.first['status_correct_streak'] as int? ?? 0;

    final prefs = await SharedPreferences.getInstance();
    final int learningThreshold = prefs.getInt('promote_learning_correct') ?? 3;
    final int proficientThreshold = prefs.getInt('promote_proficient_correct') ?? 4;
    final int adeptThreshold = prefs.getInt('promote_adept_correct') ?? 5;

    String newStatus = status;
    int newStreak = streak;

    if (isCorrect) {
      if (allowStreakIncrement) {
        newStreak = streak + 1;
        if (status == 'Learning' && newStreak >= learningThreshold) {
          newStatus = 'Proficient';
          newStreak = 0;
        } else if (status == 'Proficient' && newStreak >= proficientThreshold) {
          newStatus = 'Adept';
          newStreak = 0;
        } else if (status == 'Adept' && newStreak >= adeptThreshold) {
          newStatus = 'Mastered';
          newStreak = 0;
        }
      } else {
        newStreak = streak;
      }
    } else {
      newStatus = _demoteStatus(status);
      newStreak = 0;
    }

    await db.update(
      'words',
      {
        'status': newStatus,
        'status_correct_streak': newStreak,
        'bucket_date': DateTime.now().toIso8601String(),
        'next_review_date': _nextReviewDateForStatus(newStatus),
      },
      where: 'id = ?',
      whereArgs: [wordId],
    );

    await logResult(wordId, isCorrect);

    final int activeLearningLimit = prefs.getInt('active_limit') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
  }

  Future<void> updateWordStatus(int id, String newStatus) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return;
    }

    await db.update(
      'words',
      {
        'status': newStatus, 
        'bucket_date': DateTime.now().toIso8601String(),
        'next_review_date': _nextReviewDateForStatus(newStatus),
        'status_correct_streak': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('active_limit') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
  }

  Future<void> logResult(int wordId, bool isCorrect) async {
    final db = await database;
    if (!await _hasTable(db, 'study_log')) {
      return;
    }
    await db.insert('study_log', {
      'word_id': wordId,
      'result': isCorrect ? 'Correct' : 'Incorrect',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return {
        'total': 0,
        'learned': 0,
        'mastered': 0,
        'learning': 0,
        'proficient': 0,
        'adept': 0,
        'on_deck': 0,
      };
    }

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('active_limit') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM words'));
    final learned = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM words WHERE status != 'New' AND status != 'Ignored'"));
    final mastered = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Mastered'"));
    final learning = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Learning'"));
    final proficient = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Proficient'"));
    final adept = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Adept'"));
    final onDeck = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'On Deck'"));
    
    return {
      'total': total ?? 0,
      'learned': learned ?? 0,
      'mastered': mastered ?? 0,
      'learning': learning ?? 0,
      'proficient': proficient ?? 0,
      'adept': adept ?? 0,
      'on_deck': onDeck ?? 0,
    };
  }

  Future<List<WordStats>> getWordsWithStats(String status) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }

    final hasStudyLog = await _hasTable(db, 'study_log');
    if (!hasStudyLog) {
      final rows = await db.query(
        'words',
        columns: ['id', 'word_stem', 'definition', 'original_context', 'status'],
        where: 'status = ?',
        whereArgs: [status],
        orderBy: 'word_stem COLLATE NOCASE',
      );
      return rows
          .map((row) => WordStats.fromMap({
                ...row,
                'total_attempts': 0,
                'correct_attempts': 0,
              }))
          .toList();
    }

    final rows = await db.rawQuery('''
      SELECT 
        w.id,
        w.word_stem,
        w.definition,
        w.original_context,
        w.status,
        COUNT(l.id) as total_attempts,
        SUM(CASE WHEN l.result = 'Correct' THEN 1 ELSE 0 END) as correct_attempts
      FROM words w
      LEFT JOIN study_log l ON l.word_id = w.id
      WHERE w.status = ?
      GROUP BY w.id
      ORDER BY w.word_stem COLLATE NOCASE
    ''', [status]);

    return rows.map((row) {
      final normalized = Map<String, dynamic>.from(row);
      normalized['total_attempts'] = normalized['total_attempts'] ?? 0;
      normalized['correct_attempts'] = normalized['correct_attempts'] ?? 0;
      return WordStats.fromMap(normalized);
    }).toList();
  }

  Future<List<QuizWordReport>> getQuizReportData(List<int> wordIds) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }
    if (wordIds.isEmpty) {
      return [];
    }

    final placeholders = List.filled(wordIds.length, '?').join(',');
    final hasStudyLog = await _hasTable(db, 'study_log');

    if (!hasStudyLog) {
      final rows = await db.query(
        'words',
        columns: ['id', 'word_stem', 'status', 'status_correct_streak', 'priority_tier'],
        where: 'id IN ($placeholders)',
        whereArgs: wordIds,
        orderBy: 'word_stem COLLATE NOCASE',
      );
      return rows
          .map((row) => QuizWordReport.fromMap({
                ...row,
                'total_attempts': 0,
                'correct_attempts': 0,
              }))
          .toList();
    }

    final rows = await db.rawQuery('''
      SELECT 
        w.id,
        w.word_stem,
        w.status,
        w.status_correct_streak,
        w.priority_tier,
        COUNT(l.id) as total_attempts,
        SUM(CASE WHEN l.result = 'Correct' THEN 1 ELSE 0 END) as correct_attempts
      FROM words w
      LEFT JOIN study_log l ON l.word_id = w.id
      WHERE w.id IN ($placeholders)
      GROUP BY w.id
      ORDER BY w.word_stem COLLATE NOCASE
    ''', wordIds);

    return rows.map((row) {
      final normalized = Map<String, dynamic>.from(row);
      normalized['total_attempts'] = normalized['total_attempts'] ?? 0;
      normalized['correct_attempts'] = normalized['correct_attempts'] ?? 0;
      normalized['status_correct_streak'] = normalized['status_correct_streak'] ?? 0;
      return QuizWordReport.fromMap(normalized);
    }).toList();
  }
}
