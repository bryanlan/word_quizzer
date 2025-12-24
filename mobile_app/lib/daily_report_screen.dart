import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'db_helper.dart';
import 'models.dart';

class DailyReportScreen extends StatefulWidget {
  final String day;

  const DailyReportScreen({
    super.key,
    required this.day,
  });

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  bool isLoading = true;
  List<QuizWordReport> reports = [];
  Map<int, bool> lastResults = {};
  int totalAttempts = 0;
  int correctAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final data = await DatabaseHelper.instance.getDailyReport(widget.day);
    setState(() {
      reports = data.reports;
      lastResults = data.lastResults;
      totalAttempts = data.totalAttempts;
      correctAttempts = data.correctAttempts;
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
    final incorrectAttempts = totalAttempts - correctAttempts;
    final accuracy = totalAttempts > 0
        ? ((correctAttempts / totalAttempts) * 100).round()
        : 0;
    final dayDate = DateTime.tryParse(widget.day) ?? DateTime.now();
    final dayLabel = DateFormat('EEE, MMM d').format(dayDate);

    return Scaffold(
      appBar: AppBar(title: const Text("Daily Report")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("Summary"),
                  Text(dayLabel, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  _buildSummaryRow("Total Questions", totalAttempts.toString()),
                  _buildSummaryRow("Correct", correctAttempts.toString()),
                  _buildSummaryRow("Incorrect", incorrectAttempts.toString()),
                  _buildSummaryRow("Accuracy", "$accuracy%"),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Mastery Distribution"),
                  _buildDistributionChips(_statusDistribution()),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Difficulty Distribution (Score 1-10)"),
                  _buildDistributionChips(_difficultyDistribution()),
                  const SizedBox(height: 24),
                  _buildSectionTitle("Word Details"),
                  if (reports.isEmpty)
                    const Text(
                      "No quiz data for this day.",
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    ListView.separated(
                      itemCount: reports.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final report = reports[index];
                        final result = lastResults[report.id];
                        return _buildWordTile(report, result);
                      },
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Back to Analytics"),
                  ),
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

  Widget _buildWordTile(QuizWordReport report, bool? correctThisDay) {
    final total = report.totalAttempts;
    final correct = report.correctAttempts;
    final percent = total == 0 ? "NA" : "${((correct / total) * 100).round()}%";
    final resultLabel = correctThisDay == null
        ? "No result"
        : (correctThisDay ? "Correct" : "Incorrect");
    final resultColor = correctThisDay == null
        ? Colors.grey
        : (correctThisDay ? Colors.green : Colors.redAccent);

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
