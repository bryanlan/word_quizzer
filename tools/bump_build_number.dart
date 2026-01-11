import 'dart:io';

void main() {
  final file = File('mobile_app/pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('pubspec.yaml not found at ${file.path}');
    exit(1);
  }

  final lines = file.readAsLinesSync();
  final versionPattern = RegExp(r'^\s*version:\s*([^\s+]+)(?:\+(\d+))?\s*$');
  var updated = false;

  for (var i = 0; i < lines.length; i++) {
    final match = versionPattern.firstMatch(lines[i]);
    if (match == null) continue;
    final base = match.group(1) ?? '0.0.0';
    final buildRaw = match.group(2) ?? '0';
    final build = int.tryParse(buildRaw) ?? 0;
    final next = build + 1;
    lines[i] = 'version: $base+$next';
    stdout.writeln('Bumped version to $base+$next');
    updated = true;
    break;
  }

  if (!updated) {
    stderr.writeln('No version line found in ${file.path}');
    exit(1);
  }

  file.writeAsStringSync('${lines.join('\n')}\n');
}
