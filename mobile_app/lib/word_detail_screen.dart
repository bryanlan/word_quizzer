import 'package:flutter/material.dart';
import 'models.dart';

class WordDetailScreen extends StatelessWidget {
  final WordStats word;

  const WordDetailScreen({super.key, required this.word});

  String _percentCorrect() {
    if (word.totalAttempts == 0) return "NA";
    final percent = (word.correctAttempts / word.totalAttempts) * 100;
    return "${percent.round()}%";
  }

  @override
  Widget build(BuildContext context) {
    final definition = word.definition ?? "MISSING DEFINITION";
    final usage = (word.originalContext ?? "").trim();

    return Scaffold(
      appBar: AppBar(title: Text(word.wordStem)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              word.wordStem,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "Definition",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[200]),
            ),
            const SizedBox(height: 6),
            Text(definition),
            const SizedBox(height: 16),
            Text(
              "Usage",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[200]),
            ),
            const SizedBox(height: 6),
            Text(usage.isEmpty ? "No usage context available." : usage),
            const SizedBox(height: 24),
            Text(
              "Tested ${word.totalAttempts} times • ${_percentCorrect()} correct",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
