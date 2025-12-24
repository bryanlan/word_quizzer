import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'db_helper.dart';
import 'models.dart';
import 'quiz_report_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Word> sessionWords = [];
  int currentIndex = 0;
  bool isLoading = true;
  bool hasAnswered = false;
  bool showContext = false;
  bool usedContextHint = false;
  int contextIndex = 0;
  List<String> contextExamples = [];
  final Map<int, bool> sessionResults = {};
  
  List<String> currentOptions = [];
  String? selectedOption;
  String? feedbackMessage;
  Color feedbackColor = Colors.transparent;
  
  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _loadSession();
    _initTts();
  }
  
  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
  }

  Future<void> _loadSession() async {
    final words = await DatabaseHelper.instance.getDailyDeck();
    setState(() {
      sessionWords = words;
      isLoading = false;
    });
    if (words.isNotEmpty) {
      _loadOptionsForCurrent();
    }
  }

  Future<void> _loadOptionsForCurrent() async {
    if (sessionWords.isEmpty) return;
    final currentWord = sessionWords[currentIndex];
    final options = await DatabaseHelper.instance.getOptionsForWord(currentWord);
    final examples = await DatabaseHelper.instance.getExamplesForWord(currentWord.id);
    final mergedContexts = <String>[];
    final seen = <String>{};
    final baseContext = (currentWord.originalContext ?? '').trim();
    if (baseContext.isNotEmpty) {
      final key = baseContext.toLowerCase();
      if (!seen.contains(key)) {
        mergedContexts.add(baseContext);
        seen.add(key);
      }
    }
    for (final ex in examples) {
      final trimmed = ex.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final key = trimmed.toLowerCase();
      if (!seen.contains(key)) {
        mergedContexts.add(trimmed);
        seen.add(key);
      }
    }

    setState(() {
      currentOptions = options;
      hasAnswered = false;
      showContext = false;
      usedContextHint = false;
      contextIndex = 0;
      contextExamples = mergedContexts;
      selectedOption = null;
      feedbackMessage = null;
      feedbackColor = Colors.transparent;
    });
  }

  void _handleOptionSelected(String selectedOption) async {
    if (hasAnswered) return; // Prevent double taps

    final currentWord = sessionWords[currentIndex];
    final correctDefinition = currentWord.definition ?? "MISSING DEFINITION";
    final isCorrect = selectedOption == correctDefinition;
    setState(() {
      hasAnswered = true;
      this.selectedOption = selectedOption;
      if (isCorrect) {
        feedbackMessage = "Correct!";
        feedbackColor = Colors.green.withOpacity(0.2);
      } else {
        feedbackColor = Colors.red.withOpacity(0.2);
      }
    });

    await DatabaseHelper.instance.recordAnswer(
      currentWord.id,
      isCorrect,
      allowStreakIncrement: !usedContextHint,
    );
    sessionResults[currentWord.id] = isCorrect;

    if (isCorrect) {
      flutterTts.speak(currentWord.wordStem);
      // Auto advance after short delay
      Future.delayed(const Duration(seconds: 2), _nextWord);
    } else {
      _showFailureDialog(currentWord);
    }
  }

  Future<void> _showFailureDialog(Word word) async {
    String insult = await DatabaseHelper.instance.getRandomInsult();
    
    // ignore: use_build_context_synchronously
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Incorrect"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(insult, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.orange)),
            const SizedBox(height: 20),
            const Text("Definition:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(word.definition ?? "N/A"),
            const SizedBox(height: 20),
            const Text("Type the word to proceed:"),
            TextField(
              onChanged: (val) {
                if (val.trim().toLowerCase() == word.wordStem.toLowerCase()) {
                  Navigator.pop(ctx);
                  _nextWord();
                }
              },
              decoration: const InputDecoration(hintText: "Type here..."),
              autofocus: true,
            )
          ],
        ),
      ),
    );
  }

  void _nextWord() {
    if (currentIndex < sessionWords.length - 1) {
      setState(() {
        currentIndex++;
      });
      _loadOptionsForCurrent();
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => QuizReportScreen(
            words: sessionWords,
            results: sessionResults,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (sessionWords.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Daily Quiz")),
        body: const Center(child: Text("No words to review today! Good job.")),
      );
    }

    final currentWord = sessionWords[currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text("Word ${currentIndex + 1}/${sessionWords.length}"),
      ),
      body: Container(
        color: feedbackColor, // Flash effect
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildContextSection(),
                    const SizedBox(height: 24),
                    Text(
                      currentWord.wordStem,
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    if (currentWord.phonetic != null)
                       Text(currentWord.phonetic!, style: const TextStyle(color: Colors.tealAccent)),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Expanded(child: _buildOptions(currentWord)),
                  const SizedBox(height: 8),
                  Text(
                    "Proficiency Level: ${currentWord.status}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContextSection() {
    if (contextExamples.isEmpty) {
      return const SizedBox.shrink();
    }

    if (showContext) {
      final context = contextExamples[contextIndex];
      return Column(
        children: [
          GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) {
                return;
              }
              if (details.primaryVelocity! < 0) {
                _nextContext();
              } else if (details.primaryVelocity! > 0) {
                _previousContext();
              }
            },
            child: Text(
              context,
              textAlign: TextAlign.center,
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ),
          if (contextExamples.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    onPressed: _previousContext,
                  ),
                  Text(
                    "${contextIndex + 1}/${contextExamples.length}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    onPressed: _nextContext,
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return TextButton(
      onPressed: () {
        setState(() {
          showContext = true;
          usedContextHint = true;
        });
      },
      child: const Text("Reveal context"),
    );
  }

  void _nextContext() {
    if (contextExamples.isEmpty) {
      return;
    }
    setState(() {
      contextIndex = (contextIndex + 1) % contextExamples.length;
    });
  }

  void _previousContext() {
    if (contextExamples.isEmpty) {
      return;
    }
    setState(() {
      contextIndex = (contextIndex - 1 + contextExamples.length) % contextExamples.length;
    });
  }
  
  Widget _buildOptions(Word currentWord) {
    final correctDefinition = currentWord.definition ?? "MISSING DEFINITION";
    return ListView.builder(
      itemCount: currentOptions.length,
      itemBuilder: (context, index) {
        final option = currentOptions[index];
        Color tileColor = const Color(0xFF1E1E1E);
        
        // Highlight correct/incorrect after selection
        if (hasAnswered) {
          if (option == correctDefinition) {
            tileColor = Colors.green.withOpacity(0.5);
          } else if (option == selectedOption) {
            tileColor = Colors.red.withOpacity(0.5);
          }
        }
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: InkWell(
            onTap: () => _handleOptionSelected(option),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(option, style: const TextStyle(fontSize: 16)),
            ),
          ),
        );
      },
    );
  }
}
