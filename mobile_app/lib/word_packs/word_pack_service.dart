import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models.dart';
import '../db_helper.dart';

/// Service for loading and managing word packs from assets and server
class WordPackService {
  static final WordPackService instance = WordPackService._();
  WordPackService._();

  WordPackManifest? _cachedManifest;
  final Map<String, WordPackData> _cachedPacks = {};

  /// Load the manifest from assets
  Future<WordPackManifest> loadManifest() async {
    if (_cachedManifest != null) {
      return _cachedManifest!;
    }

    try {
      final jsonString =
          await rootBundle.loadString('assets/word_packs/manifest.json');
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      _cachedManifest = WordPackManifest.fromJson(json);
      return _cachedManifest!;
    } catch (e) {
      // Return empty manifest on error
      return const WordPackManifest(
        version: 1,
        difficultyLevels: [],
        packs: [],
      );
    }
  }

  /// Get difficulty levels from manifest
  Future<List<DifficultyLevel>> getDifficultyLevels() async {
    final manifest = await loadManifest();
    if (manifest.difficultyLevels.isEmpty) {
      return DifficultyLevel.levels;
    }
    return manifest.difficultyLevels;
  }

  /// Get all available packs
  Future<List<WordPack>> getAvailablePacks() async {
    final manifest = await loadManifest();
    return manifest.packs;
  }

  /// Get packs for a specific difficulty level
  Future<List<WordPack>> getPacksForLevel(int level) async {
    final manifest = await loadManifest();
    return manifest.packs
        .where((pack) => pack.difficultyLevel == level)
        .toList();
  }

  /// Load full pack data by pack ID
  Future<WordPackData?> loadPackData(String packId) async {
    // Check cache first
    if (_cachedPacks.containsKey(packId)) {
      return _cachedPacks[packId];
    }

    // Find pack metadata
    final manifest = await loadManifest();
    final packMeta = manifest.packs.where((p) => p.id == packId).firstOrNull;
    if (packMeta == null || packMeta.assetPath == null) {
      return null;
    }

    try {
      final jsonString = await rootBundle
          .loadString('assets/word_packs/${packMeta.assetPath}');
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final packData = WordPackData.fromJson(json);
      _cachedPacks[packId] = packData;
      return packData;
    } catch (e) {
      return null;
    }
  }

  /// Get pack metadata by ID
  Future<WordPack?> getPackById(String packId) async {
    final manifest = await loadManifest();
    return manifest.packs.where((p) => p.id == packId).firstOrNull;
  }

  /// Check if a pack has been imported
  Future<bool> isPackImported(String packId) async {
    return DatabaseHelper.instance.isPackImported(packId);
  }

  /// Get list of imported pack IDs
  Future<Set<String>> getImportedPackIds() async {
    final ids = await DatabaseHelper.instance.getImportedPackIds();
    return ids.toSet();
  }

  /// Get packs with import status for a level
  Future<List<PackWithStatus>> getPacksWithStatus(int level) async {
    final packs = await getPacksForLevel(level);
    final importedIds = await getImportedPackIds();

    return packs.map((pack) {
      return PackWithStatus(
        pack: pack,
        isImported: importedIds.contains(pack.id),
      );
    }).toList();
  }

  /// Get all packs with import status
  Future<List<PackWithStatus>> getAllPacksWithStatus() async {
    final packs = await getAvailablePacks();
    final importedIds = await getImportedPackIds();

    return packs.map((pack) {
      return PackWithStatus(
        pack: pack,
        isImported: importedIds.contains(pack.id),
      );
    }).toList();
  }

  /// Import a pack's words into the database
  Future<PackImportResult> importPack(
    String packId,
    List<PackWordImport> words,
  ) async {
    final result = await DatabaseHelper.instance.importPackWords(words);

    // Record the pack import
    final pack = await getPackById(packId);
    if (pack != null) {
      await DatabaseHelper.instance.recordPackImport(
        packId,
        result.added,
        pack.difficultyLevel,
      );
    }

    return result;
  }

  /// Clear cached data (useful for testing or after app update)
  void clearCache() {
    _cachedManifest = null;
    _cachedPacks.clear();
  }
}

/// Pack with its import status
class PackWithStatus {
  final WordPack pack;
  final bool isImported;

  const PackWithStatus({
    required this.pack,
    required this.isImported,
  });
}
