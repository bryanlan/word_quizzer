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
  // Timeout for initial operations - prevents infinite spinning on iOS
  static const Duration _initTimeout = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final token = await AuthService.getToken().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      final valid = token != null && token.isNotEmpty && !AuthService.isTokenExpired(token);
      if (!mounted) return;
      setState(() {
        isAuthenticated = valid;
      });
      if (valid) {
        // Sync from server FIRST to get user's words, then check onboarding
        // Use timeout to prevent iOS Safari hanging on database operations
        await _doInitialSync().timeout(_initTimeout, onTimeout: () {
          // Silently continue if sync times out - user can retry later
        });
        await _checkOnboarding().timeout(_initTimeout, onTimeout: () {
          // Default to no onboarding if check times out
          if (mounted) setState(() => _needsOnboarding = false);
        });
        _startBackgroundSync();
      }
    } catch (e) {
      // If any error occurs during auth check, fall back to login screen
      if (mounted) {
        setState(() {
          isAuthenticated = false;
        });
      }
    }
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _doInitialSync() async {
    try {
      final token = await AuthService.getToken().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      if (token == null || token.isEmpty) return;
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('SharedPreferences timeout'),
      );
      final url = prefs.getString('sync_server_url') ??
          'https://word-quizzer-api.bryanlangley.org';
      if (url.trim().isEmpty) return;
      final service = SyncService(baseUrl: url, token: token);
      // Allow sync up to 30 seconds before timing out
      await service.sync().timeout(const Duration(seconds: 30));
      await prefs.setString('last_sync_at', DateTime.now().toIso8601String());
    } catch (_) {
      // If sync fails or times out, continue anyway
    }
  }

  Future<void> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('SharedPreferences timeout'),
      );
      final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

      if (onboardingComplete) {
        if (!mounted) return;
        setState(() => _needsOnboarding = false);
        return;
      }

      // Check if user has any words
      // Use timeout to prevent iOS Safari hanging on database operations
      final stats = await DatabaseHelper.instance.getStats().timeout(
        const Duration(seconds: 10),
        onTimeout: () => {'total': 0}, // Default to empty on timeout
      );
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
      // If we can't check (e.g., iOS Safari issues), assume no onboarding needed
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
