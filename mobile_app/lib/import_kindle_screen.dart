import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'auth_service.dart';
import 'kindle_import_service.dart';
import 'sync_service.dart';

enum _ImportStep {
  upload,
  summary,
  triage,
  confirm,
  progress,
  complete,
}

class _StatusOption {
  final String label;
  final String value;

  const _StatusOption(this.label, this.value);
}

class _TriageSelection {
  final String status;
  final int? tier;
  final bool locked;

  const _TriageSelection({
    required this.status,
    required this.tier,
    required this.locked,
  });

  _TriageSelection copyWith({
    String? status,
    int? tier,
    bool? locked,
  }) {
    return _TriageSelection(
      status: status ?? this.status,
      tier: tier ?? this.tier,
      locked: locked ?? this.locked,
    );
  }
}

class ImportKindleScreen extends StatefulWidget {
  const ImportKindleScreen({super.key});

  @override
  State<ImportKindleScreen> createState() => _ImportKindleScreenState();
}

class _ImportKindleScreenState extends State<ImportKindleScreen> {
  static const _pageSize = 5;
  static const _statusOptions = <_StatusOption>[
    _StatusOption('Ignore', 'Ignored'),
    _StatusOption('Learn Now', 'Learning'),
    _StatusOption('On Deck', 'On Deck'),
    _StatusOption('Proficient', 'Proficient'),
    _StatusOption('Adept', 'Adept'),
    _StatusOption('Mastered', 'Mastered'),
  ];

  _ImportStep _step = _ImportStep.upload;
  KindleImportSummary? _summary;
  bool _useLlmFilter = false;
  bool _isUploading = false;
  bool _isSubmitting = false;
  int _ignoredByLlm = 0;
  ImportJob? _currentJob;
  List<ImportWord> _triageWords = [];
  final Map<int, _TriageSelection> _selections = {};
  int _pageIndex = 0;
  bool _wakeLockEnabled = false;
  String? _importId;
  String? _lastError;

  @override
  void dispose() {
    _disableWakeLock();
    super.dispose();
  }

