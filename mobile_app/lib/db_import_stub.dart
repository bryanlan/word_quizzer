Future<void> importDatabaseFile(String sourcePath, String destPath) {
  throw UnsupportedError('Database import is not supported on web.');
}

bool get supportsDatabaseFileImport => false;
