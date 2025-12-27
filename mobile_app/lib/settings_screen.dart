import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'openrouter_service.dart';
import 'sync_service.dart';
import 'auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int quizLength = 20;
  int maxLearning = 20;
  int maxProficient = 20;
  int maxAdept = 30;
  int masteredPct = 10;
  int promoteLearning = 3;
  int promoteProficient = 4;
  int promoteAdept = 5;
  int withinStageBias = 0;
  bool showApiKey = false;
  final TextEditingController apiKeyController = TextEditingController();
  final TextEditingController displayNameController = TextEditingController();
  final TextEditingController syncUrlController = TextEditingController();
  bool isTestingKey = false;
  bool isTestingSync = false;
  bool isSyncing = false;
  String lastSyncAt = '';
  String authStatusLabel = 'Not signed in';
  String authSubject = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      quizLength = prefs.getInt('quiz_length') ?? 20;
      maxLearning = prefs.getInt('max_learning') ?? 20;
      maxProficient = prefs.getInt('max_proficient') ?? 20;
      maxAdept = prefs.getInt('max_adept') ?? 30;
      masteredPct = prefs.getInt('pct_mastered') ?? 10;
      promoteLearning = prefs.getInt('promote_learning_correct') ?? 3;
      promoteProficient = prefs.getInt('promote_proficient_correct') ?? 4;
      promoteAdept = prefs.getInt('promote_adept_correct') ?? 5;
      withinStageBias = prefs.getInt('within_stage_bias') ?? 1;
      apiKeyController.text = prefs.getString('openrouter_api_key') ?? '';
      displayNameController.text = prefs.getString('display_name') ?? '';
      syncUrlController.text =
          prefs.getString('sync_server_url') ?? 'https://word-quizzer-api.bryanlangley.org';
      lastSyncAt = prefs.getString('last_sync_at') ?? '';
      final token = prefs.getString(AuthService.tokenKey) ?? '';
      if (token.isEmpty) {
        authStatusLabel = 'Not signed in';
        authSubject = '';
      } else if (AuthService.isTokenExpired(token)) {
        authStatusLabel = 'Session expired';
        authSubject = _shortenSubject(AuthService.tokenSubject(token));
      } else {
        authStatusLabel = 'Signed in';
        authSubject = _shortenSubject(AuthService.tokenSubject(token));
      }
    });
  }

  String _shortenSubject(String? subject) {
    if (subject == null || subject.isEmpty) {
      return '';
    }
    if (subject.length <= 12) {
      return subject;
    }
    return '${subject.substring(0, 6)}...${subject.substring(subject.length - 4)}';
  }

  String _biasLabel(int value) {
    switch (value) {
      case 1:
        return 'Moderately';
      case 2:
        return 'Heavily';
      default:
        return 'None';
    }
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

  Future<void> _saveSyncSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_server_url', syncUrlController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync settings saved.')),
    );
  }

  Future<void> _testSync() async {
    final url = syncUrlController.text.trim();
    final token = await AuthService.getToken() ?? '';
    if (url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to sync.')),
      );
      return;
    }
    if (AuthService.isTokenExpired(token)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please sign in again.')),
      );
      return;
    }
    setState(() {
      isTestingSync = true;
    });
    try {
      final service = SyncService(baseUrl: url, token: token);
      await service.testAuth();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sync auth verified.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync test failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isTestingSync = false;
        });
      }
    }
  }

  Future<void> _runSync() async {
    final url = syncUrlController.text.trim();
    final token = await AuthService.getToken() ?? '';
    if (url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to sync.')),
      );
      return;
    }
    if (AuthService.isTokenExpired(token)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please sign in again.')),
      );
      return;
    }
    setState(() {
      isSyncing = true;
    });
    try {
      final service = SyncService(baseUrl: url, token: token);
      final summary = await service.sync();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      await prefs.setString('last_sync_at', now);
      if (!mounted) return;
      setState(() {
        lastSyncAt = now;
        authStatusLabel = 'Signed in';
      });
      final secondPassNote = summary.hadSecondPass ? ' (two-pass)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync complete$secondPassNote. '
            '${summary.wordsCreated} new, ${summary.wordsUpdated} updated.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    apiKeyController.dispose();
    displayNameController.dispose();
    syncUrlController.dispose();
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
              "Stage Caps",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "We bias quizzes toward stages that exceed these caps.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            _buildCapSlider(
              label: "Max Learning",
              value: maxLearning,
              onChanged: (value) {
                _saveSetting('max_learning', value);
                setState(() => maxLearning = value);
              },
            ),
            _buildCapSlider(
              label: "Max Proficient",
              value: maxProficient,
              onChanged: (value) {
                _saveSetting('max_proficient', value);
                setState(() => maxProficient = value);
              },
            ),
            _buildCapSlider(
              label: "Max Adept",
              value: maxAdept,
              onChanged: (value) {
                _saveSetting('max_adept', value);
                setState(() => maxAdept = value);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              "Within-Stage Bias",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "We pick words randomly within a learning stage. "
              "How much to bias less picked words?",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            Slider(
              value: withinStageBias.toDouble(),
              min: 0,
              max: 2,
              divisions: 2,
              label: _biasLabel(withinStageBias),
              onChanged: (val) {
                final value = val.round();
                _saveSetting('within_stage_bias', value);
                setState(() => withinStageBias = value);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text("None", style: TextStyle(color: Colors.grey)),
                Text("Moderately", style: TextStyle(color: Colors.grey)),
                Text("Heavily", style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              "Mastered Share (%)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Fixed portion of each quiz reserved for Mastered words.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 6),
            Text(
              "Mastered backlog is unlimited; only this share controls quiz load.",
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildMasteredSlider(
              value: masteredPct,
              onChanged: (value) {
                _saveSetting('pct_mastered', value);
                setState(() => masteredPct = value);
              },
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
            if (!kIsWeb) ...[
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
            ] else ...[
              const Text(
                "OpenRouter (Server)",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                "The web app uses a server-managed OpenRouter key.",
                style: TextStyle(color: Colors.grey[400]),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              "Sync",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Use your Omnilearner JWT to sync data across devices.",
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: syncUrlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Server URL",
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(authStatusLabel, style: TextStyle(color: Colors.grey[400])),
                if (authSubject.isNotEmpty)
                  Text(
                    authSubject,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saveSyncSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Save Sync Settings"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await AuthService.clearToken();
                      if (!mounted) return;
                      setState(() {
                        authStatusLabel = 'Not signed in';
                        authSubject = '';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Signed out.')),
                      );
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text("Sign Out"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      try {
                        await AuthService.startGoogleLogin();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Login unavailable: $e')),
                        );
                      }
                    },
                    child: const Text("Sign in with Google"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isSyncing ? null : _runSync,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: isSyncing
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Sync Now"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isTestingSync ? null : _testSync,
                child: isTestingSync
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Test Sync"),
              ),
            ),
            if (lastSyncAt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "Last sync: $lastSyncAt",
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapSlider({
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
          min: 5,
          max: 200,
          divisions: 39,
          label: value.toString(),
          onChanged: (val) => onChanged(val.toInt()),
        ),
      ],
    );
  }

  Widget _buildMasteredSlider({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Mastered"),
            Text(
              "$value%",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 50,
          divisions: 10,
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
