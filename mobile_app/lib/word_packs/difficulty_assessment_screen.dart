import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'word_pack_service.dart';
import 'word_pack_browse_screen.dart';

class DifficultyAssessmentScreen extends StatefulWidget {
  final bool isOnboarding;

  const DifficultyAssessmentScreen({
    super.key,
    this.isOnboarding = false,
  });

  @override
  State<DifficultyAssessmentScreen> createState() =>
      _DifficultyAssessmentScreenState();
}

class _DifficultyAssessmentScreenState
    extends State<DifficultyAssessmentScreen> {
  List<DifficultyLevel> _levels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLevels();
  }

  Future<void> _loadLevels() async {
    setState(() => _isLoading = true);

    final levels = await WordPackService.instance.getDifficultyLevels();

    if (!mounted) return;
    setState(() {
      _levels = levels;
      _isLoading = false;
    });
  }

  Future<void> _selectLevel(int level) async {
    // Mark onboarding as complete if this is onboarding
    if (widget.isOnboarding) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
    }

    if (!mounted) return;

    // Navigate to browse screen filtered to selected level
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => WordPackBrowseScreen(
          initialLevel: level,
          isOnboarding: widget.isOnboarding,
        ),
      ),
    );
  }

  void _skipOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Level'),
        automaticallyImplyLeading: !widget.isOnboarding,
        actions: widget.isOnboarding
            ? [
                TextButton(
                  onPressed: _skipOnboarding,
                  child: const Text('Skip'),
                ),
              ]
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isOnboarding) ...[
                  const Text(
                    'Welcome to Word Quizzer!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Let\'s find the right vocabulary level for you.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                const Text(
                  'Look at the sample words for each level and choose the one that feels challenging but not overwhelming.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildLevelCard(_levels[index]),
              childCount: _levels.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 32),
        ),
      ],
    );
  }

  Widget _buildLevelCard(DifficultyLevel level) {
    final colors = [
      Colors.green,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];
    final color = colors[(level.level - 1).clamp(0, colors.length - 1)];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectLevel(level.level),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withAlpha(51),
                    color.withAlpha(26),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color,
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.description,
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  if (level.sampleWords.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Sample words:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: level.sampleWords.map((word) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(26),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withAlpha(77),
                            ),
                          ),
                          child: Text(
                            word,
                            style: TextStyle(
                              color: color.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension ColorShade on Color {
  Color get shade700 {
    // Darken the color
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
  }
}
