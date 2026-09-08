// Measures the win of indexing dictionary(word, book_id) on a throwaway
// COPY of epitaka.db (never touches the real DB).
//
//   dart run tool/epitaka_dict_index_test.dart [path-to-epitaka.db]

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '.';
  final srcPath = args.isNotEmpty
      ? args.first
      : '$home/Library/Containers/com.dn.epitaka/Data/Library/'
          'Application Support/com.dn.epitaka/epitaka.db';

  final tmp = File(
    '${Directory.systemTemp.path}/epitaka_index_test_${DateTime.now().millisecondsSinceEpoch}.db',
  );
  print('Copying ${File(srcPath).lengthSync() ~/ 1048576} MB → $tmp …');
  File(srcPath).copySync(tmp.path);

  final db = sqlite3.open(tmp.path);
  db.execute('PRAGMA journal_mode=OFF');

  void run(String label) {
    // 3 warm-up + 5 measured, the way the app runs it per book.
    const sql =
        'SELECT definition FROM dictionary WHERE word = ? AND book_id = ? LIMIT 5';
    for (var i = 0; i < 2; i++) {
      db.select(sql, ['dhamma', 6]);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      db.select(sql, ['dhamma', 6]);
    }
    sw.stop();
    print('  $label: ${(sw.elapsedMicroseconds / 5000).toStringAsFixed(2)} ms '
        'avg (5 warm runs)');
  }

  print('\n── BEFORE (no index) ──');
  run('scan');

  print('\n── CREATE INDEX idx_dictionary_word_book ──');
  final ix = Stopwatch()..start();
  db.execute(
    'CREATE INDEX idx_dictionary_word_book ON dictionary(word, book_id)',
  );
  ix.stop();
  print('  build time: ${ix.elapsedMilliseconds} ms');
  print('  temp DB size: ${(tmp.lengthSync() ~/ 1048576)} MB');

  print('\n── AFTER (indexed) ──');
  run('index seek');

  // And the plan:
  final plan = db
      .select(
        'EXPLAIN QUERY PLAN SELECT definition FROM dictionary '
        'WHERE word = ? AND book_id = ? LIMIT 5',
        ['dhamma', 6],
      )
      .map((r) => r['detail'])
      .join(' | ');
  print('  plan: $plan');

  db.dispose();
  tmp.deleteSync();
}
