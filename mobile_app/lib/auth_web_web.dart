// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<String?> getTokenFromRedirect() async {
  final fragment = html.window.location.hash;
  if (fragment.isEmpty || fragment.length <= 1) {
    return null;
  }
  final params = Uri.splitQueryString(fragment.substring(1));
  final token = params['token'];
  return token;
}

void clearAuthRedirect() {
  final location = html.window.location;
  final newUrl = '${location.origin}${location.pathname}';
  html.window.history.replaceState(null, 'auth', newUrl);
}

Future<void> startOAuth(String url) async {
  html.window.location.assign(url);
}

String currentOrigin() => html.window.location.origin;
