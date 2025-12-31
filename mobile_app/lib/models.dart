class Word {
  final int id;
  final String wordStem;
  final String? originalContext;
  final String? bookTitle;
  final String? definition;
  final String? phonetic;
  final String status;
  final int difficultyScore;
  final int priorityTier;

  Word({
    required this.id,
    required this.wordStem,
    this.originalContext,
    this.bookTitle,
    this.definition,
    this.phonetic,
    required this.status,
    required this.difficultyScore,
    required this.priorityTier,
  });

  factory Word.fromMap(Map<String, dynamic> map) {
    return Word(
      id: map['id'],
      wordStem: map['word_stem'],
      originalContext: map['original_context'],
      bookTitle: map['book_title'],
      definition: map['definition'],
      phonetic: map['phonetic'],
      status: map['status'],
      difficultyScore: map['difficulty_score'] ?? 0,
      priorityTier: map['priority_tier'] ?? 0,
    );
  }
}

class WordSummary {
  final int id;
  final String wordStem;
  final String status;
  final int? priorityTier;

  WordSummary({
    required this.id,
    required this.wordStem,
    required this.status,
    required this.priorityTier,
  });

  factory WordSummary.fromMap(Map<String, dynamic> map) {
    final tierValue = map['priority_tier'];
    final tier = tierValue == null ? null : (tierValue as int?);
    return WordSummary(
      id: map['id'],
      wordStem: map['word_stem']?.toString() ?? '',
      status: map['status']?.toString() ?? '',
      priorityTier: tier == null || tier == 0 ? null : tier,
    );
  }
}

class WordStats {
  final int id;
  final String wordStem;
  final String? definition;
  final String? originalContext;
  final String status;
  final int totalAttempts;
  final int correctAttempts;

  WordStats({
    required this.id,
    required this.wordStem,
    required this.definition,
    required this.originalContext,
    required this.status,
    required this.totalAttempts,
    required this.correctAttempts,
  });

  factory WordStats.fromMap(Map<String, dynamic> map) {
    return WordStats(
      id: map['id'],
      wordStem: map['word_stem'],
      definition: map['definition'],
      originalContext: map['original_context'],
      status: map['status'] ?? '',
      totalAttempts: map['total_attempts'] ?? 0,
      correctAttempts: map['correct_attempts'] ?? 0,
    );
  }
}

class QuizWordReport {
  final int id;
  final String wordStem;
  final String status;
  final int totalAttempts;
  final int correctAttempts;
  final int currentStreak;
  final int difficultyScore;

  QuizWordReport({
    required this.id,
    required this.wordStem,
    required this.status,
    required this.totalAttempts,
    required this.correctAttempts,
    required this.currentStreak,
    required this.difficultyScore,
  });

  factory QuizWordReport.fromMap(Map<String, dynamic> map) {
    return QuizWordReport(
      id: map['id'],
      wordStem: map['word_stem'],
      status: map['status'] ?? '',
      totalAttempts: map['total_attempts'] ?? 0,
      correctAttempts: map['correct_attempts'] ?? 0,
      currentStreak: map['status_correct_streak'] ?? 0,
      difficultyScore: map['difficulty_score'] ?? 0,
    );
  }
}

class DailyQuizReport {
  final List<QuizWordReport> reports;
  final Map<int, bool> lastResults;
  final int totalAttempts;
  final int correctAttempts;

  DailyQuizReport({
    required this.reports,
    required this.lastResults,
    required this.totalAttempts,
    required this.correctAttempts,
  });
}

class WeeklyAnalytics {
  final List<Map<String, dynamic>> activity;
  final int totalQuizzes;
  final int totalDays;
  final int totalWords;
  final int totalAttempts;
  final int correctAttempts;
  final Map<String, int> promotions;
  final Map<String, int> demotions;
  final Map<String, int> difficultyCounts;

  WeeklyAnalytics({
    required this.activity,
    required this.totalQuizzes,
    required this.totalDays,
    required this.totalWords,
    required this.totalAttempts,
    required this.correctAttempts,
    required this.promotions,
    required this.demotions,
    required this.difficultyCounts,
  });
}

class Distractor {
  final int id;
  final int wordId;
  final String text;

  Distractor({required this.id, required this.wordId, required this.text});

  factory Distractor.fromMap(Map<String, dynamic> map) {
    return Distractor(
      id: map['id'],
      wordId: map['word_id'],
      text: map['text'],
    );
  }
}

class Example {
  final int id;
  final int wordId;
  final String sentence;

  Example({required this.id, required this.wordId, required this.sentence});

  factory Example.fromMap(Map<String, dynamic> map) {
    return Example(
      id: map['id'],
      wordId: map['word_id'],
      sentence: map['sentence'],
    );
  }
}

class StatusChange {
  final String fromStatus;
  final String toStatus;
  final bool promoted;

