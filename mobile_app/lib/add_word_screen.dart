import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'openrouter_service.dart';

class AddWordScreen extends StatefulWidget {
  final String apiKey;

  const AddWordScreen({super.key, required this.apiKey});

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  final TextEditingController wordController = TextEditingController();
  String status = 'Learning';
  int tier = 3;
  bool isSaving = false;

  @override
  void dispose() {
    wordController.dispose();
    super.dispose();
  }

  Future<void> _addWord() async {
    final word = wordController.text.trim();
    if (word.isEmpty) {
      _showMessage("Please enter a word.");
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final exists = await DatabaseHelper.instance.wordExists(word);
      if (exists) {
        _showMessage("That word already exists.");
        return;
      }

      final service = OpenRouterService(widget.apiKey);
      final enrichment = await service.enrichWord(word);

      final id = await DatabaseHelper.instance.addWordWithEnrichment(
        wordStem: word,
        status: status,
        priorityTier: tier,
        definition: enrichment.definition,
        examples: enrichment.examples,
        distractors: enrichment.distractors,
      );

      if (!mounted) return;
      if (id == null) {
        _showMessage("That word already exists.");
        return;
      }

      Navigator.pop(context, word);
    } on InvalidApiKeyException {
      if (!mounted) return;
      _showMessage("Invalid OpenRouter API key. Check Settings.");
    } catch (e) {
      if (!mounted) return;
      _showMessage("Unable to add word: $e");
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Word")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Word",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: wordController,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Enter a word",
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Status",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: status,
              items: const [
                DropdownMenuItem(value: 'Learning', child: Text('Learning')),
                DropdownMenuItem(value: 'On Deck', child: Text('On Deck')),
                DropdownMenuItem(value: 'Proficient', child: Text('Proficient')),
                DropdownMenuItem(value: 'Adept', child: Text('Adept')),
              ],
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        status = value;
                      });
                    },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            const Text(
              "Tier (Priority)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              "Tier 1 is highest priority for Learning. Tier 5 is lowest.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: tier,
              items: List.generate(
                5,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text("Tier ${index + 1}"),
                ),
              ),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        tier = value;
                      });
                    },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : _addWord,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        "Generate & Add",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
