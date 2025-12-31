import 'package:flutter/material.dart';
import '../models.dart';
import 'word_pack_service.dart';

enum _ImportStep {
  preview,
  triage,
  confirm,
  complete,
}

class _StatusOption {
  final String label;
  final String value;
  final String description;

  const _StatusOption(this.label, this.value, this.description);
}

class _WordSelection {
  final String status;

  const _WordSelection({required this.status});
}

class WordPackImportScreen extends StatefulWidget {
  final String packId;

  const WordPackImportScreen({
    super.key,
    required this.packId,
  });

  @override
  State<WordPackImportScreen> createState() => _WordPackImportScreenState();
}

class _WordPackImportScreenState extends State<WordPackImportScreen> {
  static const _pageSize = 5;
  static const _statusOptions = <_StatusOption>[
    _StatusOption('Learning', 'Learning', 'Currently learning this word'),
    _StatusOption('Proficient', 'Proficient', 'Know it fairly well'),
    _StatusOption('Adept', 'Adept', 'Know it very well'),
    _StatusOption('Mastered', 'Mastered', 'Completely mastered'),
  ];

  _ImportStep _step = _ImportStep.preview;
  WordPackData? _packData;
  bool _isLoading = true;
  bool _isImporting = false;
  bool _alreadyImported = false;
  final Map<int, _WordSelection> _selections = {};
  int _pageIndex = 0;
  PackImportResult? _importResult;

  @override
  void initState() {
    super.initState();
    _loadPack();
  }

  Future<void> _loadPack() async {
    setState(() => _isLoading = true);

    final service = WordPackService.instance;
    final packData = await service.loadPackData(widget.packId);
    final isImported = await service.isPackImported(widget.packId);

    if (!mounted) return;
    setState(() {
      _packData = packData;
      _alreadyImported = isImported;
      _isLoading = false;

      // Initialize all selections to Learning by default
      if (packData != null) {
        for (var i = 0; i < packData.words.length; i++) {
          _selections[i] = const _WordSelection(status: 'Learning');
        }
      }
    });
  }

  int get _totalPages =>
      ((_packData?.words.length ?? 0) / _pageSize).ceil();

  List<PackWord> get _currentPageWords {
    if (_packData == null) return [];
    final start = _pageIndex * _pageSize;
    final end = (start + _pageSize).clamp(0, _packData!.words.length);
    return _packData!.words.sublist(start, end);
  }

  bool get _isCurrentPageComplete {
    final start = _pageIndex * _pageSize;
    final end = (start + _pageSize).clamp(0, _packData?.words.length ?? 0);
    for (var i = start; i < end; i++) {
      if (!_selections.containsKey(i)) return false;
    }
    return true;
  }

  void _startTriage() {
    setState(() {
      _step = _ImportStep.triage;
      _pageIndex = 0;
    });
  }

  void _goToConfirm() {
    setState(() => _step = _ImportStep.confirm);
  }

  void _goBack() {
    switch (_step) {
      case _ImportStep.preview:
        Navigator.of(context).pop();
        break;
      case _ImportStep.triage:
        if (_pageIndex > 0) {
          setState(() => _pageIndex--);
        } else {
          setState(() => _step = _ImportStep.preview);
        }
        break;
      case _ImportStep.confirm:
        setState(() => _step = _ImportStep.triage);
        break;
      case _ImportStep.complete:
        Navigator.of(context).pop(true);
        break;
    }
  }

  void _nextPage() {
    if (_pageIndex < _totalPages - 1) {
      setState(() => _pageIndex++);
    } else {
      _goToConfirm();
    }
  }