  StatusChange({
    required this.fromStatus,
    required this.toStatus,
    required this.promoted,
  });
}

/// Represents a difficulty level for word packs
class DifficultyLevel {
  final int level;
  final String name;
  final String description;
  final List<String> sampleWords;

  const DifficultyLevel({
    required this.level,
    required this.name,
    required this.description,
    required this.sampleWords,
  });

  factory DifficultyLevel.fromJson(Map<String, dynamic> json) {
    return DifficultyLevel(
      level: json['level'] as int,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      sampleWords: (json['sample_words'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  static const List<DifficultyLevel> levels = [
    DifficultyLevel(
      level: 1,
      name: 'Mid High School',
      description: 'Core vocabulary for academic success',
      sampleWords: [],
    ),
    DifficultyLevel(
      level: 2,
      name: 'Early College',
      description: 'Expanding academic and literary vocabulary',
      sampleWords: [],
    ),
    DifficultyLevel(
      level: 3,
      name: 'College Graduate',
      description: 'Professional and sophisticated vocabulary',
      sampleWords: [],
    ),
    DifficultyLevel(
      level: 4,
      name: 'Advanced / Well-Read',
      description: 'Scholarly and specialized vocabulary',
      sampleWords: [],
    ),
    DifficultyLevel(
      level: 5,
      name: 'Elite',
      description: 'Rare and exceptional vocabulary',
      sampleWords: [],
    ),
  ];
}

/// Represents a word pack metadata
class WordPack {
  final String id;
  final String name;
  final int difficultyLevel;
  final String description;
  final int wordCount;
  final bool isBundled;
  final String? assetPath;

  const WordPack({
    required this.id,
    required this.name,
    required this.difficultyLevel,
    required this.description,
    required this.wordCount,
    required this.isBundled,
    this.assetPath,
  });

  factory WordPack.fromJson(Map<String, dynamic> json, {bool isBundled = true}) {
    return WordPack(
      id: json['id'] as String,
      name: json['name'] as String,
      difficultyLevel: json['difficulty_level'] as int,
      description: json['description'] as String? ?? '',
      wordCount: json['word_count'] as int? ?? 30,
      isBundled: isBundled,
      assetPath: json['asset_path'] as String?,
    );
  }
}

/// Represents a word within a pack (pre-enriched)
class PackWord {
  final String wordStem;
  final String definition;
  final int difficultyScore;
  final List<String> examples;
  final List<String> distractors;

  const PackWord({
    required this.wordStem,
    required this.definition,
    required this.difficultyScore,
    required this.examples,
    required this.distractors,
  });

  factory PackWord.fromJson(Map<String, dynamic> json) {
    return PackWord(
      wordStem: json['word_stem'] as String,
      definition: json['definition'] as String,
      difficultyScore: json['difficulty_score'] as int? ?? 5,
      examples: (json['examples'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      distractors: (json['distractors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

/// Complete pack data including words
class WordPackData {
  final WordPack metadata;
  final List<PackWord> words;

  const WordPackData({
    required this.metadata,
    required this.words,
  });

  factory WordPackData.fromJson(Map<String, dynamic> json, {bool isBundled = true}) {
    final words = (json['words'] as List<dynamic>?)
            ?.map((w) => PackWord.fromJson(w as Map<String, dynamic>))
            .toList() ??
        [];
    return WordPackData(
      metadata: WordPack(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        difficultyLevel: json['difficulty_level'] as int? ?? 1,
        description: json['description'] as String? ?? '',
        wordCount: words.length,
        isBundled: isBundled,
        assetPath: json['asset_path'] as String?,
      ),
      words: words,
    );
  }
}

/// Word pack manifest containing all available packs
class WordPackManifest {
  final int version;
  final List<DifficultyLevel> difficultyLevels;
  final List<WordPack> packs;

  const WordPackManifest({
    required this.version,
    required this.difficultyLevels,
    required this.packs,
  });

  factory WordPackManifest.fromJson(Map<String, dynamic> json) {
    return WordPackManifest(
      version: json['version'] as int? ?? 1,
      difficultyLevels: (json['difficulty_levels'] as List<dynamic>?)
              ?.map((l) => DifficultyLevel.fromJson(l as Map<String, dynamic>))
              .toList() ??
          DifficultyLevel.levels,
      packs: (json['packs'] as List<dynamic>?)
              ?.map((p) => WordPack.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Data for importing a word from a pack
class PackWordImport {
  final String wordStem;
  final String definition;
  final String status;
  final int difficultyScore;
  final List<String> examples;
  final List<String> distractors;

  const PackWordImport({
    required this.wordStem,
    required this.definition,
    required this.status,
    required this.difficultyScore,
    required this.examples,
    required this.distractors,
  });
}

/// Result of importing a word pack
class PackImportResult {
  final int added;
  final int skipped;

  const PackImportResult({
    required this.added,
    required this.skipped,
  });
}
