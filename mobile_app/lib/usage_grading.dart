class UsageGradeResult {
  final String grade; // 'failed' | 'hard' | 'easy'
  final String feedback;
  final List<String> whyWrong;
  final List<String> improvements;
  final String correctedExample;
  final List<String> similarExamples;
  final List<String> subtleties;

  const UsageGradeResult({
    required this.grade,
    required this.feedback,
    this.whyWrong = const [],
    this.improvements = const [],
    this.correctedExample = '',
    this.similarExamples = const [],
    this.subtleties = const [],
  });
}
