import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'openrouter_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int activeLimit = 20;
  int quizLength = 20;
  int pctLearning = 60;
  int pctProficient = 20;
  int pctAdept = 15;
  int pctMastered = 5;
  int promoteLearning = 3;
  int promoteProficient = 4;
  int promoteAdept = 5;
  bool showApiKey = false;
  final TextEditingController apiKeyController = TextEditingController();
  final TextEditingController displayNameController = TextEditingController();
  bool isTestingKey = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      activeLimit = prefs.getInt('active_limit') ?? 20;
      quizLength = prefs.getInt('quiz_length') ?? 20;
      pctLearning = prefs.getInt('pct_learning') ?? 60;
      pctProficient = prefs.getInt('pct_proficient') ?? 20;
      pctAdept = prefs.getInt('pct_adept') ?? 15;
      pctMastered = prefs.getInt('pct_mastered') ?? 5;
      promoteLearning = prefs.getInt('promote_learning_correct') ?? 3;
      promoteProficient = prefs.getInt('promote_proficient_correct') ?? 4;
      promoteAdept = prefs.getInt('promote_adept_correct') ?? 5;
      apiKeyController.text = prefs.getString('openrouter_api_key') ?? '';
      displayNameController.text = prefs.getString('display_name') ?? '';
    });
  }

  Future<void> _saveSettings(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_limit', value);
    setState(() {
      activeLimit = value;
    });
  }

  Future<void> _saveSetting(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = apiKeyController.text.trim();
    await prefs.setString('openrouter_api_key', trimmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OpenRouter key saved.')),
    );
  }

  Future<void> _clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('openrouter_api_key');
    setState(() {
      apiKeyController.text = '';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OpenRouter key cleared.')),
    );
  }

  Future<void> _saveDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = displayNameController.text.trim();
    await prefs.setString('display_name', trimmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Display name saved.')),
    );
  }

  Future<void> _clearDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('display_name');
    setState(() {
      displayNameController.text = '';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Display name cleared.')),
    );
  }

  Future<void> _testApiKey() async {
    final key = apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an OpenRouter key first.')),
      );
      return;
    }
    setState(() {
      isTestingKey = true;
    });
    try {
      final service = OpenRouterService(key);
      await service.testKey();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OpenRouter key is valid.')),
      );
    } on InvalidApiKeyException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OpenRouter API key.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Key test failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isTestingKey = false;
        });
      }
    }
  }

  int _totalPercent() {
    return pctLearning + pctProficient + pctAdept + pctMastered;
  }

  @override
  void dispose() {
    apiKeyController.dispose();
    displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text(
              "Active Learning Cap",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "How many words should be in the active 'Learning' phase at once? "
              "Words are pulled from 'On Deck' to fill this cap.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("5 Words"),
                Text(
                  "$activeLimit",
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                ),
                const Text("100 Words"),
              ],
            ),
            Slider(
              value: activeLimit.toDouble(),
              min: 5,
              max: 100,
              divisions: 19,
              label: activeLimit.toString(),
              onChanged: (val) => _saveSettings(val.toInt()),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              "Quiz Settings",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "How many questions per quiz?",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("5"),
                Text(
                  "$quizLength",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                ),
                const Text("50"),
              ],
            ),
            Slider(
              value: quizLength.toDouble(),
              min: 5,
              max: 50,
              divisions: 9,
              label: quizLength.toString(),
              onChanged: (val) {
                final value = val.toInt();
                _saveSetting('quiz_length', value);
                setState(() => quizLength = value);
              },
            ),
            const SizedBox(height: 20),
            const Text(
              "Quiz Mix (%)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "If the total isn't 100%, we normalize the mix automatically.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            _buildPercentSlider(
              label: "Learning",
              value: pctLearning,
              color: Colors.orangeAccent,
              onChanged: (value) {
                _saveSetting('pct_learning', value);
                setState(() => pctLearning = value);
              },
            ),
            _buildPercentSlider(
              label: "Proficient",
              value: pctProficient,
              color: Colors.tealAccent,
              onChanged: (value) {
                _saveSetting('pct_proficient', value);
                setState(() => pctProficient = value);
              },
            ),
            _buildPercentSlider(
              label: "Adept",
              value: pctAdept,
              color: Colors.purpleAccent,
              onChanged: (value) {
                _saveSetting('pct_adept', value);
                setState(() => pctAdept = value);
              },
            ),
            _buildPercentSlider(
              label: "Mastered",
              value: pctMastered,
              color: Colors.greenAccent,
              onChanged: (value) {
                _saveSetting('pct_mastered', value);
                setState(() => pctMastered = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              "Total: ${_totalPercent()}%",
              style: TextStyle(
                color: _totalPercent() == 100 ? Colors.grey[400] : Colors.amberAccent,
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              "Promotion Rules",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Consecutive correct answers required to level up.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            _buildStreakSlider(
              label: "Learning → Proficient",
              value: promoteLearning,
              onChanged: (value) {
                _saveSetting('promote_learning_correct', value);
                setState(() => promoteLearning = value);
              },
            ),
            _buildStreakSlider(
              label: "Proficient → Adept",
              value: promoteProficient,
              onChanged: (value) {
                _saveSetting('promote_proficient_correct', value);
                setState(() => promoteProficient = value);
              },
            ),
            _buildStreakSlider(
              label: "Adept → Mastered",
              value: promoteAdept,
              onChanged: (value) {
                _saveSetting('promote_adept_correct', value);
                setState(() => promoteAdept = value);
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              "Display Name",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Shown in the greeting on the home screen.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: displayNameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Scholar",
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveDisplayName,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Save Name"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearDisplayName,
                    child: const Text("Clear Name"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              "OpenRouter API Key",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Used to generate definitions, examples, and distractors on-device.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: apiKeyController,
              obscureText: !showApiKey,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: "sk-or-...",
                suffixIcon: IconButton(
                  icon: Icon(showApiKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      showApiKey = !showApiKey;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveApiKey,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Save Key"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearApiKey,
                    child: const Text("Clear Key"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isTestingKey ? null : _testApiKey,
                child: isTestingKey
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Test Key"),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPercentSlider({
    required String label,
    required int value,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              "$value%",
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: value.toString(),
          onChanged: (val) => onChanged(val.toInt()),
        ),
      ],
    );
  }

  Widget _buildStreakSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              "$value",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: value.toString(),
          onChanged: (val) => onChanged(val.toInt()),
        ),
      ],
    );
  }
}
