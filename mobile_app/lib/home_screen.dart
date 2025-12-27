import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'db_helper.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'word_list_screen.dart';
import 'add_word_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db_import.dart';
import 'word_enrichment_service.dart';
import 'auth_service.dart';
import 'sync_service.dart';
import 'pwa_update.dart';

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
  String displayName = "Scholar";
  String apiKey = '';
  bool canAddWord = false;
  int quizzesToday = 0;
  int todayScore = 0;
  int highScore = 0;

  @override
  void initState() {
    super.initState();
    _refreshStats();
    _loadDisplayName();
    _loadApiKey();
  }

  Future<void> _refreshStats() async {
    final s = await DatabaseHelper.instance.getStats();
    final count = await DatabaseHelper.instance.getQuizCountForDate(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    final resetAtStr = prefs.getString('score_reset_at');
    final resetAt = resetAtStr == null ? null : DateTime.tryParse(resetAtStr);
    final todayScoreValue = await DatabaseHelper.instance
        .getScoreForDate(DateTime.now(), since: resetAt);
    final highScoreValue =
        await DatabaseHelper.instance.getHighScore(since: resetAt);
    setState(() {
      stats = s;
      quizzesToday = count;
      todayScore = todayScoreValue;
      highScore = highScoreValue;
      isLoading = false;
    });
  }

  Future<void> _loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('display_name') ?? '').trim();
    setState(() {
      displayName = name.isEmpty ? "Scholar" : name;
    });
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      final configured = await WordEnrichmentService.serverKeyConfigured();
      if (!mounted) return;
      setState(() {
        apiKey = '';
        canAddWord = configured;
      });
      return;
    }
    setState(() {
      apiKey = prefs.getString('openrouter_api_key') ?? '';
      canAddWord = apiKey.trim().isNotEmpty;
    });
  }

  Future<void> _runSilentSync() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty || AuthService.isTokenExpired(token)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('sync_server_url') ??
        'https://word-quizzer-api.bryanlangley.org';
    if (url.trim().isEmpty) {
      return;
    }
    try {
      final service = SyncService(baseUrl: url, token: token);
      await service.sync();
      await prefs.setString('last_sync_at', DateTime.now().toIso8601String());
    } catch (_) {
      // Silent refresh.
    }
  }

  Future<void> _handlePullToRefresh() async {
    await _runSilentSync();
    await _refreshStats();
    if (kIsWeb) {
      await refreshApp();
    }
  }

  String _timeOfDayLabel() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return "Morning";
    }
    if (hour >= 12 && hour < 18) {
      return "Afternoon";
    }
    return "Evening";
  }

  String _buildAddWordSummary(
    List<String> added,
    List<String> skipped,
    List<String> failed,
  ) {
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add('Added ${added.length}');
    }
    if (skipped.isNotEmpty) {
      parts.add('Skipped ${skipped.length}');
    }
    if (failed.isNotEmpty) {
      parts.add('Failed ${failed.length}');
    }
    if (parts.isEmpty) {
      return '';
    }
    return '${parts.join('. ')}.';
  }

  Future<void> _importDb() async {
    if (!supportsDatabaseFileImport) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Import Unavailable"),
          content: const Text(
            "Database import isn't supported in the web app yet. "
            "Use the desktop app to import, or add words manually.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      final filePath = result.files.single.path;
      if (filePath == null || filePath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read selected file.')),
        );
        return;
      }
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
            icon: Icon(
              Icons.add,
              color: canAddWord ? null : Colors.grey,
            ),
            onPressed: () {
              if (!canAddWord) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("OpenRouter Key Required"),
                    content: Text(
                      kIsWeb
                          ? "The server OpenRouter key isn't configured yet."
                          : "Add your OpenRouter API key in Settings to create new words.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddWordScreen(),
                ),
              ).then((result) {
                _refreshStats();
                if (result is Map) {
                  final added = (result['added'] as List?)?.cast<String>() ?? [];
                  final skipped = (result['skipped'] as List?)?.cast<String>() ?? [];
                  final failed = (result['failed'] as List?)?.cast<String>() ?? [];
                  final message = _buildAddWordSummary(added, skipped, failed);
                  if (message.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                } else if (result is String && result.trim().isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added \"$result\".')),
                  );
                }
              });
            },
            tooltip: 'Add Word',
          ),
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
              ).then((_) {
                _loadApiKey();
                _loadDisplayName();
                _refreshStats();
              });
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
          : RefreshIndicator(
              onRefresh: _handlePullToRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Good ${_timeOfDayLabel()}, $displayName.",
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "Quizzes taken today: $quizzesToday",
                              style: const TextStyle(fontSize: 16, color: Colors.tealAccent),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _buildStatCard(
                                "Total Words",
                                stats['total'].toString(),
                                Colors.blueAccent,
                                onTap: () => _openWordList("All"),
                              ),
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
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "Today's score: $todayScore • High score: $highScore",
                              style: const TextStyle(fontSize: 16, color: Colors.tealAccent),
                            ),
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
                  ),
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
