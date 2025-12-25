import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_web.dart';

class AuthService {
  static const String tokenKey = 'sync_jwt';
  static const String defaultAuthBase = 'https://omnilearner-api.bryanlangley.org';
  static const String authPath = '/api/v1/auth/google';

  static Future<void> handleAuthRedirect() async {
    final token = await getTokenFromRedirect();
    if (token == null || token.trim().isEmpty) {
      return;
    }
    await saveToken(token.trim());
    clearAuthRedirect();
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(tokenKey);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
  }

  static Future<void> startGoogleLogin({String? redirectUrl}) async {
    final redirect = redirectUrl ?? currentOrigin();
    final url = Uri.parse(defaultAuthBase + authPath).replace(
      queryParameters: {
        'redirect': redirect,
      },
    );
    await startOAuth(url.toString());
  }

  static bool isTokenExpired(String token) {
    final payload = _decodePayload(token);
    if (payload == null) {
      return true;
    }
    final exp = payload['exp'];
    if (exp is! int) {
      return true;
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return DateTime.now().isAfter(expiry);
  }

  static String? tokenSubject(String token) {
    final payload = _decodePayload(token);
    final sub = payload?['sub'];
    return sub?.toString();
  }

  static Map<String, dynamic>? _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
