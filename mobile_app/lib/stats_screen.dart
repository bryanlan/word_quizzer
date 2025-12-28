import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db_helper.dart';
import 'package:intl/intl.dart';
import 'daily_report_screen.dart';
import 'models.dart';
import 'transition_words_screen.dart';
import 'word_detail_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> troublesomeWords = [];
  List<BarChartGroupData> chartData = [];
  List<WeekOption> weekOptions = [];
  WeekOption? selectedWeek;
  int maxQuizCount = 0;
  WeeklyAnalytics weeklyAnalytics = WeeklyAnalytics(
    activity: [],
    totalQuizzes: 0,
    totalDays: 0,
    totalWords: 0,
    totalAttempts: 0,
    correctAttempts: 0,
    promotions: const {},
    demotions: const {},
    difficultyCounts: const {},
  );

  @override
  void initState() {
    super.initState();
    _initWeeks();
    _loadStats();
  }

  void _initWeeks() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    weekOptions = List.generate(8, (index) {
      final start = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      ).subtract(Duration(days: 7 * index));
      final end = start.add(const Duration(days: 6));
      final label = "${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)}";
      return WeekOption(start: start, label: label);
    });
    selectedWeek = weekOptions.first;
  }

  Future<void> _loadStats() async {
    final hasWords = await DatabaseHelper.instance.hasTable('words');
    if (!hasWords) {
      setState(() {
        troublesomeWords = [];
        chartData = _buildChartGroups([], DateTime.now());
        maxQuizCount = 0;
        isLoading = false;
      });
      return;
    }

    // 1. Get Troublesome Words
    final badWords = await DatabaseHelper.instance.getTroublesomeWords();

    WeeklyAnalytics analytics = WeeklyAnalytics(
      activity: [],
      totalQuizzes: 0,
      totalDays: 0,
      totalWords: 0,
      totalAttempts: 0,
      correctAttempts: 0,
      promotions: const {},
      demotions: const {},
      difficultyCounts: const {},
    );
    if (selectedWeek != null) {
      analytics = await DatabaseHelper.instance.getWeeklyAnalytics(selectedWeek!.start);
    }

    setState(() {
      troublesomeWords = badWords;
      weeklyAnalytics = analytics;
      chartData = _buildChartGroups(analytics.activity, selectedWeek?.start ?? DateTime.now());
      maxQuizCount = _maxQuizCount(analytics.activity);
      isLoading = false;
    });
  }

  List<BarChartGroupData> _buildChartGroups(List<Map<String, dynamic>> data, DateTime weekStart) {
    return List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      final dayData = data.firstWhere((element) => element['day'] == dateStr, orElse: () => {'count': 0});
      
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: (dayData['count'] as int).toDouble(),
            color: Colors.tealAccent,
            width: 16,
            borderRadius: BorderRadius.circular(4),
          )
        ],
      );
    });
  }

  int _maxQuizCount(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return 0;
    }
    int maxValue = 0;
    for (final row in data) {
      final count = row['count'] as int? ?? 0;
      if (count > maxValue) {
        maxValue = count;
      }
    }
    return maxValue;
  }

  double _leftInterval() {
    if (maxQuizCount <= 5) {
      return 1;
    }
    final interval = (maxQuizCount / 5).ceil();
    return interval.toDouble();
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

  Widget _buildTransitionRow({
    required String label,
    required int count,
    required String fromStatus,
    required String toStatus,
  }) {
    final canTap = count > 0 && selectedWeek != null;
    return InkWell(
      onTap: canTap
          ? () {
              final weekStart = selectedWeek!.start;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TransitionWordsScreen(
                    title: label,
                    fromStatus: fromStatus,
                    toStatus: toStatus,
                    weekStart: weekStart,
                  ),
                ),
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Row(
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: canTap ? Colors.grey : Colors.transparent,
                ),
              ],
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    final totalAttempts = weeklyAnalytics.totalAttempts;
    final correctAttempts = weeklyAnalytics.correctAttempts;
    final accuracy = totalAttempts > 0
        ? ((correctAttempts / totalAttempts) * 100).round()
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text("Analytics")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("Activity (Quizzes per Day)"),
                  if (selectedWeek != null)
                    DropdownButtonFormField<WeekOption>(
                      value: selectedWeek,
                      items: weekOptions
                          .map((option) => DropdownMenuItem(
                                value: option,
                                child: Text(option.label),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedWeek = value;
                          isLoading = true;
                        });
                        _loadStats();
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        barGroups: chartData,
                        maxY: maxQuizCount == 0 ? 1 : (maxQuizCount + 1).toDouble(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _leftInterval(),
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.white12,
                            strokeWidth: 1,
                          ),
                        ),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: Colors.black87,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final base = selectedWeek?.start ?? DateTime.now();
                              final date = base.add(Duration(days: group.x));
                              final label = DateFormat('EEE').format(date);
                              return BarTooltipItem(
                                "$label\n${rod.toY.toInt()} quizzes",
                                const TextStyle(color: Colors.white),
                              );
                            },
                          ),
                          touchCallback: (event, response) {
                            if (event is! FlTapUpEvent || response?.spot == null) {
                              return;
                            }
                            final index = response!.spot!.touchedBarGroupIndex;
                            final base = selectedWeek?.start ?? DateTime.now();
                            final date = base.add(Duration(days: index));
                            final day = DateFormat('yyyy-MM-dd').format(date);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DailyReportScreen(day: day),
                              ),
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final base = selectedWeek?.start ?? DateTime.now();
                                final date = base.add(Duration(days: value.toInt()));
                                return Text(DateFormat('E').format(date).substring(0, 1));
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              interval: _leftInterval(),
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionTitle("Weekly Summary"),
                  _buildSummaryRow("Total Quizzes", weeklyAnalytics.totalQuizzes.toString()),
                  _buildSummaryRow("Days With Quizzes", weeklyAnalytics.totalDays.toString()),
                  _buildSummaryRow("Words Reviewed", weeklyAnalytics.totalWords.toString()),
                  _buildSummaryRow("Accuracy", "$accuracy%"),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Promotions"),
                  _buildTransitionRow(
                    label: "Learning → Proficient",
                    count: weeklyAnalytics.promotions['Learning→Proficient'] ?? 0,
                    fromStatus: 'Learning',
                    toStatus: 'Proficient',
                  ),
                  _buildTransitionRow(
                    label: "Proficient → Adept",
                    count: weeklyAnalytics.promotions['Proficient→Adept'] ?? 0,
                    fromStatus: 'Proficient',
                    toStatus: 'Adept',
                  ),
                  _buildTransitionRow(
                    label: "Adept → Mastered",
                    count: weeklyAnalytics.promotions['Adept→Mastered'] ?? 0,
                    fromStatus: 'Adept',
                    toStatus: 'Mastered',
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Demotions"),
                  if (weeklyAnalytics.demotions.isEmpty)
                    const Text("No demotions yet.", style: TextStyle(color: Colors.grey))
                  else
                    ...(() {
                      final entries = weeklyAnalytics.demotions.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key));
                      return entries.map((entry) {
                        final parts = entry.key.split('→');
                        final from = parts.isNotEmpty ? parts.first : '';
                        final to = parts.length > 1 ? parts.last : '';
                        final label = parts.length > 1
                            ? '${parts.first} → ${parts.last}'
                            : entry.key;
                        return _buildTransitionRow(
                          label: label,
                          count: entry.value,
                          fromStatus: from,
                          toStatus: to,
                        );
                      }).toList();
                    })(),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Difficulty Histogram (Score 1-10)"),
                  _buildDistributionChips(weeklyAnalytics.difficultyCounts),
                  const SizedBox(height: 40),
                  _buildSectionTitle("Troublesome Words"),
                  if (troublesomeWords.isEmpty)
                    const Text("No data yet. Keep studying!", style: TextStyle(color: Colors.grey)),
                  ...troublesomeWords.map((w) => ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        title: Text(w['word_stem']),
                        trailing: Text("${w['fails']} fails"),
                        onTap: () async {
                          final rawId = w['id'];
                          final id = rawId is int
                              ? rawId
                              : int.tryParse(rawId?.toString() ?? '');
                          if (id == null) {
                            return;
                          }
                          final word = await DatabaseHelper.instance.getWordStatsById(id);
                          if (!mounted) {
                            return;
                          }
                          if (word == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Word not found.")),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WordDetailScreen(word: word),
                            ),
                          );
                        },
                      )),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
    );
  }
}

class WeekOption {
  final DateTime start;
  final String label;

  WeekOption({required this.start, required this.label});
}
