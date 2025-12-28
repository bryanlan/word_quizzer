import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'llm_modes.dart';
import 'models.dart';
import 'word_enrichment_service.dart';

class WordEditorScreen extends StatefulWidget {
  final int wordId;

  const WordEditorScreen({super.key, required this.wordId});

  @override
  State<WordEditorScreen> createState() => _WordEditorScreenState();
}

class _WordEditorScreenState extends State<WordEditorScreen> {
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

  Word? _word;
  bool _isLoading = true;
  bool _isSaving = false;
  int? _tier;
  String _status = 'New';
  List<TextEditingController> _exampleControllers = [];
  TextEditingController _definitionController = TextEditingController();
  List<String> _distractors = [];

  @override
  void initState() {
    super.initState();
    _loadWord();
  }

  @override
  void dispose() {
    for (final controller in _exampleControllers) {
      controller.dispose();
    }
    _definitionController.dispose();
    super.dispose();
  }

  Future<void> _loadWord() async {
    final word = await DatabaseHelper.instance.getWordById(widget.wordId);
    if (!mounted) return;
    if (word == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    final examples = await DatabaseHelper.instance.getExamplesForWord(word.id);
    final distractors = await DatabaseHelper.instance.getDistractorsForWord(word.id);
    for (final controller in _exampleControllers) {
      controller.dispose();
    }
    _definitionController.dispose();
    final controllers = examples
        .map((example) => TextEditingController(text: example))
        .toList();
    setState(() {
      _word = word;
      _status = word.status;
      _tier = word.priorityTier <= 0 ? null : word.priorityTier;
      _definitionController = TextEditingController(text: word.definition ?? '');
      _exampleControllers = controllers;
      _distractors = distractors;
      _isLoading = false;
    });
  }

  Future<void> _updateStatus(String status) async {
    if (_word == null) return;
    setState(() {
      _isSaving = true;
    });
    await DatabaseHelper.instance.updateWordStatus(_word!.id, status);
    await _loadWord();
    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Status updated to $status')),
    );
  }

  Future<void> _updateTier(int? tier) async {
    if (_word == null) return;
    setState(() {
      _isSaving = true;
    });
    await DatabaseHelper.instance.updateWordTier(_word!.id, tier);
    await _loadWord();
    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tier updated to ${tier ?? 'Auto'}')),
    );
  }

  Future<void> _saveDefinition() async {
    if (_word == null) return;
    setState(() {
      _isSaving = true;
    });
    await DatabaseHelper.instance.updateWordDefinition(
      _word!.id,
      _definitionController.text,
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Definition saved.')),
    );
  }

  Future<void> _saveExamples() async {
    if (_word == null) return;
    final examples = _exampleControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    setState(() {
      _isSaving = true;
    });
    await DatabaseHelper.instance.replaceExamplesForWord(_word!.id, examples);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Examples saved.')),
    );
  }

  Future<void> _runLlm(WordLlmMode mode) async {
    if (_word == null) return;
    final wordStem = _word!.wordStem;
    setState(() {
      _isSaving = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Running LLM...')),
          ],
        ),
      ),
    );
    try {
      if (mode == WordLlmMode.tier) {
        final tier = await WordEnrichmentService.requestTier(wordStem);
        await DatabaseHelper.instance.updateWordTier(_word!.id, tier);
      } else {
        final result = await WordEnrichmentService.enrichWord(wordStem);
        if (mode == WordLlmMode.full || mode == WordLlmMode.definition) {
          await DatabaseHelper.instance.updateWordDefinition(
            _word!.id,
            result.definition,
          );
        }
        if (mode == WordLlmMode.full || mode == WordLlmMode.examples) {
          await DatabaseHelper.instance.replaceExamplesForWord(
            _word!.id,
            result.examples,
          );
        }
        if (mode == WordLlmMode.full || mode == WordLlmMode.distractors) {
          await DatabaseHelper.instance.replaceDistractorsForWord(
            _word!.id,
            result.distractors,
          );
        }
      }
      await _loadWord();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${mode.label} refreshed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LLM failed: $e')),
      );
    } finally {
      if (mounted) {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _addExample() {
    setState(() {
      _exampleControllers.add(TextEditingController());
    });
  }

  void _removeExample(int index) {
    final controller = _exampleControllers[index];
    controller.dispose();
    setState(() {
      _exampleControllers.removeAt(index);
    });
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_word == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Word Editor')),
        body: const Center(child: Text('Word not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_word!.wordStem)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statusOptions.map((status) {
                final selected = _status == status;
                return ChoiceChip(
                  label: Text(status),
                  selected: selected,
                  onSelected: _isSaving ? null : (_) => _updateStatus(status),
                );
              }).toList(),
            ),
            _buildSectionTitle('Priority Tier'),
            const Text(
              'Tier 1 = highest priority to be pulled into Learning. Tier 5 = lowest. Auto lets the LLM decide.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Auto'),
                  selected: _tier == null,
                  onSelected: _isSaving ? null : (_) => _updateTier(null),
                ),
                ...List.generate(5, (index) {
                  final value = index + 1;
                  return ChoiceChip(
                    label: Text(value.toString()),
                    selected: _tier == value,
                    onSelected: _isSaving ? null : (_) => _updateTier(value),
                  );
                }),
              ],
            ),
            _buildSectionTitle('Definition'),
            TextField(
              controller: _definitionController,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter definition...',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveDefinition,
              child: const Text('Save Definition'),
            ),
            _buildSectionTitle('Examples'),
            if (_exampleControllers.isEmpty)
              const Text('No examples yet.', style: TextStyle(color: Colors.grey)),
            ..._exampleControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Example sentence ${index + 1}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _isSaving ? null : () => _removeExample(index),
                    ),
                  ],
                ),
              );
            }),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _isSaving ? null : _addExample,
                  child: const Text('Add Example'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveExamples,
                  child: const Text('Save Examples'),
                ),
              ],
            ),
            _buildSectionTitle('Distractors'),
            if (_distractors.isEmpty)
              const Text('No distractors yet.', style: TextStyle(color: Colors.grey))
            else
              ..._distractors.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $d'),
                  )),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isSaving ? null : () => _runLlm(WordLlmMode.distractors),
              child: const Text('Regenerate Distractors'),
            ),
            _buildSectionTitle('LLM Actions'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isSaving ? null : () => _runLlm(WordLlmMode.full),
                  child: const Text('Full Refresh'),
                ),
                OutlinedButton(
                  onPressed: _isSaving ? null : () => _runLlm(WordLlmMode.definition),
                  child: const Text('Definition'),
                ),
                OutlinedButton(
                  onPressed: _isSaving ? null : () => _runLlm(WordLlmMode.examples),
                  child: const Text('Examples'),
                ),
                OutlinedButton(
                  onPressed: _isSaving ? null : () => _runLlm(WordLlmMode.tier),
                  child: const Text('Tier'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
