import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'db_helper.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'word_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic> stats = {
    'total': 0,
    'learned': 0,
    'mastered': 0,
    'learning': 0,
    'proficient': 0,
    'adept': 0,
    'on_deck': 0,
  };
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  Future<void> _refreshStats() async {
    final s = await DatabaseHelper.instance.getStats();
    setState(() {
      stats = s;
      isLoading = false;
    });
  }

  Future<void> _importDb() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      String filePath = result.files.single.path!;
      try {
        await DatabaseHelper.instance.importDatabase(filePath);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database Imported Successfully!'))
        );
        _refreshStats();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing: $e'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vocab Master"),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
               Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StatsScreen()),
              );
            },
            tooltip: 'Analytics',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
               Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _importDb,
            tooltip: 'Import Database',
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Good Morning, Scholar.",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildStatCard("Total Words", stats['total'].toString(), Colors.blueAccent),
                      const SizedBox(width: 10),
                      _buildStatCard(
                        "On Deck",
                        stats['on_deck'].toString(),
                        Colors.amberAccent,
                        onTap: () => _openWordList("On Deck"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildStatCard(
                        "Learning",
                        stats['learning'].toString(),
                        Colors.orangeAccent,
                        onTap: () => _openWordList("Learning"),
                      ),
                      const SizedBox(width: 10),
                      _buildStatCard(
                        "Proficient",
                        stats['proficient'].toString(),
                        Colors.tealAccent,
                        onTap: () => _openWordList("Proficient"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildStatCard(
                        "Adept",
                        stats['adept'].toString(),
                        Colors.purpleAccent,
                        onTap: () => _openWordList("Adept"),
                      ),
                      const SizedBox(width: 10),
                      _buildStatCard("Mastered", stats['mastered'].toString(), Colors.greenAccent),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const QuizScreen()),
                      ).then((_) => _refreshStats());
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      "START DAILY QUIZ",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  void _openWordList(String status) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WordListScreen(
          status: status,
          title: "$status Words",
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
                Text(title, style: const TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
