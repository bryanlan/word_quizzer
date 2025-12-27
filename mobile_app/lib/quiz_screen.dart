import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'db_helper.dart';
import 'models.dart';
import 'quiz_report_screen.dart';
import 'tts_service.dart';

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
  bool showSelfAnswer = false;
  int contextIndex = 0;
  List<String> contextExamples = [];
  List<String> llmExamples = [];
  String originalContextText = '';
  final Map<int, bool> sessionResults = {};
  final Map<int, bool> contextRevealUsed = {};
  late final String sessionId;
  
  List<String> currentOptions = [];
  String? selectedOption;
  String? feedbackMessage;
  Color feedbackColor = Colors.transparent;
  
  FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    sessionId = _createSessionId();
    _loadSession();
    _initTts();
  }
  
  Future<void> _initTts() async {
    await TtsService.configure(flutterTts);
  }

  void _speakWord(String word) {
    flutterTts.speak(word);
  }

  void _maybeShowPromotion(String wordStem, StatusChange? change) {
    if (change == null || !change.promoted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Promoted! $wordStem -> ${change.toStatus}.')),
    );
  }

  Future<void> _loadSession() async {
    final words = await DatabaseHelper.instance.getDailyDeck();
    setState(() {
      sessionWords = words;
      contextRevealUsed.clear();
      isLoading = false;
    });
    if (words.isNotEmpty) {
      _loadOptionsForCurrent();
    }
  }

  Future<void> _loadOptionsForCurrent() async {
    if (sessionWords.isEmpty) return;
    final currentWord = sessionWords[currentIndex];
    setState(() {
      currentOptions = [];
      hasAnswered = false;
      showContext = false;
      usedContextHint = false;
      showSelfAnswer = false;
      contextExamples = [];
      llmExamples = [];
      originalContextText = '';
      feedbackMessage = null;
      feedbackColor = Colors.transparent;
      selectedOption = null;
      contextRevealUsed[currentWord.id] = false;
    });
    final options = await DatabaseHelper.instance.getOptionsForWord(currentWord);
    final examples = await DatabaseHelper.instance.getExamplesForWord(currentWord.id);
    final mergedContexts = <String>[];
    final seen = <String>{};
    final baseContext = (currentWord.originalContext ?? '').trim();
    if (baseContext.isNotEmpty) {
      final shortened = _shortenContext(baseContext);
      if (shortened.isNotEmpty) {
        final key = shortened.toLowerCase();
        if (!seen.contains(key)) {
          mergedContexts.add(shortened);
          seen.add(key);
        }
      }
    }
    final cleanedExamples = _cleanExampleList(examples);
    for (final ex in cleanedExamples) {
      final key = ex.toLowerCase();
      if (!seen.contains(key)) {
        mergedContexts.add(ex);
        seen.add(key);
      }
    }

    setState(() {
      currentOptions = options;
      hasAnswered = false;
      showContext = false;
      usedContextHint = false;
      showSelfAnswer = false;
      contextIndex = 0;
      contextExamples = mergedContexts;
      llmExamples = cleanedExamples;
      originalContextText = baseContext.isEmpty ? '' : _shortenContext(baseContext);
      selectedOption = null;
      feedbackMessage = null;
      feedbackColor = Colors.transparent;
    });
  }

  String _shortenContext(String text) {
    var trimmed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    const maxChars = 180;
    if (trimmed.length > maxChars) {
      trimmed = "${trimmed.substring(0, maxChars - 3).trimRight()}...";
    }

    return trimmed;
  }

  List<String> _cleanExampleList(List<String> items) {
    final cleaned = <String>[];
    final seen = <String>{};
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final shortened = _shortenContext(trimmed);
      if (shortened.isEmpty) {
        continue;
      }
      final key = shortened.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      cleaned.add(shortened);
    }
    return cleaned;
  }

  void _handleOptionSelected(String selectedOption) async {
    if (hasAnswered) return; // Prevent double taps

    final currentWord = sessionWords[currentIndex];
    final correctDefinition = currentWord.definition ?? "MISSING DEFINITION";
    final isCorrect = selectedOption == correctDefinition;
    final revealed = contextRevealUsed[currentWord.id] ?? usedContextHint;
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

    final statusChange = await DatabaseHelper.instance.recordAnswer(
      currentWord.id,
      isCorrect,
      allowStreakIncrement: !revealed,
      sessionId: sessionId,
    );
    sessionResults[currentWord.id] = isCorrect;
    _maybeShowPromotion(currentWord.wordStem, statusChange);

    if (isCorrect) {
      _speakWord(currentWord.wordStem);
      // Auto advance after short delay
      Future.delayed(const Duration(seconds: 1), _nextWord);
    } else {
      _showFailureDialog(currentWord);
    }
  }

  String _createSessionId() {
    final rand = Random();
    return "${DateTime.now().millisecondsSinceEpoch}-${rand.nextInt(1000000)}";
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
            const SizedBox(height: 12),
            const Text("Word:", style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(child: Text(word.wordStem)),
                IconButton(
                  icon: const Icon(Icons.volume_up, color: Colors.tealAccent),
                  onPressed: () => _speakWord(word.wordStem),
                  tooltip: 'Pronounce',
                ),
              ],
            ),
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
    final isSelfGraded = _isSelfGraded(currentWord.status);

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
                    if (isSelfGraded) _buildSelfGradedContext() else _buildContextSection(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentWord.wordStem,
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _speakWord(currentWord.wordStem),
                          child: const Icon(Icons.volume_up, color: Colors.tealAccent),
                        ),
                      ],
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
                  Expanded(
                    child: isSelfGraded
                        ? _buildSelfGradedPanel(currentWord)
                        : _buildOptions(currentWord),
                  ),
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
          final currentWord = sessionWords[currentIndex];
          contextRevealUsed[currentWord.id] = true;
        });
      },
      child: const Text("Reveal context"),
    );
  }

  Widget _buildSelfGradedContext() {
    return const Text(
      "Think of the definition, then tap Reveal.",
      textAlign: TextAlign.center,
      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
    );
  }

  Widget _buildSelfGradedPanel(Word currentWord) {
    if (!showSelfAnswer) {
      return Center(
        child: ElevatedButton(
          onPressed: () {
            setState(() {
              showSelfAnswer = true;
            });
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text("Reveal"),
        ),
      );
    }

    final definition = currentWord.definition ?? "MISSING DEFINITION";
    final revealExamples = <String>[];
    final original = originalContextText.trim();
    if (original.isNotEmpty) {
      revealExamples.add(original);
    }
    final originalKey = original.toLowerCase();
    for (final example in llmExamples) {
      if (originalKey.isNotEmpty && example.toLowerCase() == originalKey) {
        continue;
      }
      revealExamples.add(example);
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Definition",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(definition),
                const SizedBox(height: 16),
                const Text(
                  "Examples",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (revealExamples.isEmpty)
                  const Text("No examples available.", style: TextStyle(color: Colors.grey))
                else
                  ...revealExamples.map(
                    (example) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        "• $example",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleSelfGrade('failed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Failed"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleSelfGrade('hard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
                child: const Text("Hard"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleSelfGrade('easy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Easy"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isSelfGraded(String status) {
    return status == 'Proficient' || status == 'Adept' || status == 'Mastered';
  }

  Future<void> _handleSelfGrade(String grade) async {
    if (hasAnswered) return;
    if (!showSelfAnswer) return;

    final currentWord = sessionWords[currentIndex];
    setState(() {
      hasAnswered = true;
    });

    final isCorrect = grade != 'failed';
    final statusChange = await DatabaseHelper.instance.recordSelfGrade(
      currentWord.id,
      grade,
      sessionId: sessionId,
    );
    sessionResults[currentWord.id] = isCorrect;
    _maybeShowPromotion(currentWord.wordStem, statusChange);
    _nextWord();
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
