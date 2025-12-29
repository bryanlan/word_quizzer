import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'db_import.dart';

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
    await _ensureBaseSchema(db);
    await _ensureOnDeckStatusSchema(db);
    await _ensureStudyLogSchema(db);
    await _ensureStatusLogSchema(db);
    await _ensureScoreLogSchema(db);
    await _ensureQuizSessionSchema(db);
    await _migratePausedStatus(db);
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
    if (!supportsDatabaseFileImport) {
      throw UnsupportedError('Database import is not supported on web.');
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vocab_master.db');

    // Close existing connection if open
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }

    await importDatabaseFile(sourcePath, path);

    _database = await _initDB('vocab_master.db');
    await _ensureBaseSchema(_database!);
    await _ensureOnDeckStatusSchema(_database!);
    await _ensureStudyLogSchema(_database!);
    await _ensureStatusLogSchema(_database!);
    await _ensureScoreLogSchema(_database!);
    await _ensureQuizSessionSchema(_database!);
    await _migratePausedStatus(_database!);
  }

  Future<void> _ensureBaseSchema(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_stem TEXT UNIQUE NOT NULL,
        original_context TEXT,
        book_title TEXT,
        definition TEXT,
        phonetic TEXT,
        status TEXT CHECK(status IN ('New', 'On Deck', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored')) DEFAULT 'New',
        bucket_date DATE,
        next_review_date DATE,
        difficulty_score INTEGER,
        priority_tier INTEGER,
        status_correct_streak INTEGER DEFAULT 0,
        manual_flag BOOLEAN DEFAULT 0,
        server_word_id INTEGER,
        updated_at TEXT
      );
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS examples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER,
        sentence TEXT,
        FOREIGN KEY (word_id) REFERENCES words (id)
      );
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS distractors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER,
        text TEXT,
        is_plausible BOOLEAN DEFAULT 1,
        FOREIGN KEY (word_id) REFERENCES words (id)
      );
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS study_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER,
        result TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        session_id TEXT,
        FOREIGN KEY (word_id) REFERENCES words (id)
      );
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS status_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        word_id INTEGER,
        from_status TEXT,
        to_status TEXT,
        FOREIGN KEY (word_id) REFERENCES words (id)
      );
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS score_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER,
        points INTEGER NOT NULL,
        reason TEXT,
        mode TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        session_id TEXT,
        FOREIGN KEY (word_id) REFERENCES words (id)
      );
    """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS insults (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT,
        severity INTEGER
      );
    """);
  }

  Future<void> _migratePausedStatus(Database db) async {
    if (!await _hasTable(db, 'words')) {
      return;
    }
    await db.update(
      'words',
      {
        'status': 'Ignored',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'status = ?',
      whereArgs: ['Pau(S)ed'],
    );
  }

  Future<void> _ensureStudyLogSchema(Database db) async {
    if (!await _hasTable(db, 'study_log')) {
      return;
    }

    final columns = await db.rawQuery("PRAGMA table_info(study_log)");
    final hasSessionId = columns.any((c) => c['name'] == 'session_id');
    if (!hasSessionId) {
      await db.execute("ALTER TABLE study_log ADD COLUMN session_id TEXT");
    }
  }

  Future<void> _ensureStatusLogSchema(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS status_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        word_id INTEGER,
        from_status TEXT,
        to_status TEXT,
        FOREIGN KEY (word_id) REFERENCES words (id)
      )
    """);
  }

  Future<void> _ensureScoreLogSchema(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS score_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id INTEGER,
        points INTEGER NOT NULL,
        reason TEXT,
        mode TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        session_id TEXT,
        FOREIGN KEY (word_id) REFERENCES words (id)
      )
    """);
  }

  Future<void> _ensureQuizSessionSchema(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS quiz_sessions (
        session_id TEXT PRIMARY KEY,
        started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        completed_at DATETIME
      )
    """);
  }

  Future<void> _ensureOnDeckStatusSchema(Database db) async {
    if (!await _hasTable(db, 'words')) {
      return;
    }

    final columns = await db.rawQuery("PRAGMA table_info(words)");
    final hasPriorityTier = columns.any((c) => c['name'] == 'priority_tier');
    final hasManualFlag = columns.any((c) => c['name'] == 'manual_flag');
    final hasStreak = columns.any((c) => c['name'] == 'status_correct_streak');
    final hasServerWordId = columns.any((c) => c['name'] == 'server_word_id');
    final hasUpdatedAt = columns.any((c) => c['name'] == 'updated_at');

    final tableSqlRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='words'");
    final tableSql = tableSqlRows.isNotEmpty
        ? (tableSqlRows.first['sql']?.toString() ?? '')
        : '';
    final hasOnDeck = tableSql.toLowerCase().contains('on deck');

    if (hasOnDeck) {
      await db.transaction((txn) async {
        if (!hasPriorityTier) {
          await txn
              .execute("ALTER TABLE words ADD COLUMN priority_tier INTEGER");
        }
        if (!hasManualFlag) {
          await txn.execute(
              "ALTER TABLE words ADD COLUMN manual_flag BOOLEAN DEFAULT 0");
        }
        if (!hasStreak) {
          await txn.execute(
              "ALTER TABLE words ADD COLUMN status_correct_streak INTEGER DEFAULT 0");
        }
        if (!hasServerWordId) {
          await txn
              .execute("ALTER TABLE words ADD COLUMN server_word_id INTEGER");
        }
        if (!hasUpdatedAt) {
          await txn.execute("ALTER TABLE words ADD COLUMN updated_at TEXT");
          await txn.execute(
              "UPDATE words SET updated_at = COALESCE(updated_at, CURRENT_TIMESTAMP)");
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
          status TEXT CHECK(status IN ('New', 'On Deck', 'Learning', 'Proficient', 'Adept', 'Mastered', 'Ignored')) DEFAULT 'New',
          bucket_date DATE,
          next_review_date DATE,
          difficulty_score INTEGER,
          priority_tier INTEGER,
          status_correct_streak INTEGER DEFAULT 0,
          manual_flag BOOLEAN DEFAULT 0,
          server_word_id INTEGER,
          updated_at TEXT
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
          manual_flag,
          server_word_id,
          updated_at
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
          ${hasManualFlag ? 'manual_flag' : '0'},
          NULL,
          CURRENT_TIMESTAMP
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
      var tier = rawTier is int
          ? rawTier
          : int.tryParse(rawTier?.toString() ?? '') ?? 3;
      if (tier <= 0) {
        tier = 3;
      }
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

  Future<void> _promoteOnDeckToLearning(
      Database db, int activeLearningLimit) async {
    if (!await _hasTable(db, 'words')) {
      return;
    }

    final activeCount = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM words WHERE status = 'Learning'")) ??
        0;
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
        'updated_at': now,
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
    required int biasLevel,
  }) async {
    if (limit <= 0) {
      return [];
    }

    if (biasLevel <= 0) {
      return _fetchRandomWordsForStatus(
        db,
        status: status,
        limit: limit,
        dueOnly: dueOnly,
        excludeIds: excludeIds,
      );
    }

    return _fetchWeightedWordsForStatus(
      db,
      status: status,
      limit: limit,
      dueOnly: dueOnly,
      excludeIds: excludeIds,
      biasLevel: biasLevel,
    );
  }

  Future<List<Word>> _fetchRandomWordsForStatus(
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
      whereParts
          .add("(next_review_date IS NULL OR next_review_date <= DATE('now'))");
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

  Future<List<Word>> _fetchWeightedWordsForStatus(
    Database db, {
    required String status,
    required int limit,
    required bool dueOnly,
    required Set<int> excludeIds,
    required int biasLevel,
  }) async {
    final whereParts = <String>["w.status = ?"];
    final args = <Object>[status];

    if (dueOnly) {
      whereParts.add(
          "(w.next_review_date IS NULL OR w.next_review_date <= DATE('now'))");
    }

    if (excludeIds.isNotEmpty) {
      final placeholders = List.filled(excludeIds.length, '?').join(',');
      whereParts.add("w.id NOT IN ($placeholders)");
      args.addAll(excludeIds);
    }

    final rows = await db.rawQuery('''
      SELECT
        w.id,
        w.word_stem,
        w.original_context,
        w.book_title,
        w.definition,
        w.phonetic,
        w.status,
        w.difficulty_score,
        w.priority_tier,
        w.bucket_date,
        COUNT(l.id) as attempts
      FROM words w
      LEFT JOIN study_log l
        ON l.word_id = w.id
       AND l.timestamp >= COALESCE(w.bucket_date, '1970-01-01')
      WHERE ${whereParts.join(' AND ')}
      GROUP BY w.id
    ''', args);

    if (rows.isEmpty) {
      return [];
    }

    final now = DateTime.now();
    final candidates = rows.map((row) {
      final bucketDate = row['bucket_date']?.toString();
      final attempts = row['attempts'] as int? ?? 0;
      final days = _daysInStatus(now, bucketDate);
      final exposureRate = days == 0 ? attempts.toDouble() : attempts / days;
      return _SelectionCandidate(
        word: Word.fromMap(row),
        exposureRate: exposureRate,
      );
    }).toList();

    return _pickCandidatesByBias(candidates, limit, biasLevel);
  }

  Future<List<Word>> getDailyDeck() async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    final int quizLength = prefs.getInt('quiz_length') ?? 20;
    final int maxLearning = prefs.getInt('max_learning') ?? 20;
    final int maxProficient = prefs.getInt('max_proficient') ?? 20;
    final int maxAdept = prefs.getInt('max_adept') ?? 30;
    final int masteredPct = prefs.getInt('pct_mastered') ?? 10;
    final int withinStageBias = prefs.getInt('within_stage_bias') ?? 1;

    if (quizLength <= 0) {
      return [];
    }

    await _promoteOnDeckToLearning(db, activeLearningLimit);

    final deck = <Word>[];
    final selectedIds = <int>{};
    final int masteredTarget =
        ((quizLength * masteredPct) / 100).round().clamp(0, quizLength);

    if (masteredTarget > 0) {
      final masteredWords = await _fetchWordsForStatus(
        db,
        status: 'Mastered',
        limit: masteredTarget,
        dueOnly: true,
        excludeIds: selectedIds,
        biasLevel: withinStageBias,
      );
      for (final word in masteredWords) {
        selectedIds.add(word.id);
      }
      deck.addAll(masteredWords);
    }

    var remaining = quizLength - deck.length;
    if (remaining > 0) {
      final countRows = await db.rawQuery('''
        SELECT status, COUNT(*) as count
        FROM words
        WHERE status IN ('Learning', 'Proficient', 'Adept')
        GROUP BY status
      ''');

      final counts = <String, int>{
        'Learning': 0,
        'Proficient': 0,
        'Adept': 0,
      };
      for (final row in countRows) {
        final status = row['status']?.toString();
        final count = row['count'] as int? ?? 0;
        if (status != null && counts.containsKey(status)) {
          counts[status] = count;
        }
      }

      final maxTargets = <String, int>{
        'Learning': maxLearning,
        'Proficient': maxProficient,
        'Adept': maxAdept,
      };

      final pressures = <String, double>{};
      for (final status in counts.keys) {
        final maxValue = maxTargets[status] ?? 1;
        final denom = maxValue <= 0 ? 1 : maxValue;
        pressures[status] = counts[status]! / denom;
      }

      final rng = Random();
      final exhausted = <String>{};
      final order = ['Learning', 'Proficient', 'Adept'];

      while (remaining > 0) {
        final candidates = order
            .where((status) =>
                !exhausted.contains(status) && (counts[status] ?? 0) > 0)
            .toList();
        if (candidates.isEmpty) {
          break;
        }

        final weights = <String, double>{};
        var totalWeight = 0.0;
        for (final status in candidates) {
          final weight = 1.0 + (pressures[status] ?? 0.0);
          weights[status] = weight;
          totalWeight += weight;
        }

        if (totalWeight <= 0) {
          break;
        }

        final pick = rng.nextDouble() * totalWeight;
        var cumulative = 0.0;
        String selectedStatus = candidates.first;
        for (final status in candidates) {
          cumulative += weights[status] ?? 0.0;
          if (pick <= cumulative) {
            selectedStatus = status;
            break;
          }
        }

        final words = await _fetchWordsForStatus(
          db,
          status: selectedStatus,
          limit: 1,
          dueOnly: selectedStatus != 'Learning',
          excludeIds: selectedIds,
          biasLevel: withinStageBias,
        );
        if (words.isEmpty) {
          exhausted.add(selectedStatus);
          continue;
        }

        final word = words.first;
        selectedIds.add(word.id);
        deck.add(word);
        remaining--;
      }

      if (remaining > 0) {
        for (final status in order) {
          if (remaining <= 0) {
            break;
          }
          final words = await _fetchWordsForStatus(
            db,
            status: status,
            limit: remaining,
            dueOnly: status != 'Learning',
            excludeIds: selectedIds,
            biasLevel: withinStageBias,
          );
          for (final word in words) {
            selectedIds.add(word.id);
          }
          deck.addAll(words);
          remaining = quizLength - deck.length;
        }
      }
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
          [word.id, 4 - options.length]);
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
    final List<Map<String, dynamic>> maps =
        await db.query('insults', orderBy: 'RANDOM()', limit: 1);
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

  String _promoteStatus(String status) {
    switch (status) {
      case 'Learning':
        return 'Proficient';
      case 'Proficient':
        return 'Adept';
      case 'Adept':
        return 'Mastered';
      default:
        return status;
    }
  }

  bool _isPromotion(String fromStatus, String toStatus) {
    return (fromStatus == 'Learning' && toStatus == 'Proficient') ||
        (fromStatus == 'Proficient' && toStatus == 'Adept') ||
        (fromStatus == 'Adept' && toStatus == 'Mastered');
  }

  bool _isDemotion(String fromStatus, String toStatus) {
    final fromRank = _statusRank(fromStatus);
    final toRank = _statusRank(toStatus);
    return fromRank > 0 && toRank > 0 && fromRank > toRank;
  }

  int _statusRank(String status) {
    switch (status) {
      case 'Learning':
        return 1;
      case 'Proficient':
        return 2;
      case 'Adept':
        return 3;
      case 'Mastered':
        return 4;
      default:
        return 0;
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

  Future<StatusChange?> recordAnswer(
    int wordId,
    bool isCorrect, {
    bool allowStreakIncrement = true,
    String? sessionId,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return null;
    }

    final rows = await db.query(
      'words',
      columns: ['status', 'status_correct_streak'],
      where: 'id = ?',
      whereArgs: [wordId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    String status = rows.first['status']?.toString() ?? 'Learning';
    int streak = rows.first['status_correct_streak'] as int? ?? 0;

    final prefs = await SharedPreferences.getInstance();
    final int learningThreshold = prefs.getInt('promote_learning_correct') ?? 3;
    final int proficientThreshold =
        prefs.getInt('promote_proficient_correct') ?? 4;
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
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [wordId],
    );

    if (newStatus != status && await _hasTable(db, 'status_log')) {
      await db.insert('status_log', {
        'word_id': wordId,
        'from_status': status,
        'to_status': newStatus,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    await logResult(wordId, isCorrect, sessionId: sessionId);
    final points = _pointsForAnswer(isCorrect, allowStreakIncrement);
    if (points > 0) {
      await logScore(
        wordId,
        points,
        reason: _reasonForAnswer(isCorrect, allowStreakIncrement),
        mode: 'multiple_choice',
        sessionId: sessionId,
      );
    }

    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
    if (newStatus != status) {
      return StatusChange(
        fromStatus: status,
        toStatus: newStatus,
        promoted: _isPromotion(status, newStatus),
      );
    }
    return null;
  }

  Future<StatusChange?> recordSelfGrade(
    int wordId,
    String grade, {
    String? sessionId,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return null;
    }

    final rows = await db.query(
      'words',
      columns: ['status', 'status_correct_streak'],
      where: 'id = ?',
      whereArgs: [wordId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final status = rows.first['status']?.toString() ?? 'Learning';
    final streak = rows.first['status_correct_streak'] as int? ?? 0;
    String newStatus = status;
    int newStreak = streak;
    bool isCorrect = grade != 'failed';

    final prefs = await SharedPreferences.getInstance();
    final int learningThreshold = prefs.getInt('promote_learning_correct') ?? 3;
    final int proficientThreshold =
        prefs.getInt('promote_proficient_correct') ?? 4;
    final int adeptThreshold = prefs.getInt('promote_adept_correct') ?? 5;

    if (grade == 'failed') {
      newStatus = 'Learning';
      newStreak = 0;
    } else if (grade == 'easy') {
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

    await db.update(
      'words',
      {
        'status': newStatus,
        'status_correct_streak': newStreak,
        'bucket_date': DateTime.now().toIso8601String(),
        'next_review_date': _nextReviewDateForStatus(newStatus),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [wordId],
    );

    if (newStatus != status && await _hasTable(db, 'status_log')) {
      await db.insert('status_log', {
        'word_id': wordId,
        'from_status': status,
        'to_status': newStatus,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    await logResult(wordId, isCorrect, sessionId: sessionId);
    final points = _pointsForSelfGrade(grade);
    if (points > 0) {
      await logScore(
        wordId,
        points,
        reason: _reasonForSelfGrade(grade),
        mode: 'self_graded',
        sessionId: sessionId,
      );
    }

    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
    if (newStatus != status) {
      return StatusChange(
        fromStatus: status,
        toStatus: newStatus,
        promoted: _isPromotion(status, newStatus),
      );
    }
    return null;
  }

  Future<void> recordQuizSessionStart(String sessionId) async {
    final db = await database;
    if (!await _hasTable(db, 'quiz_sessions')) {
      return;
    }
    await db.execute(
      '''
        INSERT OR IGNORE INTO quiz_sessions (session_id, started_at)
        VALUES (?, ?)
      ''',
      [sessionId, DateTime.now().toIso8601String()],
    );
  }

  Future<void> recordQuizSessionComplete(String sessionId) async {
    final db = await database;
    if (!await _hasTable(db, 'quiz_sessions')) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final updated = await db.update(
      'quiz_sessions',
      {'completed_at': now},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    if (updated == 0) {
      await db.insert(
        'quiz_sessions',
        {
          'session_id': sessionId,
          'started_at': now,
          'completed_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
  }

  int _pointsForAnswer(bool isCorrect, bool allowStreakIncrement) {
    if (!isCorrect) {
      return 0;
    }
    return allowStreakIncrement ? 10 : 6;
  }

  String _reasonForAnswer(bool isCorrect, bool allowStreakIncrement) {
    if (!isCorrect) {
      return 'mc_wrong';
    }
    return allowStreakIncrement ? 'mc_correct' : 'mc_correct_revealed';
  }

  int _pointsForSelfGrade(String grade) {
    switch (grade) {
      case 'easy':
        return 10;
      case 'hard':
        return 6;
      default:
        return 0;
    }
  }

  String _reasonForSelfGrade(String grade) {
    switch (grade) {
      case 'easy':
        return 'self_easy';
      case 'hard':
        return 'self_hard';
      default:
        return 'self_failed';
    }
  }

  Future<void> logResult(int wordId, bool isCorrect,
      {String? sessionId}) async {
    final db = await database;
    if (!await _hasTable(db, 'study_log')) {
      return;
    }
    await db.insert('study_log', {
      'word_id': wordId,
      'result': isCorrect ? 'Correct' : 'Incorrect',
      'timestamp': DateTime.now().toIso8601String(),
      'session_id': sessionId,
    });
  }

  Future<void> logScore(
    int wordId,
    int points, {
    String? reason,
    String? mode,
    String? sessionId,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'score_log')) {
      return;
    }
    await db.insert('score_log', {
      'word_id': wordId,
      'points': points,
      'reason': reason,
      'mode': mode,
      'timestamp': DateTime.now().toIso8601String(),
      'session_id': sessionId,
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
    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
    final total =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM words'));
    final learned = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM words WHERE status != 'New' AND status != 'Ignored'"));
    final mastered = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Mastered'"));
    final learning = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Learning'"));
    final proficient = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Proficient'"));
    final adept = Sqflite.firstIntValue(
        await db.rawQuery("SELECT COUNT(*) FROM words WHERE status = 'Adept'"));
    final onDeck = Sqflite.firstIntValue(await db
        .rawQuery("SELECT COUNT(*) FROM words WHERE status = 'On Deck'"));

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
        columns: [
          'id',
          'word_stem',
          'definition',
          'original_context',
          'status'
        ],
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

  Future<WordStats?> getWordStatsById(int id) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return null;
    }

    final hasStudyLog = await _hasTable(db, 'study_log');
    if (!hasStudyLog) {
      final rows = await db.query(
        'words',
        columns: [
          'id',
          'word_stem',
          'definition',
          'original_context',
          'status'
        ],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return WordStats.fromMap({
        ...rows.first,
        'total_attempts': 0,
        'correct_attempts': 0,
      });
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
      WHERE w.id = ?
      GROUP BY w.id
      LIMIT 1
    ''', [id]);

    if (rows.isEmpty) {
      return null;
    }
    final normalized = Map<String, dynamic>.from(rows.first);
    normalized['total_attempts'] = normalized['total_attempts'] ?? 0;
    normalized['correct_attempts'] = normalized['correct_attempts'] ?? 0;
    return WordStats.fromMap(normalized);
  }

  Future<List<WordStats>> getAllWordsWithStats() async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }

    final hasStudyLog = await _hasTable(db, 'study_log');
    if (!hasStudyLog) {
      final rows = await db.query(
        'words',
        columns: [
          'id',
          'word_stem',
          'definition',
          'original_context',
          'status'
        ],
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
      GROUP BY w.id
      ORDER BY w.word_stem COLLATE NOCASE
    ''');

    return rows.map((row) {
      final normalized = Map<String, dynamic>.from(row);
      normalized['total_attempts'] = normalized['total_attempts'] ?? 0;
      normalized['correct_attempts'] = normalized['correct_attempts'] ?? 0;
      return WordStats.fromMap(normalized);
    }).toList();
  }

  Future<List<WordSummary>> getWordSummaries({
    String? status,
    int? tier,
    String? startsWith,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }

    final whereParts = <String>[];
    final args = <Object?>[];

    if (status != null && status != 'All') {
      whereParts.add('status = ?');
      args.add(status);
    }

    if (tier != null) {
      if (tier <= 0) {
        whereParts.add('(priority_tier IS NULL OR priority_tier = 0)');
      } else {
        whereParts.add('priority_tier = ?');
        args.add(tier);
      }
    }

    if (startsWith != null && startsWith.isNotEmpty && startsWith != 'All') {
      if (startsWith == '#') {
        whereParts.add("substr(word_stem, 1, 1) NOT GLOB '[A-Za-z]'");
      } else {
        whereParts.add('upper(word_stem) LIKE ?');
        args.add('${startsWith.toUpperCase()}%');
      }
    }

    final trimmedSearch = (search ?? '').trim().toLowerCase();
    if (trimmedSearch.isNotEmpty) {
      whereParts.add('lower(word_stem) LIKE ?');
      args.add('%$trimmedSearch%');
    }

    final whereClause = whereParts.isEmpty ? null : whereParts.join(' AND ');

    final rows = await db.query(
      'words',
      columns: ['id', 'word_stem', 'status', 'priority_tier'],
      where: whereClause,
      whereArgs: args,
      orderBy: 'word_stem COLLATE NOCASE',
      limit: limit,
      offset: offset,
    );

    return rows.map((row) => WordSummary.fromMap(row)).toList();
  }

  Future<List<int>> getWordIdsForFilter({
    String? status,
    int? tier,
    String? startsWith,
    String? search,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return [];
    }

    final whereParts = <String>[];
    final args = <Object?>[];

    if (status != null && status != 'All') {
      whereParts.add('status = ?');
      args.add(status);
    }

    if (tier != null) {
      if (tier <= 0) {
        whereParts.add('(priority_tier IS NULL OR priority_tier = 0)');
      } else {
        whereParts.add('priority_tier = ?');
        args.add(tier);
      }
    }

    if (startsWith != null && startsWith.isNotEmpty && startsWith != 'All') {
      if (startsWith == '#') {
        whereParts.add("substr(word_stem, 1, 1) NOT GLOB '[A-Za-z]'");
      } else {
        whereParts.add('upper(word_stem) LIKE ?');
        args.add('${startsWith.toUpperCase()}%');
      }
    }

    final trimmedSearch = (search ?? '').trim().toLowerCase();
    if (trimmedSearch.isNotEmpty) {
      whereParts.add('lower(word_stem) LIKE ?');
      args.add('%$trimmedSearch%');
    }

    final whereClause = whereParts.isEmpty ? null : whereParts.join(' AND ');

    final rows = await db.query(
      'words',
      columns: ['id'],
      where: whereClause,
      whereArgs: args,
      orderBy: 'word_stem COLLATE NOCASE',
    );

    return rows.map((row) => row['id'] as int).toList();
  }

  Future<Map<int, String>> getWordStemsByIds(List<int> ids) async {
    final db = await database;
    if (!await _hasTable(db, 'words') || ids.isEmpty) {
      return {};
    }

    final result = <int, String>{};
    const int chunkSize = 900;
    for (var start = 0; start < ids.length; start += chunkSize) {
      final chunk = ids.sublist(
        start,
        start + chunkSize > ids.length ? ids.length : start + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'words',
        columns: ['id', 'word_stem'],
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );

      for (final row in rows) {
        final id = row['id'] as int? ?? 0;
        if (id == 0) continue;
        result[id] = row['word_stem']?.toString() ?? '';
      }
    }
    return result;
  }

  Future<Word?> getWordById(int id) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return null;
    }
    final rows = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Word.fromMap(rows.first);
  }

  Future<void> updateWordTier(int id, int? tier) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return;
    }
    await db.update(
      'words',
      {
        'priority_tier': tier ?? 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateWordTierBatch(List<int> ids, int? tier) async {
    final db = await database;
    if (!await _hasTable(db, 'words') || ids.isEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'words',
          {
            'priority_tier': tier ?? 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> updateWordStatusBatch(List<int> ids, String status) async {
    final db = await database;
    if (!await _hasTable(db, 'words') || ids.isEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'words',
          {
            'status': status,
            'bucket_date': now,
            'next_review_date': _nextReviewDateForStatus(status),
            'status_correct_streak': 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);
  }

  Future<void> updateWordDefinition(int id, String definition) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return;
    }
    await db.update(
      'words',
      {
        'definition': definition.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getDistractorsForWord(int wordId) async {
    final db = await database;
    if (!await _hasTable(db, 'distractors')) {
      return [];
    }
    final rows = await db.query(
      'distractors',
      columns: ['text'],
      where: 'word_id = ?',
      whereArgs: [wordId],
      orderBy: 'id',
    );
    return rows
        .map((row) => row['text']?.toString() ?? '')
        .where((text) => text.trim().isNotEmpty)
        .toList();
  }

  Future<void> replaceExamplesForWord(int wordId, List<String> examples) async {
    final db = await database;
    if (!await _hasTable(db, 'examples')) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        'examples',
        where: 'word_id = ?',
        whereArgs: [wordId],
      );
      for (final example in examples) {
        final trimmed = example.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        await txn.insert('examples', {
          'word_id': wordId,
          'sentence': trimmed,
        });
      }
      await txn.update(
        'words',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [wordId],
      );
    });
  }

  Future<void> replaceDistractorsForWord(
      int wordId, List<String> distractors) async {
    final db = await database;
    if (!await _hasTable(db, 'distractors')) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        'distractors',
        where: 'word_id = ?',
        whereArgs: [wordId],
      );
      for (final distractor in distractors) {
        final trimmed = distractor.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        await txn.insert('distractors', {
          'word_id': wordId,
          'text': trimmed,
        });
      }
      await txn.update(
        'words',
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [wordId],
      );
    });
  }

  Future<List<WordStats>> getWordsForStatusTransition({
    required DateTime weekStart,
    required String fromStatus,
    required String toStatus,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'words') || !await _hasTable(db, 'status_log')) {
      return [];
    }

    final startStr = weekStart.toIso8601String().split('T')[0];
    final endStr =
        weekStart.add(const Duration(days: 6)).toIso8601String().split('T')[0];
    final hasStudyLog = await _hasTable(db, 'study_log');

    if (!hasStudyLog) {
      final rows = await db.rawQuery('''
        SELECT DISTINCT w.id, w.word_stem, w.definition, w.original_context, w.status
        FROM status_log s
        JOIN words w ON s.word_id = w.id
        WHERE s.from_status = ? AND s.to_status = ?
          AND DATE(s.timestamp) BETWEEN ? AND ?
        ORDER BY w.word_stem COLLATE NOCASE
      ''', [fromStatus, toStatus, startStr, endStr]);
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
      FROM (
        SELECT DISTINCT word_id
        FROM status_log
        WHERE from_status = ? AND to_status = ?
          AND DATE(timestamp) BETWEEN ? AND ?
      ) s
      JOIN words w ON s.word_id = w.id
      LEFT JOIN study_log l ON l.word_id = w.id
      GROUP BY w.id
      ORDER BY w.word_stem COLLATE NOCASE
    ''', [fromStatus, toStatus, startStr, endStr]);

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
        columns: [
          'id',
          'word_stem',
          'status',
          'status_correct_streak',
          'difficulty_score'
        ],
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
        w.difficulty_score,
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
      normalized['status_correct_streak'] =
          normalized['status_correct_streak'] ?? 0;
      return QuizWordReport.fromMap(normalized);
    }).toList();
  }

  Future<WeeklyAnalytics> getWeeklyAnalytics(DateTime weekStart) async {
    final db = await database;
    if (!await _hasTable(db, 'quiz_sessions')) {
      return WeeklyAnalytics(
        activity: [],
        totalQuizzes: 0,
        totalDays: 0,
        totalWords: 0,
        totalAttempts: 0,
        correctAttempts: 0,
        promotions: {},
        demotions: {},
        difficultyCounts: {},
      );
    }

    final startStr = weekStart.toIso8601String().split('T')[0];
    final endStr =
        weekStart.add(const Duration(days: 6)).toIso8601String().split('T')[0];

    final completedByDay = <String, int>{};
    final completedDays = await db.rawQuery('''
      SELECT DATE(completed_at) as day, COUNT(*) as count
      FROM quiz_sessions
      WHERE completed_at IS NOT NULL AND DATE(completed_at) BETWEEN ? AND ?
      GROUP BY day
      ORDER BY day
    ''', [startStr, endStr]);
    for (final row in completedDays) {
      final day = row['day']?.toString();
      if (day == null || day.isEmpty) {
        continue;
      }
      completedByDay[day] = row['count'] as int? ?? 0;
    }

    final activity = <Map<String, dynamic>>[];
    var totalQuizzes = 0;
    var totalDays = 0;
    for (var i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final dayStr = date.toIso8601String().split('T')[0];
      final count = completedByDay[dayStr] ?? 0;
      if (count <= 0) {
        continue;
      }
      activity.add({'day': dayStr, 'count': count});
      totalQuizzes += count;
      totalDays += 1;
    }

    int totalWords = 0;
    int totalAttempts = 0;
    int correctAttempts = 0;
    if (totalQuizzes > 0 && await _hasTable(db, 'study_log')) {
      final totalWordsRows = await db.rawQuery('''
        WITH completed_sessions AS (
          SELECT session_id
          FROM quiz_sessions
          WHERE completed_at IS NOT NULL AND DATE(completed_at) BETWEEN ? AND ?
        )
        SELECT COUNT(DISTINCT word_id) as count
        FROM study_log
        WHERE session_id IN (SELECT session_id FROM completed_sessions)
      ''', [startStr, endStr]);
      totalWords = totalWordsRows.isNotEmpty
          ? (totalWordsRows.first['count'] as int? ?? 0)
          : 0;

      final attemptsRows = await db.rawQuery('''
        WITH completed_sessions AS (
          SELECT session_id
          FROM quiz_sessions
          WHERE completed_at IS NOT NULL AND DATE(completed_at) BETWEEN ? AND ?
        )
        SELECT COUNT(*) as total_attempts,
               SUM(CASE WHEN result = 'Correct' THEN 1 ELSE 0 END) as correct_attempts
        FROM study_log
        WHERE session_id IN (SELECT session_id FROM completed_sessions)
      ''', [startStr, endStr]);
      totalAttempts = attemptsRows.isNotEmpty
          ? (attemptsRows.first['total_attempts'] as int? ?? 0)
          : 0;
      correctAttempts = attemptsRows.isNotEmpty
          ? (attemptsRows.first['correct_attempts'] as int? ?? 0)
          : 0;
    }

    final promotions = <String, int>{
      'Learning→Proficient': 0,
      'Proficient→Adept': 0,
      'Adept→Mastered': 0,
    };
    final demotions = <String, int>{
      'Mastered→Adept': 0,
      'Adept→Proficient': 0,
      'Proficient→Learning': 0,
    };
    if (await _hasTable(db, 'status_log')) {
      final rows = await db.rawQuery('''
        SELECT from_status, to_status, COUNT(*) as count
        FROM status_log
        WHERE DATE(timestamp) BETWEEN ? AND ?
        GROUP BY from_status, to_status
      ''', [startStr, endStr]);
      for (final row in rows) {
        final from = row['from_status']?.toString() ?? '';
        final to = row['to_status']?.toString() ?? '';
        final count = row['count'] as int? ?? 0;
        if (from == 'Learning' && to == 'Proficient') {
          promotions['Learning→Proficient'] = count;
        } else if (from == 'Proficient' && to == 'Adept') {
          promotions['Proficient→Adept'] = count;
        } else if (from == 'Adept' && to == 'Mastered') {
          promotions['Adept→Mastered'] = count;
        }
        if (_isDemotion(from, to)) {
          final key = '$from→$to';
          demotions[key] = (demotions[key] ?? 0) + count;
        }
      }
    }

    final difficultyCounts = <String, int>{};
    if (totalQuizzes > 0 &&
        await _hasTable(db, 'study_log') &&
        await _hasTable(db, 'words')) {
      final rows = await db.rawQuery('''
        WITH completed_sessions AS (
          SELECT session_id
          FROM quiz_sessions
          WHERE completed_at IS NOT NULL AND DATE(completed_at) BETWEEN ? AND ?
        ),
        reviewed_words AS (
          SELECT DISTINCT word_id
          FROM study_log
          WHERE session_id IN (SELECT session_id FROM completed_sessions)
        )
        SELECT w.difficulty_score
        FROM reviewed_words r
        JOIN words w ON r.word_id = w.id
      ''', [startStr, endStr]);

      for (final row in rows) {
        final score = row['difficulty_score'] as int? ?? 0;
        final bucket = _difficultyBucket(score);
        difficultyCounts[bucket] = (difficultyCounts[bucket] ?? 0) + 1;
      }
    }

    return WeeklyAnalytics(
      activity: activity,
      totalQuizzes: totalQuizzes,
      totalDays: totalDays,
      totalWords: totalWords,
      totalAttempts: totalAttempts,
      correctAttempts: correctAttempts,
      promotions: promotions,
      demotions: demotions,
      difficultyCounts: difficultyCounts,
    );
  }

  Future<List<Map<String, dynamic>>> getTroublesomeWords({
    int days = 28,
    int limit = 5,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'quiz_sessions') ||
        !await _hasTable(db, 'study_log') ||
        !await _hasTable(db, 'words')) {
      return [];
    }

    final sinceDate = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .split('T')[0];
    final rows = await db.rawQuery('''
      WITH recent_sessions AS (
        SELECT session_id
        FROM quiz_sessions
        WHERE completed_at IS NOT NULL AND DATE(completed_at) >= ?
      )
      SELECT w.id, w.word_stem, COUNT(*) as fails
      FROM study_log l
      JOIN recent_sessions s ON l.session_id = s.session_id
      JOIN words w ON l.word_id = w.id
      WHERE l.result = 'Incorrect'
      GROUP BY w.id, w.word_stem
      ORDER BY fails DESC, w.word_stem COLLATE NOCASE
      LIMIT ?
    ''', [sinceDate, limit]);

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  String _difficultyBucket(int score) {
    if (score <= 0) {
      return "Unknown";
    }
    if (score <= 2) {
      return "1-2";
    }
    if (score <= 4) {
      return "3-4";
    }
    if (score <= 6) {
      return "5-6";
    }
    if (score <= 8) {
      return "7-8";
    }
    return "9-10";
  }

  int _daysInStatus(DateTime now, String? bucketDate) {
    if (bucketDate == null || bucketDate.trim().isEmpty) {
      return 1;
    }
    final parsed = DateTime.tryParse(bucketDate);
    if (parsed == null) {
      return 1;
    }
    final days = now.difference(parsed).inDays + 1;
    return days <= 0 ? 1 : days;
  }

  List<Word> _pickCandidatesByBias(
    List<_SelectionCandidate> candidates,
    int limit,
    int biasLevel,
  ) {
    if (candidates.isEmpty || limit <= 0) {
      return [];
    }
    if (biasLevel <= 0) {
      candidates.shuffle();
      return candidates.take(limit).map((c) => c.word).toList();
    }

    final rng = Random();
    if (biasLevel >= 2) {
      final sorted = [...candidates]
        ..sort((a, b) => a.exposureRate.compareTo(b.exposureRate));
      final selected = <Word>[];
      var i = 0;
      const tolerance = 0.000001;
      while (i < sorted.length && selected.length < limit) {
        final rate = sorted[i].exposureRate;
        final bucket = <_SelectionCandidate>[];
        while (i < sorted.length &&
            (sorted[i].exposureRate - rate).abs() <= tolerance) {
          bucket.add(sorted[i]);
          i++;
        }
        bucket.shuffle(rng);
        for (final candidate in bucket) {
          if (selected.length >= limit) {
            break;
          }
          selected.add(candidate.word);
        }
      }
      return selected;
    }

    const double alpha = 0.7;
    final pool = [...candidates];
    final selected = <Word>[];
    while (pool.isNotEmpty && selected.length < limit) {
      var totalWeight = 0.0;
      final weights = <double>[];
      for (final candidate in pool) {
        final weight = 1 / pow(1 + candidate.exposureRate, alpha);
        weights.add(weight);
        totalWeight += weight;
      }
      if (totalWeight <= 0) {
        break;
      }
      final pick = rng.nextDouble() * totalWeight;
      var cumulative = 0.0;
      var index = 0;
      for (var i = 0; i < pool.length; i++) {
        cumulative += weights[i];
        if (pick <= cumulative) {
          index = i;
          break;
        }
      }
      selected.add(pool[index].word);
      pool.removeAt(index);
    }
    return selected;
  }

  Future<int> getQuizCountForDate(DateTime date) async {
    final db = await database;
    final day = date.toIso8601String().split('T')[0];
    if (!await _hasTable(db, 'quiz_sessions')) {
      return 0;
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM quiz_sessions
      WHERE completed_at IS NOT NULL AND DATE(completed_at) = ?
    ''', [day]);
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['count'] as int? ?? 0;
  }

  Future<int> getScoreForDate(DateTime date, {DateTime? since}) async {
    final db = await database;
    if (!await _hasTable(db, 'score_log')) {
      return 0;
    }

    final day = date.toIso8601String().split('T')[0];
    final whereParts = <String>["DATE(timestamp) = ?"];
    final args = <Object>[day];
    if (since != null) {
      whereParts.add("timestamp >= ?");
      args.add(since.toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT SUM(points) as total
      FROM score_log
      WHERE ${whereParts.join(' AND ')}
    ''', args);
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['total'] as int? ?? 0;
  }

  Future<int> getHighScore({DateTime? since}) async {
    final db = await database;
    if (!await _hasTable(db, 'score_log')) {
      return 0;
    }

    final whereParts = <String>[];
    final args = <Object>[];
    if (since != null) {
      whereParts.add("timestamp >= ?");
      args.add(since.toIso8601String());
    }

    final whereSql =
        whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT DATE(timestamp) as day, SUM(points) as total
      FROM score_log
      $whereSql
      GROUP BY day
      ORDER BY total DESC
      LIMIT 1
    ''', args);
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first['total'] as int? ?? 0;
  }

  Future<bool> wordExists(String wordStem) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return false;
    }

    final rows = await db.query(
      'words',
      columns: ['id'],
      where: 'LOWER(word_stem) = ?',
      whereArgs: [wordStem.toLowerCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int?> addWordWithEnrichment({
    required String wordStem,
    required String status,
    required int priorityTier,
    required String definition,
    required List<String> examples,
    required List<String> distractors,
  }) async {
    final db = await database;
    if (!await _hasTable(db, 'words')) {
      return null;
    }

    final existing = await db.query(
      'words',
      columns: ['id'],
      where: 'LOWER(word_stem) = ?',
      whereArgs: [wordStem.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return null;
    }

    final now = DateTime.now().toIso8601String();
    String? initialContext;
    for (final example in examples) {
      final trimmed = example.trim();
      if (trimmed.isNotEmpty) {
        initialContext = trimmed;
        break;
      }
    }
    final wordId = await db.transaction<int>((txn) async {
      final id = await txn.insert('words', {
        'word_stem': wordStem,
        'definition': definition,
        'status': status,
        'priority_tier': priorityTier,
        'difficulty_score': 0,
        'original_context': initialContext,
        'bucket_date': now,
        'next_review_date': _nextReviewDateForStatus(status),
        'status_correct_streak': 0,
        'manual_flag': 1,
        'updated_at': now,
      });

      for (final example in examples) {
        final trimmed = example.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        await txn.insert('examples', {
          'word_id': id,
          'sentence': trimmed,
        });
      }

      for (final distractor in distractors) {
        final trimmed = distractor.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        await txn.insert('distractors', {
          'word_id': id,
          'text': trimmed,
        });
      }

      return id;
    });

    final prefs = await SharedPreferences.getInstance();
    final int activeLearningLimit = prefs.getInt('max_learning') ?? 20;
    await _promoteOnDeckToLearning(db, activeLearningLimit);

    return wordId;
  }

  Future<DailyQuizReport> getDailyReport(String day) async {
    final db = await database;
    if (!await _hasTable(db, 'quiz_sessions') ||
        !await _hasTable(db, 'study_log') ||
        !await _hasTable(db, 'words')) {
      return DailyQuizReport(
        reports: [],
        lastResults: {},
        totalAttempts: 0,
        correctAttempts: 0,
      );
    }

    final sessionRows = await db.rawQuery('''
      SELECT session_id
      FROM quiz_sessions
      WHERE completed_at IS NOT NULL AND DATE(completed_at) = ?
      ORDER BY completed_at
    ''', [day]);
    final sessionIds = <String>[];
    for (final row in sessionRows) {
      final id = row['session_id']?.toString();
      if (id == null || id.isEmpty) {
        continue;
      }
      sessionIds.add(id);
    }
    if (sessionIds.isEmpty) {
      return DailyQuizReport(
        reports: [],
        lastResults: {},
        totalAttempts: 0,
        correctAttempts: 0,
      );
    }

    final placeholders = List.filled(sessionIds.length, '?').join(',');
    final summaryRows = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_attempts,
        SUM(CASE WHEN result = 'Correct' THEN 1 ELSE 0 END) as correct_attempts
      FROM study_log
      WHERE session_id IN ($placeholders)
    ''', sessionIds);

    int totalAttempts = 0;
    int correctAttempts = 0;
    if (summaryRows.isNotEmpty) {
      final row = summaryRows.first;
      totalAttempts = row['total_attempts'] as int? ?? 0;
      correctAttempts = row['correct_attempts'] as int? ?? 0;
    }

    if (totalAttempts == 0) {
      return DailyQuizReport(
        reports: [],
        lastResults: {},
        totalAttempts: 0,
        correctAttempts: 0,
      );
    }

    final rows = await db.rawQuery('''
      WITH day_logs AS (
        SELECT 
          word_id,
          MAX(id) as last_id
        FROM study_log
        WHERE session_id IN ($placeholders)
        GROUP BY word_id
      ),
      all_logs AS (
        SELECT
          word_id,
          COUNT(*) as total_attempts,
          SUM(CASE WHEN result = 'Correct' THEN 1 ELSE 0 END) as correct_attempts
        FROM study_log
        GROUP BY word_id
      ),
      last_results AS (
        SELECT 
          l.word_id,
          l.result as last_result
        FROM study_log l
        JOIN day_logs d ON l.id = d.last_id
      )
      SELECT 
        w.id,
        w.word_stem,
        w.status,
        w.status_correct_streak,
        w.difficulty_score,
        COALESCE(a.total_attempts, 0) as total_attempts,
        COALESCE(a.correct_attempts, 0) as correct_attempts,
        lr.last_result
      FROM day_logs d
      JOIN words w ON w.id = d.word_id
      LEFT JOIN all_logs a ON a.word_id = w.id
      LEFT JOIN last_results lr ON lr.word_id = w.id
      ORDER BY w.word_stem COLLATE NOCASE
    ''', sessionIds);

    final reports = <QuizWordReport>[];
    final lastResults = <int, bool>{};
    for (final row in rows) {
      final normalized = Map<String, dynamic>.from(row);
      normalized['status_correct_streak'] =
          normalized['status_correct_streak'] ?? 0;
      normalized['total_attempts'] = normalized['total_attempts'] ?? 0;
      normalized['correct_attempts'] = normalized['correct_attempts'] ?? 0;
      final report = QuizWordReport.fromMap(normalized);
      reports.add(report);

      final lastResult = row['last_result']?.toString();
      if (lastResult != null) {
        lastResults[report.id] = lastResult == 'Correct';
      }
    }

    return DailyQuizReport(
      reports: reports,
      lastResults: lastResults,
      totalAttempts: totalAttempts,
      correctAttempts: correctAttempts,
    );
  }
}

class _SelectionCandidate {
  final Word word;
  final double exposureRate;

  _SelectionCandidate({
    required this.word,
    required this.exposureRate,
  });
}
