import 'dart:io';

Future<void> importDatabaseFile(String sourcePath, String destPath) async {
  await File(sourcePath).copy(destPath);
}

bool get supportsDatabaseFileImport => true;
