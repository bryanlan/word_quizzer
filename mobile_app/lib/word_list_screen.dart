import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'db_helper.dart';
import 'models.dart';
import 'word_detail_screen.dart';
import 'tts_service.dart';

class WordListScreen extends StatefulWidget {
  final String status;
  final String title;

  const WordListScreen({
    super.key,
    required this.status,
    required this.title,
  });

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  bool isLoading = true;
  List<WordStats> words = [];
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _loadWords();
    _initTts();
  }

  Future<void> _initTts() async {
    await TtsService.configure(flutterTts);
  }

  void _speakWord(String word) {
    flutterTts.speak(word);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _loadWords() async {
    final data = widget.status == "All"
        ? await DatabaseHelper.instance.getAllWordsWithStats()
        : await DatabaseHelper.instance.getWordsWithStats(widget.status);
    setState(() {
      words = data;
      isLoading = false;
    });
  }

  String _statsText(WordStats stats) {
    final total = stats.totalAttempts;
    final correct = stats.correctAttempts;
    final statusLabel = widget.status == "All" ? "${stats.status} • " : "";
    if (total == 0) {
      return "${statusLabel}Tested 0 • NA correct";
    }
    final percent = ((correct / total) * 100).round();
    return "${statusLabel}Tested $total • $percent% correct";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : words.isEmpty
              ? const Center(child: Text("No words in this category yet."))
              : ListView.separated(
                  itemCount: words.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final word = words[index];
                    return ListTile(
                      title: Text(word.wordStem),
                      subtitle: Text(_statsText(word)),
                      trailing: IconButton(
                        icon: const Icon(Icons.volume_up, color: Colors.tealAccent),
                        onPressed: () => _speakWord(word.wordStem),
                        tooltip: 'Pronounce',
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => WordDetailScreen(word: word),
                          ),
                        );
                        _loadWords();
                      },
                    );
                  },
                ),
    );
  }
}
