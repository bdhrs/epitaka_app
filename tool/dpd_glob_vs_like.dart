// Compares the current LIKE-prefix suggestions with an index-usable GLOB
// prefix over the same words: same rows (before LIMIT 25), same order?
//
//   dart run tool/dpd_glob_vs_like.dart [path-to-dpd-dictionary.db]

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '.';
  final dbPath = args.isNotEmpty
      ? args.first
      : '$home/Library/Containers/com.dn.epitaka/Data/Library/'
          'Application Support/com.dn.epitaka/dpd-dictionary.db';
  final db = sqlite3.open(dbPath);

  const words = [
    'sīla', 'buddha', 'dhamma', 'kamma', 'mettā', 'nibbāna',
    'anicca', 'gacchati', 'bhikkhu', 'sacca', 'vipassanā', 'jāti',
  ];

  for (final w in words) {
    final like = db.select(
      'SELECT lookup_key FROM dpd_lookup WHERE lookup_key LIKE ? LIMIT 25',
      ['$w%'],
    ).map((r) => r['lookup_key'] as String).toList();
    final glob = db.select(
      'SELECT lookup_key FROM dpd_lookup WHERE lookup_key GLOB ? LIMIT 25',
      ['$w*'],
    ).map((r) => r['lookup_key'] as String).toList();

    final onlyLike = like.where((k) => !glob.contains(k)).toList();
    final onlyGlob = glob.where((k) => !like.contains(k)).toList();
    final sameOrder = like.join('|') == glob.join('|');
    print(
      '"$w": LIKE=${like.length} GLOB=${glob.length} '
      'sameTop25=$sameOrder '
      'likeOnly=${onlyLike.length > 2 ? onlyLike.length : onlyLike} '
      'globOnly=${onlyGlob.length > 2 ? onlyGlob.length : onlyGlob}',
    );
    if (onlyLike.isNotEmpty && onlyLike.length <= 2) {
      print('    likeOnly keys: $onlyLike');
    }
    if (onlyGlob.isNotEmpty && onlyGlob.length <= 2) {
      print('    globOnly keys: $onlyGlob');
    }
  }

  db.dispose();
}
