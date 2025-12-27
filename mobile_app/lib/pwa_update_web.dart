import 'dart:html' as html;

Future<void> refreshApp() async {
  final registration = await html.window.navigator.serviceWorker?.getRegistration();
  await registration?.update();
  final waiting = registration?.waiting;
  if (waiting != null) {
    waiting.postMessage('skipWaiting');
  }
  html.window.location.reload();
}
