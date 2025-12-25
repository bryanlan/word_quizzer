Future<String?> getTokenFromRedirect() async => null;

void clearAuthRedirect() {}

Future<void> startOAuth(String url) async {
  throw UnsupportedError('OAuth is only available on web.');
}

String currentOrigin() => '';
