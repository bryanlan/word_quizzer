import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'db_helper.dart';
import 'models.dart';
import 'word_detail_screen.dart';

class TransitionWordsScreen extends StatefulWidget {
  final String title;
  final String fromStatus;
  final String toStatus;
  final DateTime weekStart;

  const TransitionWordsScreen({
    super.key,
    required this.title,
    required this.fromStatus,
    required this.toStatus,
    required this.weekStart,
  });

  @override
  State<TransitionWordsScreen> createState() => _TransitionWordsScreenState();
}

class _TransitionWordsScreenState extends State<TransitionWordsScreen> {
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
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
  }

  Future<void> _loadWords() async {
    final data = await DatabaseHelper.instance.getWordsForStatusTransition(
      weekStart: widget.weekStart,
      fromStatus: widget.fromStatus,
      toStatus: widget.toStatus,
    );
    if (!mounted) return;
    setState(() {
      words = data;
      isLoading = false;
    });
  }

  void _speakWord(String word) {
    flutterTts.speak(word);
  }

  String _statsText(WordStats stats) {
    final total = stats.totalAttempts;
    final correct = stats.correctAttempts;
    if (total == 0) {
      return "Tested 0 • NA correct";
    }
    final percent = ((correct / total) * 100).round();
    return "Tested $total • $percent% correct";
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : words.isEmpty
              ? const Center(child: Text("No words for this transition yet."))
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
