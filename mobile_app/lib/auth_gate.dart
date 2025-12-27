import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'sync_service.dart';
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
    }
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
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
    return const HomeScreen();
  }
}
