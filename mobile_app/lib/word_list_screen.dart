import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'models.dart';
import 'word_detail_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final data = await DatabaseHelper.instance.getWordsWithStats(widget.status);
    setState(() {
      words = data;
      isLoading = false;
    });
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
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => WordDetailScreen(word: word),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
