import 'dart:async';

import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'llm_modes.dart';
import 'models.dart';
import 'word_editor_screen.dart';
import 'word_enrichment_service.dart';

class WordManagementScreen extends StatefulWidget {
  const WordManagementScreen({super.key});

  @override
  State<WordManagementScreen> createState() => _WordManagementScreenState();
}

class _WordManagementScreenState extends State<WordManagementScreen> {
  static const int _pageSize = 50;
  static const List<String> _statusFilters = [
    'All',
    'New',
    'On Deck',
    'Learning',
    'Proficient',
    'Adept',
    'Mastered',
    'Ignored',
    'Pau(S)ed',
  ];

  static const List<String> _letters = [
    'All',
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<WordSummary> _words = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _loadGeneration = 0;

  String _statusFilter = 'All';
  int? _tierFilter;
  String _letterFilter = 'All';
  String _searchQuery = '';

  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadWords(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadWords();
    }
  }

  Future<void> _loadWords({bool reset = false}) async {
    if ((_isLoadingMore && !reset) || (_isLoading && !reset)) {
      return;
    }
    final generation = ++_loadGeneration;
    if (reset) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _offset = 0;
        _words = [];
        _selectionMode = false;
        _selectedIds.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final results = await DatabaseHelper.instance.getWordSummaries(
        status: _statusFilter,
        tier: _tierFilter,
        startsWith: _letterFilter,
        search: _searchQuery,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _words.addAll(results);
        _offset += results.length;
        _hasMore = results.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load words: $e')),
      );
    }
  }

  Future<void> _applyFilters() async {
    await _loadWords(reset: true);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = value;
      });
      _applyFilters();
    });
  }

  void _toggleSelection(int wordId) {
    setState(() {
      if (_selectedIds.contains(wordId)) {
        _selectedIds.remove(wordId);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedIds.add(wordId);
        _selectionMode = true;
      }
    });
  }

  Future<void> _selectAllFiltered() async {
    final ids = await DatabaseHelper.instance.getWordIdsForFilter(
      status: _statusFilter,
      tier: _tierFilter,
      startsWith: _letterFilter,
      search: _searchQuery,
    );
    if (!mounted) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
      _selectionMode = _selectedIds.isNotEmpty;
    });
  }

  Future<void> _applyStatusToSelection(String status) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    await DatabaseHelper.instance.updateWordStatusBatch(ids, status);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated ${ids.length} words to $status.')),
    );
    _applyFilters();
  }

  Future<void> _applyTierToSelection(int? tier) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    await DatabaseHelper.instance.updateWordTierBatch(ids, tier);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Updated ${ids.length} words to ${tier ?? 'Auto'} tier.')),
    );
    _applyFilters();
  }

  Future<void> _runLlmForSelection(WordLlmMode mode) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final stems = await DatabaseHelper.instance.getWordStemsByIds(ids);
    if (!mounted) return;
    final entries = stems.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (entries.isEmpty) return;

    final dialogReady = Completer<StateSetter>();
    int processed = 0;
    int failures = 0;
    String currentWord = '';

    bool didShowDialog = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          if (!dialogReady.isCompleted) {
            dialogReady.complete(setState);
          }
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              title: Text(mode.label),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (currentWord.isNotEmpty) Text('Now: $currentWord'),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: entries.isEmpty ? 0 : processed / entries.length,
                  ),
                  const SizedBox(height: 8),
                  Text('$processed / ${entries.length}'),
                  if (failures > 0)
                    Text('Failures: $failures',
                        style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          );
        },
      ),
    );
    didShowDialog = true;

    final dialogSetState = await dialogReady.future;

    for (final entry in entries) {
      currentWord = entry.value;
      dialogSetState(() {});
      try {
        if (mode == WordLlmMode.tier) {
          final tier = await WordEnrichmentService.requestTier(entry.value);
          await DatabaseHelper.instance.updateWordTier(entry.key, tier);
        } else {
          final result = await WordEnrichmentService.enrichWord(entry.value);
          await DatabaseHelper.instance
              .replaceDistractorsForWord(entry.key, result.distractors);
        }
      } catch (_) {
        failures += 1;
      }
      processed += 1;
      dialogSetState(() {});
    }

    if (mounted && didShowDialog) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;
    final summary = failures == 0
        ? 'LLM complete.'
        : 'LLM complete with $failures failures.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
    _applyFilters();
  }

  void _openWordEditor(WordSummary word) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WordEditorScreen(wordId: word.id),
      ),
    ).then((_) {
      if (mounted) {
        _applyFilters();
      }
    });
  }

  void _showStatusPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: _statusFilters
            .where((status) => status != 'All')
            .map((status) => ListTile(
                  title: Text(status),
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyStatusToSelection(status);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _showTierPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Auto'),
            onTap: () {
              Navigator.pop(ctx);
              _applyTierToSelection(null);
            },
          ),
          ...List.generate(5, (index) {
            final tier = index + 1;
            return ListTile(
              title: Text('Tier $tier'),
              onTap: () {
                Navigator.pop(ctx);
                _applyTierToSelection(tier);
              },
            );
          }),
        ],
      ),
    );
  }

  void _showLlmPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: WordLlmMode.values
            .map((mode) => ListTile(
                  title: Text(mode.label),
                  onTap: () {
                    Navigator.pop(ctx);
                    _runLlmForSelection(mode);
                  },
                ))
            .toList(),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search words...',
            border: OutlineInputBorder(),
          ),
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _statusFilters.map((status) {
            return ChoiceChip(
              label: Text(status),
              selected: _statusFilter == status,
              onSelected: (_) {
                setState(() {
                  _statusFilter = status;
                });
                _applyFilters();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All tiers'),
              selected: _tierFilter == null,
              onSelected: (_) {
                setState(() {
                  _tierFilter = null;
                });
                _applyFilters();
              },
            ),
            ChoiceChip(
              label: const Text('Auto'),
              selected: _tierFilter == 0,
              onSelected: (_) {
                setState(() {
                  _tierFilter = 0;
                });
                _applyFilters();
              },
            ),
            ...List.generate(5, (index) {
              final tier = index + 1;
              return ChoiceChip(
                label: Text('Tier $tier'),
                selected: _tierFilter == tier,
                onSelected: (_) {
                  setState(() {
                    _tierFilter = tier;
                  });
                  _applyFilters();
                },
              );
            }),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _letters.map((letter) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(letter),
                  selected: _letterFilter == letter,
                  onSelected: (_) {
                    setState(() {
                      _letterFilter = letter;
                    });
                    _applyFilters();
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    if (!_selectionMode) {
      return const SizedBox.shrink();
    }
    final count = _selectedIds.length;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$count selected',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          TextButton(
            onPressed: _selectAllFiltered,
            child: const Text('Select all filtered'),
          ),
          OutlinedButton(
            onPressed: _showStatusPicker,
            child: const Text('Set Status'),
          ),
          OutlinedButton(
            onPressed: _showTierPicker,
            child: const Text('Set Tier'),
          ),
          OutlinedButton(
            onPressed: _showLlmPicker,
            child: const Text('Run LLM'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectionMode = false;
                _selectedIds.clear();
              });
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildWordRow(WordSummary word) {
    final selected = _selectedIds.contains(word.id);
    final tierLabel =
        word.priorityTier == null ? 'Auto' : 'Tier ${word.priorityTier}';

    return ListTile(
      onLongPress: () => _toggleSelection(word.id),
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(word.id);
        } else {
          _openWordEditor(word);
        }
      },
      leading: _selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelection(word.id),
            )
          : null,
      title: Text(word.wordStem),
      subtitle: Text('${word.status} • $tierLabel'),
      trailing: _selectionMode ? null : const Icon(Icons.chevron_right),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Word Management')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _applyFilters,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFilters(),
                  const SizedBox(height: 16),
                  _buildSelectionBar(),
                  if (_words.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text('No words match these filters.',
                          style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._words.map(_buildWordRow),
                  if (_isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
    );
  }
}
