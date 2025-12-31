import 'package:flutter/material.dart';
import '../models.dart';
import 'word_pack_service.dart';
import 'word_pack_import_screen.dart';

class WordPackBrowseScreen extends StatefulWidget {
  final int? initialLevel;
  final bool isOnboarding;

  const WordPackBrowseScreen({
    super.key,
    this.initialLevel,
    this.isOnboarding = false,
  });

  @override
  State<WordPackBrowseScreen> createState() => _WordPackBrowseScreenState();
}

class _WordPackBrowseScreenState extends State<WordPackBrowseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DifficultyLevel> _levels = [];
  Map<int, List<PackWithStatus>> _packsByLevel = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final service = WordPackService.instance;
    final levels = await service.getDifficultyLevels();
    final allPacks = await service.getAllPacksWithStatus();

    final packsByLevel = <int, List<PackWithStatus>>{};
    for (var level = 1; level <= 5; level++) {
      packsByLevel[level] =
          allPacks.where((p) => p.pack.difficultyLevel == level).toList();
    }

    if (!mounted) return;
    setState(() {
      _levels = levels;
      _packsByLevel = packsByLevel;
      _isLoading = false;
    });

    // Set initial tab if specified
    if (widget.initialLevel != null &&
        widget.initialLevel! >= 1 &&
        widget.initialLevel! <= 5) {
      _tabController.animateTo(widget.initialLevel! - 1);
    }
  }

  DifficultyLevel _getLevelData(int level) {
    return _levels.firstWhere(
      (l) => l.level == level,
      orElse: () => DifficultyLevel.levels[level - 1],
    );
  }

  void _openPack(PackWithStatus packWithStatus) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => WordPackImportScreen(
          packId: packWithStatus.pack.id,
        ),
      ),
    );

    if (result == true) {
      _loadData(); // Refresh to show updated import status
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOnboarding ? 'Choose Your Level' : 'Word Packs'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            for (var level = 1; level <= 5; level++)
              Tab(text: 'Level $level'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                for (var level = 1; level <= 5; level++)
                  _buildLevelTab(level),
              ],
            ),
    );
  }

  Widget _buildLevelTab(int level) {
    final levelData = _getLevelData(level);
    final packs = _packsByLevel[level] ?? [];

    return RefreshIndicator(
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildLevelHeader(levelData),
          ),
          if (packs.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No packs available for this level yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildPackCard(packs[index]),
                  childCount: packs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLevelHeader(DifficultyLevel level) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withAlpha(51),
            Theme.of(context).colorScheme.primary.withAlpha(13),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Level ${level.level}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  level.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            level.description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          if (level.sampleWords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sample words:',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: level.sampleWords
                  .map((word) => Chip(
                        label: Text(word),
                        labelStyle: const TextStyle(fontSize: 12),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPackCard(PackWithStatus packWithStatus) {
    final pack = packWithStatus.pack;
    final isImported = packWithStatus.isImported;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPack(packWithStatus),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isImported) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(51),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Imported',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pack.description,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${pack.wordCount} words',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isImported ? Icons.check_circle : Icons.chevron_right,
                color: isImported ? Colors.green : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
