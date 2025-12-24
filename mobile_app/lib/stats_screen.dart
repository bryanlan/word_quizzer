import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db_helper.dart';
import 'package:intl/intl.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> troublesomeWords = [];
  List<BarChartGroupData> chartData = [];
  double masteryRate = 0.0;

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
        masteryRate = 0.0;
        chartData = _buildChartGroups([]);
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
        SELECT DATE(timestamp) as day, COUNT(*) as count
        FROM study_log
        WHERE timestamp >= DATE('now', '-7 days')
        GROUP BY day
        ORDER BY day ASC
      ''');
    }

    // 3. Mastery Rate
    final stats = await DatabaseHelper.instance.getStats();
    double rate = stats['total'] > 0 ? stats['mastered'] / stats['total'] : 0.0;

    setState(() {
      troublesomeWords = badWords;
      masteryRate = rate;
      chartData = _buildChartGroups(activity);
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
                  _buildSectionTitle("Mastery Progress"),
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 150,
                          height: 150,
                          child: CircularProgressIndicator(
                            value: masteryRate,
                            strokeWidth: 12,
                            backgroundColor: Colors.white10,
                            color: Colors.greenAccent,
                          ),
                        ),
                        Text(
                          "${(masteryRate * 100).toInt()}%",
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionTitle("Activity (Last 7 Days)"),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        barGroups: chartData,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
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
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