  Future<void> _enableWakeLock() async {
    if (_wakeLockEnabled) {
      return;
    }
    _wakeLockEnabled = true;
    try {
      await WakelockPlus.enable();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep the screen awake while watching progress.'),
        ),
      );
    }
  }

  Future<void> _disableWakeLock() async {
    if (!_wakeLockEnabled) {
      return;
    }
    _wakeLockEnabled = false;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<KindleImportService?> _buildService() async {
    final token = await AuthService.getToken();
    if (token == null || token.trim().isEmpty || AuthService.isTokenExpired(token)) {
      if (!mounted) return null;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in required'),
          content: const Text('Sign in with Google to import and enrich words.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                AuthService.startGoogleLogin();
              },
              child: const Text('Sign In'),
            ),
          ],
        ),
      );
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('sync_server_url') ??
        'https://word-quizzer-api.bryanlangley.org';
    if (url.trim().isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync server URL missing.')),
      );
      return null;
    }

    return KindleImportService(baseUrl: url, token: token);
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _isUploading = true;
      _lastError = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) {
        setState(() {
          _isUploading = false;
        });
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Unable to read file bytes.');
      }

      final service = await _buildService();
      if (service == null) {
        setState(() {
          _isUploading = false;
        });
        return;
      }

      final summary = await service.uploadKindleFile(
        bytes: bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _importId = summary.importId;
        _ignoredByLlm = summary.ignoredByLlm;
        _step = _ImportStep.summary;
        _isUploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e.toString();
        _isUploading = false;
      });
    }
  }

  Future<void> _startFilter() async {
    final service = await _buildService();
    final importId = _importId;
    if (service == null || importId == null || importId.isEmpty) {
      return;
    }

    setState(() {
      _lastError = null;
      _currentJob = null;
    });

    await _enableWakeLock();
    try {
      final job = await service.startFilter(importId);
      await _pollJob(service, job);
      final ignored = _currentJob?.result['ignored_count'] as int? ?? 0;
      final words = await service.getTriageWords(importId);
      if (!mounted) return;
      setState(() {
        _ignoredByLlm = ignored;
        _triageWords = words;
        _pageIndex = 0;
        _step = _triageWords.isEmpty ? _ImportStep.complete : _ImportStep.triage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e.toString();
      });
    } finally {
      await _disableWakeLock();
    }
  }

  Future<void> _skipFilter() async {
    final service = await _buildService();
    final importId = _importId;
    if (service == null || importId == null || importId.isEmpty) {
      return;
    }

    setState(() {
      _lastError = null;
    });

    try {
      final words = await service.getTriageWords(importId);
      if (!mounted) return;
      setState(() {
        _triageWords = words;
        _pageIndex = 0;
        _step = _triageWords.isEmpty ? _ImportStep.complete : _ImportStep.triage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e.toString();
      });
    }
  }

  Future<void> _pollJob(KindleImportService service, ImportJob job) async {
    setState(() {
      _currentJob = job;
      _step = _ImportStep.progress;
    });

    while (mounted) {
      final updated = await service.getJob(job.jobId);
      if (!mounted) return;
      setState(() {
        _currentJob = updated;
      });
      if (updated.status == 'completed') {
        break;
      }
      if (updated.status == 'failed') {
        throw Exception(updated.message.isNotEmpty ? updated.message : 'Job failed.');
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  List<ImportWord> _currentPageWords() {
    final start = _pageIndex * _pageSize;
    if (start >= _triageWords.length) {
      return [];
    }
    final end = (start + _pageSize).clamp(0, _triageWords.length);
    return _triageWords.sublist(start, end);
  }

  bool _pageComplete() {
    for (final word in _currentPageWords()) {
      final selection = _selections[word.id];
      if (selection == null || selection.status.isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _setStatus(ImportWord word, String status) {
    final current = _selections[word.id];
    setState(() {
      _selections[word.id] = _TriageSelection(
        status: status,
        tier: status == 'Ignored' ? null : current?.tier,
        locked: true,
      );
    });
  }

  void _setTier(ImportWord word, int? tier) {
    final current = _selections[word.id];
    if (current == null) {
      return;
    }
    setState(() {
      _selections[word.id] = current.copyWith(tier: tier);
    });
  }

  void _unlockWord(int wordId) {
    final current = _selections[wordId];
    if (current == null) {
      return;
    }
    setState(() {
      _selections[wordId] = current.copyWith(locked: false);
    });
  }

  Future<void> _submitAndEnrich() async {
    final service = await _buildService();
    final importId = _importId;
    if (service == null || importId == null || importId.isEmpty) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _lastError = null;
    });

    try {
      final decisions = _selections.entries.map((entry) {
        final selection = entry.value;
        return {
          'word_id': entry.key,
          'status': selection.status,
          'priority_tier': selection.status == 'Ignored' ? null : selection.tier,
        };
      }).toList();

      await service.submitTriage(importId, decisions);
      await _enableWakeLock();
      final job = await service.startEnrichment(importId);
      await _pollJob(service, job);
      if (!mounted) return;
      setState(() {
        _step = _ImportStep.complete;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e.toString();
      });
    } finally {
      await _disableWakeLock();
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _syncNow() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty || AuthService.isTokenExpired(token)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to sync.')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('sync_server_url') ??
        'https://word-quizzer-api.bryanlangley.org';
    if (url.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync server URL missing.')),
      );
      return;
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syncing...')),
        );
      }
      final service = SyncService(baseUrl: url, token: token);
      await service.sync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync complete.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  Widget _buildProgressCard(String title, ImportJob? job) {
    final total = job?.total ?? 0;
    final processed = job?.processed ?? 0;
    final message = job?.message ?? '';
    final progress = total > 0 ? processed / total : null;
    return Card(
      color: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (message.isNotEmpty) Text(message),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            if (total > 0)
              Text('$processed / $total', style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload your Kindle vocab database to start importing.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isUploading ? null : _pickAndUpload,
          icon: const Icon(Icons.upload_file),
          label: const Text('Select Kindle File'),
        ),
        if (_isUploading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Uploading and parsing...'),
        ],
        if (_lastError != null) ...[
          const SizedBox(height: 12),
          Text(
            _lastError!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryStep() {
    final summary = _summary;
    if (summary == null) {
      return const Text('No import summary available.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Import Summary',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildSummaryRow('Total Extracted', summary.totalExtracted.toString()),
        _buildSummaryRow('Net New Words', summary.newWords.toString()),
        _buildSummaryRow('Repeats Skipped', summary.repeatWords.toString()),
        if (_ignoredByLlm > 0)
          _buildSummaryRow('Ignored by LLM', _ignoredByLlm.toString()),
        const SizedBox(height: 16),
        SwitchListTile(
          value: _useLlmFilter,
          onChanged: (value) {
            setState(() {
              _useLlmFilter = value;
            });
          },
          title: const Text('Auto-ignore junk words with LLM'),
          subtitle: const Text('Only applies to net new words.'),
        ),
        if (_lastError != null) ...[
          const SizedBox(height: 12),
          Text(_lastError!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _useLlmFilter ? _startFilter : _skipFilter,
                child: Text(_useLlmFilter ? 'Run Filter' : 'Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTriageStep() {
    final current = _currentPageWords();
    final totalPages = (_triageWords.length / _pageSize).ceil();
    final canProceed = _pageComplete();
    final isLastPage = _pageIndex >= totalPages - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Triage new words',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Tier 1 = highest priority to be pulled into Learning. Tier 5 = lowest. '
          'Auto lets the LLM decide.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ...current.map(_buildTriageCard),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Page ${_pageIndex + 1} of $totalPages'),
            Text('${(_pageIndex * _pageSize) + current.length} / ${_triageWords.length}'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pageIndex == 0
                    ? null
                    : () {
                        setState(() {
                          _pageIndex -= 1;
                        });
                      },
                child: const Text('Prev'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: canProceed
                    ? () {
                        if (isLastPage) {
                          setState(() {
                            _step = _ImportStep.confirm;
                          });
                        } else {
                          setState(() {
                            _pageIndex += 1;
                          });
                        }
                      }
                    : null,
                child: Text(isLastPage ? 'Review & Enrich' : 'Next'),
              ),
            ),
          ],
        ),
        if (!canProceed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Select a knowledge level for all 5 words to continue.',
                style: TextStyle(color: Colors.orangeAccent)),
          ),
      ],
    );
  }

  Widget _buildTriageCard(ImportWord word) {
    final selection = _selections[word.id];
    final locked = selection?.locked ?? false;
    final isIgnored = selection?.status == 'Ignored';
    final statusValue = selection?.status ?? '';

    return Card(
      color: isIgnored ? Colors.white10.withValues(alpha: 0.4) : Colors.white10,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    word.word,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (locked)
                  TextButton(
                    onPressed: () => _unlockWord(word.id),
                    child: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            AbsorbPointer(
              absorbing: locked,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _statusOptions.map((option) {
                  final selected = statusValue == option.value;
                  return ChoiceChip(
                    label: Text(option.label),
                    selected: selected,
                    selectedColor: option.value == 'Ignored'
                        ? Colors.grey
                        : Colors.tealAccent.withValues(alpha: 0.2),
                    onSelected: (_) => _setStatus(word, option.value),
                  );
                }).toList(),
              ),
            ),
            if (statusValue.isNotEmpty && statusValue != 'Ignored') ...[
              const SizedBox(height: 12),
              const Text('Priority Tier', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 6),
              AbsorbPointer(
                absorbing: locked,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Auto'),
                      selected: selection?.tier == null,
                      onSelected: (_) => _setTier(word, null),
                    ),
                    ...List.generate(5, (index) {
                      final tier = index + 1;
                      return ChoiceChip(
                        label: Text(tier.toString()),
                        selected: selection?.tier == tier,
                        onSelected: (_) => _setTier(word, tier),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmStep() {
    final ignoredByUser = _selections.values.where((s) => s.status == 'Ignored').length;
    final toEnrich = _triageWords.length - ignoredByUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ready to enrich?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildSummaryRow('Words to enrich', toEnrich.toString()),
        _buildSummaryRow('Ignored by LLM', _ignoredByLlm.toString()),
        _buildSummaryRow('Ignored by you', ignoredByUser.toString()),
        const SizedBox(height: 12),
        const Text(
          'We will generate definitions, examples, distractors, and tiering (for Auto).',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        if (_lastError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_lastError!, style: const TextStyle(color: Colors.redAccent)),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        setState(() {
                          _step = _ImportStep.triage;
                        });
                      },
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitAndEnrich,
                child: _isSubmitting
                    ? const Text('Submitting...')
                    : const Text('Submit to LLM'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressStep() {
    final title = _currentJob?.message.isNotEmpty == true
        ? _currentJob!.message
        : 'Processing...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Processing',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildProgressCard(title, _currentJob),
        if (_lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_lastError!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (_currentJob?.status == 'completed')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _step = _ImportStep.complete;
                });
              },
              child: const Text('Continue'),
            ),
          ),
      ],
    );
  }

  Widget _buildCompleteStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Import complete',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text('Sync to pull the new words onto this device.'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return Home'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _syncNow,
                child: const Text('Sync Now'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_step) {
      case _ImportStep.upload:
        body = _buildUploadStep();
        break;
      case _ImportStep.summary:
        body = _buildSummaryStep();
        break;
      case _ImportStep.triage:
        body = _buildTriageStep();
        break;
      case _ImportStep.confirm:
        body = _buildConfirmStep();
        break;
      case _ImportStep.progress:
        body = _buildProgressStep();
        break;
      case _ImportStep.complete:
        body = _buildCompleteStep();
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Kindle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: body,
      ),
    );
  }
}
