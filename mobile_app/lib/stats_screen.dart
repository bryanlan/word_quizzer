import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db_helper.dart';
import 'package:intl/intl.dart';
import 'daily_report_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> troublesomeWords = [];
  List<BarChartGroupData> chartData = [];
  int maxQuizCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = await DatabaseHelper.instance.database;
    final hasWords = await DatabaseHelper.instance.hasTable('words');
    if (!hasWords) {
      setState(() {
        troublesomeWords = [];
        chartData = _buildChartGroups([]);
        maxQuizCount = 0;
        isLoading = false;
      });
      return;
    }

    final hasStudyLog = await DatabaseHelper.instance.hasTable('study_log');

    // 1. Get Troublesome Words
    List<Map<String, dynamic>> badWords = [];
    if (hasStudyLog) {
      badWords = await db.rawQuery('''
        SELECT w.word_stem, COUNT(*) as fails
        FROM study_log l
        JOIN words w ON l.word_id = w.id
        WHERE l.result = 'Incorrect'
        GROUP BY word_id
        HAVING fails > 1
        ORDER BY fails DESC
        LIMIT 5
      ''');
    }

    // 2. Get Last 7 Days Activity
    List<Map<String, dynamic>> activity = [];
    if (hasStudyLog) {
      activity = await db.rawQuery('''
        SELECT
          DATE(timestamp) as day,
          COUNT(DISTINCT COALESCE(session_id, DATE(timestamp))) as count
        FROM study_log
        WHERE timestamp >= DATE('now', '-7 days')
        GROUP BY day
        ORDER BY day ASC
      ''');
    }

    setState(() {
      troublesomeWords = badWords;
      chartData = _buildChartGroups(activity);
      maxQuizCount = _maxQuizCount(activity);
      isLoading = false;
    });
  }

  List<BarChartGroupData> _buildChartGroups(List<Map<String, dynamic>> data) {
    // Map dates to 0-6
    return List.generate(7, (index) {
      final date = DateTime.now().subtract(Duration(days: 6 - index));
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

  @override
  Widget build(BuildContext context) {
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
                              final date = DateTime.now()
                                  .subtract(Duration(days: 6 - group.x));
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
                            final date = DateTime.now()
                                .subtract(Duration(days: 6 - index));
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
                                final date = DateTime.now().subtract(Duration(days: 6 - value.toInt()));
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
                  _buildSectionTitle("Troublesome Words"),
                  if (troublesomeWords.isEmpty)
                    const Text("No data yet. Keep studying!", style: TextStyle(color: Colors.grey)),
                  ...troublesomeWords.map((w) => ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        title: Text(w['word_stem']),
                        trailing: Text("${w['fails']} fails"),
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
