import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'sync_service.dart';
import 'db_helper.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool isLoading = true;
  bool isAuthenticated = false;
  bool isSyncing = false;
  String syncMessage = '';

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
    if (valid && token != null) {
      await _maybeAutoSync(token);
    }
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _maybeAutoSync(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncAt = prefs.getString('last_sync_at') ?? '';
    final stats = await DatabaseHelper.instance.getStats();
    final total = stats['total'] as int? ?? 0;
    if (lastSyncAt.isNotEmpty && total > 0) {
      return;
    }
    final url = prefs.getString('sync_server_url') ??
        'https://word-quizzer-api.bryanlangley.org';
    if (url.trim().isEmpty) {
      return;
    }
    if (!mounted) return;
    setState(() {
      isSyncing = true;
      syncMessage = 'Syncing your library...';
    });
    try {
      final service = SyncService(baseUrl: url, token: token);
      await service.sync();
      await prefs.setString('last_sync_at', DateTime.now().toIso8601String());
    } catch (_) {
      // Keep silent; user can retry in Settings.
    } finally {
      if (mounted) {
        setState(() {
          isSyncing = false;
          syncMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (isSyncing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(syncMessage, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    if (!isAuthenticated) {
      return const LoginScreen();
    }
    return const HomeScreen();
  }
}