  Future<void> _doImport() async {
    if (_packData == null) return;

    setState(() => _isImporting = true);

    final wordsToImport = <PackWordImport>[];
    for (var i = 0; i < _packData!.words.length; i++) {
      final word = _packData!.words[i];
      final selection = _selections[i] ?? const _WordSelection(status: 'Learning');
      wordsToImport.add(PackWordImport(
        wordStem: word.wordStem,
        definition: word.definition,
        status: selection.status,
        difficultyScore: word.difficultyScore,
        examples: word.examples,
        distractors: word.distractors,
      ));
    }

    final result = await WordPackService.instance.importPack(
      widget.packId,
      wordsToImport,
    );

    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _importResult = result;
      _step = _ImportStep.complete;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _ImportStep.preview || _step == _ImportStep.complete,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getTitle()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _packData == null
                ? const Center(child: Text('Pack not found'))
                : _buildBody(),
      ),
    );
  }

  String _getTitle() {
    switch (_step) {
      case _ImportStep.preview:
        return _packData?.metadata.name ?? 'Word Pack';
      case _ImportStep.triage:
        return 'Review Words (${_pageIndex + 1}/$_totalPages)';
      case _ImportStep.confirm:
        return 'Confirm Import';
      case _ImportStep.complete:
        return 'Import Complete';
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case _ImportStep.preview:
        return _buildPreview();
      case _ImportStep.triage:
        return _buildTriage();
      case _ImportStep.confirm:
        return _buildConfirm();
      case _ImportStep.complete:
        return _buildComplete();
    }
  }

  Widget _buildPreview() {
    final pack = _packData!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pack info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.metadata.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pack.metadata.description,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.format_list_numbered,
                        '${pack.words.length} words',
                      ),
                      const SizedBox(width: 12),
                      _buildInfoChip(
                        Icons.signal_cellular_alt,
                        'Level ${pack.metadata.difficultyLevel}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_alreadyImported) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withAlpha(77)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You have already imported this pack. Re-importing will skip words you already have.',
                      style: TextStyle(color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Preview words
          const Text(
            'Preview Words',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Here are the first 5 words in this pack:',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          ...pack.words.take(5).map((word) => _buildPreviewWordCard(word)),
          if (pack.words.length > 5) ...[
            const SizedBox(height: 8),
            Text(
              '... and ${pack.words.length - 5} more words',
              style: TextStyle(
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 32),
          // Start button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startTriage,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                _alreadyImported ? 'Re-import Pack' : 'Start Import',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewWordCard(PackWord word) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              word.wordStem,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              word.definition,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriage() {
    final words = _currentPageWords;
    final startIndex = _pageIndex * _pageSize;

    return Column(
      children: [
        // Progress bar
        LinearProgressIndicator(
          value: (_pageIndex + 1) / _totalPages,
          backgroundColor: Colors.grey[200],
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: words.length,
            itemBuilder: (context, index) {
              final globalIndex = startIndex + index;
              return _buildTriageWordCard(words[index], globalIndex);
            },
          ),
        ),
        // Navigation
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(26),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (_pageIndex > 0)
                TextButton.icon(
                  onPressed: () => setState(() => _pageIndex--),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                ),
              const Spacer(),
              Text(
                'Page ${_pageIndex + 1} of $_totalPages',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isCurrentPageComplete ? _nextPage : null,
                icon: Icon(
                  _pageIndex == _totalPages - 1
                      ? Icons.check
                      : Icons.arrow_forward,
                ),
                label: Text(
                  _pageIndex == _totalPages - 1 ? 'Review' : 'Next',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTriageWordCard(PackWord word, int index) {
    final selection = _selections[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Word header
            Text(
              word.wordStem,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            // Definition
            Text(
              word.definition,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
            // Example
            if (word.examples.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"${word.examples.first}"',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Status selection
            const Text(
              'How well do you know this word?',
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _statusOptions.map((option) {
                final isSelected = selection?.status == option.value;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selections[index] = _WordSelection(status: option.value);
                      });
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirm() {
    // Count selections by status
    final statusCounts = <String, int>{};
    for (final selection in _selections.values) {
      statusCounts[selection.status] =
          (statusCounts[selection.status] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          const Text(
            'Ready to Import',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re about to import ${_packData!.words.length} words.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Summary by Status',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...statusCounts.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _getStatusColor(entry.key),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      '${entry.value} words',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isImporting ? null : _doImport,
              icon: _isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_isImporting ? 'Importing...' : 'Import Words'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _isImporting ? null : _goBack,
              child: const Text('Go Back and Edit'),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Learning':
        return Colors.blue;
      case 'Proficient':
        return Colors.orange;
      case 'Adept':
        return Colors.purple;
      case 'Mastered':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildComplete() {
    final result = _importResult!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.celebration,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            const Text(
              'Import Complete!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${result.added} words added to your library',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.green,
              ),
            ),
            if (result.skipped > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${result.skipped} words skipped (already in library)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
