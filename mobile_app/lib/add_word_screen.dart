import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'openrouter_service.dart';
import 'word_enrichment_service.dart';

class AddWordScreen extends StatefulWidget {
  const AddWordScreen({super.key});

  @override
  State<AddWordScreen> createState() => _AddWordScreenState();
}

class _AddWordScreenState extends State<AddWordScreen> {
  final TextEditingController wordController = TextEditingController();
  String status = 'Learning';
  int tier = 3;
  bool isSaving = false;
  static const int _maxWords = 10;

  @override
  void dispose() {
    wordController.dispose();
    super.dispose();
  }

  Future<void> _addWord() async {
    final words = _parseWords(wordController.text);
    if (words.isEmpty) {
      _showMessage("Please enter at least one word.");
      return;
    }
    if (words.length > _maxWords) {
      _showMessage("Please limit to $_maxWords words per batch.");
      return;
    }

    setState(() {
      isSaving = true;
    });

    final added = <String>[];
    final skipped = <String>[];
    final failed = <String>[];

    try {
      for (final word in words) {
        final exists = await DatabaseHelper.instance.wordExists(word);
        if (exists) {
          skipped.add(word);
          continue;
        }

        try {
          final enrichment = await WordEnrichmentService.enrichWord(word);
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
            skipped.add(word);
            continue;
          }
          added.add(word);
        } on MissingApiKeyException {
          if (!mounted) return;
          _showMessage(
            kIsWeb
                ? "Server OpenRouter key is missing. Configure it on the server."
                : "OpenRouter key missing. Add one in Settings.",
          );
          return;
        } on NotAuthenticatedException {
          if (!mounted) return;
          _showMessage("Sign in required to add words.");
          return;
        } on InvalidApiKeyException {
          if (!mounted) return;
          _showMessage("Invalid OpenRouter API key. Check Settings.");
          return;
        } catch (e) {
          failed.add(word);
          if (!mounted) return;
          _showMessage("Unable to add \"$word\": $e");
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Unable to add words: $e");
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }

    if (!mounted) return;
    if (added.isEmpty) {
      _showMessage(_buildSummaryMessage(added, skipped, failed));
      return;
    }
    Navigator.pop(
      context,
      {
        'added': added,
        'skipped': skipped,
        'failed': failed,
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _parseWords(String input) {
    final results = <String>[];
    final seen = <String>{};
    for (final raw in input.split(',')) {
      final cleaned = raw.trim();
      if (cleaned.isEmpty) {
        continue;
      }
      final key = cleaned.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      results.add(cleaned);
    }
    return results;
  }

  String _buildSummaryMessage(
    List<String> added,
    List<String> skipped,
    List<String> failed,
  ) {
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add('Added ${added.length}.');
    }
    if (skipped.isNotEmpty) {
      parts.add('Skipped ${skipped.length} existing.');
    }
    if (failed.isNotEmpty) {
      parts.add('Failed ${failed.length}.');
    }
    if (parts.isEmpty) {
      return 'No new words added.';
    }
    return parts.join(' ');
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
              "Words",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: wordController,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Enter up to 10 words, comma-separated",
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
