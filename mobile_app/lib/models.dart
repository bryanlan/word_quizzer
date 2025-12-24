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
      priorityTier: map['priority_tier'] ?? 3,
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
  final int priorityTier;

  QuizWordReport({
    required this.id,
    required this.wordStem,
    required this.status,
    required this.totalAttempts,
    required this.correctAttempts,
    required this.currentStreak,
    required this.priorityTier,
  });

  factory QuizWordReport.fromMap(Map<String, dynamic> map) {
    return QuizWordReport(
      id: map['id'],
      wordStem: map['word_stem'],
      status: map['status'] ?? '',
      totalAttempts: map['total_attempts'] ?? 0,
      correctAttempts: map['correct_attempts'] ?? 0,
      currentStreak: map['status_correct_streak'] ?? 0,
      priorityTier: map['priority_tier'] ?? 3,
    );
  }
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
