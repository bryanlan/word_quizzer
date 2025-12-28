import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'db_helper.dart';
import 'models.dart';
import 'tts_service.dart';
import 'widgets/speaker_button.dart';

class WordDetailScreen extends StatefulWidget {
  final WordStats word;

  const WordDetailScreen({super.key, required this.word});

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  static const List<String> statusOptions = [
    'New',
    'On Deck',
    'Learning',
    'Proficient',
    'Adept',
    'Mastered',
    'Ignored',
    'Pau(S)ed',
  ];

  late String currentStatus;
  bool isSaving = false;
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    currentStatus = statusOptions.contains(widget.word.status)
        ? widget.word.status
        : 'New';
    _initTts();
  }

  Future<void> _initTts() async {
    await TtsService.configure(flutterTts);
  }

  void _speakWord(String word) {
    flutterTts.speak(word);
  }

  String _percentCorrect() {
    if (widget.word.totalAttempts == 0) return "NA";
    final percent = (widget.word.correctAttempts / widget.word.totalAttempts) * 100;
    return "${percent.round()}%";
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final definition = widget.word.definition ?? "MISSING DEFINITION";
    final usage = (widget.word.originalContext ?? "").trim();

    return Scaffold(
      appBar: AppBar(title: Text(widget.word.wordStem)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.word.wordStem,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                SpeakerButton(
                  onPressed: () => _speakWord(widget.word.wordStem),
                  size: 36,
                  backgroundColor: Colors.white10,
                  iconColor: Colors.tealAccent,
                ),
              ],
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
              "Tested ${widget.word.totalAttempts} times • ${_percentCorrect()} correct",
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Text(
              "Update Status",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[200]),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: currentStatus,
              items: statusOptions
                  .map((status) => DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      ))
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) async {
                      if (value == null || value == currentStatus) {
                        return;
                      }
                      setState(() {
                        isSaving = true;
                      });
                      await DatabaseHelper.instance.updateWordStatus(widget.word.id, value);
                      if (!mounted) return;
                      setState(() {
                        currentStatus = value;
                        isSaving = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Status updated to $value")),
                      );
                    },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
            if (isSaving)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
