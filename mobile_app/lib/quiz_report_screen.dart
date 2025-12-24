import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'models.dart';
import 'quiz_screen.dart';

class QuizReportScreen extends StatefulWidget {
  final List<Word> words;
  final Map<int, bool> results;

  const QuizReportScreen({
    super.key,
    required this.words,
    required this.results,
  });

  @override
  State<QuizReportScreen> createState() => _QuizReportScreenState();
}

class _QuizReportScreenState extends State<QuizReportScreen> {
  bool isLoading = true;
  List<QuizWordReport> reports = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final ids = widget.words.map((w) => w.id).toList();
    final data = await DatabaseHelper.instance.getQuizReportData(ids);
    setState(() {
      reports = data;
      isLoading = false;
    });
  }

  Map<String, int> _statusDistribution() {
    final counts = <String, int>{};
    for (final report in reports) {
      counts[report.status] = (counts[report.status] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _difficultyDistribution() {
    final counts = <String, int>{};
    for (final report in reports) {
      final label = _difficultyBucket(report.difficultyScore);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
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

  @override
  Widget build(BuildContext context) {
    final total = widget.results.length;
    final correct = widget.results.values.where((v) => v).length;
    final incorrect = total - correct;
    final accuracy = total > 0 ? ((correct / total) * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(title: const Text("Quiz Report")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const QuizScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Take New Quiz"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.popUntil(context, (route) => route.isFirst);
                          },
                          child: const Text("Return Home"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Summary"),
                  _buildSummaryRow("Total Questions", total.toString()),
                  _buildSummaryRow("Correct", correct.toString()),
                  _buildSummaryRow("Incorrect", incorrect.toString()),
                  _buildSummaryRow("Accuracy", "$accuracy%"),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Mastery Distribution"),
                  _buildDistributionChips(_statusDistribution()),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Difficulty Distribution (Score 1-10)"),
                  _buildDistributionChips(_difficultyDistribution()),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Word Details"),
                  ListView.separated(
                    itemCount: reports.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final report = reports[index];
                      final result = widget.results[report.id] ?? false;
                      return _buildWordTile(report, result);
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDistributionChips(Map<String, int> counts) {
    if (counts.isEmpty) {
      return const Text("No data yet.", style: TextStyle(color: Colors.grey));
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries
          .map((entry) => Chip(label: Text("${entry.key}: ${entry.value}")))
          .toList(),
    );
  }

  Widget _buildWordTile(QuizWordReport report, bool correctThisTime) {
    final total = report.totalAttempts;
    final correct = report.correctAttempts;
    final percent = total == 0 ? "NA" : "${((correct / total) * 100).round()}%";
    final resultLabel = correctThisTime ? "Correct" : "Incorrect";
    final resultColor = correctThisTime ? Colors.green : Colors.redAccent;

    return ListTile(
      title: Text(report.wordStem),
      subtitle: Text(
        "Level: ${report.status} • Tested $total • $percent correct • Streak ${report.currentStreak}",
      ),
      trailing: Text(
        resultLabel,
        style: TextStyle(color: resultColor, fontWeight: FontWeight.bold),
      ),
    );
  }
}
