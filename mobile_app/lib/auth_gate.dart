import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'db_helper.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'sync_service.dart';
import 'word_packs/difficulty_assessment_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool isLoading = true;
  bool isAuthenticated = false;
  bool? _needsOnboarding;
  Timer? _syncTimer;
  bool _syncInFlight = false;
  static const Duration _syncInterval = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await AuthService.getToken();
    final valid = token != null && token.isNotEmpty && !AuthService.isTokenExpired(token);
    if (!mounted) return;
    setState(() {
      isAuthenticated = valid;
    });
    if (valid) {
      _startBackgroundSync();
      await _checkOnboarding();
    }
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

    if (onboardingComplete) {
      if (!mounted) return;
      setState(() => _needsOnboarding = false);
      return;
    }

    // Check if user has any words
    try {
      final stats = await DatabaseHelper.instance.getStats();
      final totalWords = stats['total'] ?? 0;
      if (!mounted) return;

      if (totalWords > 0) {
        // User already has words, mark onboarding as complete
        await prefs.setBool('onboarding_complete', true);
        setState(() => _needsOnboarding = false);
      } else {
        setState(() => _needsOnboarding = true);
      }
    } catch (_) {
      // If we can't check, assume no onboarding needed
      if (!mounted) return;
      setState(() => _needsOnboarding = false);
    }
  }

  void _startBackgroundSync() {
    if (_syncTimer != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBackgroundSync();
    });
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      _runBackgroundSync();
    });
  }

  Future<void> _runBackgroundSync() async {
    if (_syncInFlight) {
      return;
    }
    _syncInFlight = true;
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty || AuthService.isTokenExpired(token)) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('sync_server_url') ??
          'https://word-quizzer-api.bryanlangley.org';
      if (url.trim().isEmpty) {
        return;
      }
      final lastSyncAt = prefs.getString('last_sync_at') ?? '';
      if (lastSyncAt.isNotEmpty) {
        final last = DateTime.tryParse(lastSyncAt);
        if (last != null && DateTime.now().difference(last) < _syncInterval) {
          return;
        }
      }
      final service = SyncService(baseUrl: url, token: token);
      await service.sync();
      await prefs.setString('last_sync_at', DateTime.now().toIso8601String());
    } catch (_) {
      // Silent background sync.
    } finally {
      _syncInFlight = false;
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!isAuthenticated) {
      return const LoginScreen();
    }
    // Show onboarding for new users with no words
    if (_needsOnboarding == true) {
      return const DifficultyAssessmentScreen(isOnboarding: true);
    }
    return const HomeScreen();
  }
}
