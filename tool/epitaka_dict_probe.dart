// Epitaka content-DB probe for the dictionary path.
//
//   dart run tool/epitaka_dict_probe.dart [path-to-epitaka.db]
//
// Measures the queries behind the non-DPD dictionary sections that run on
// every dictionary open (dictionary_books list, per-book `dictionary`
// definition lookup, and the Pali-definition `pali_definition` + `sentences`
// lookups).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '.';
  final dbPath = args.isNotEmpty
      ? args.first
      : '$home/Library/Containers/com.dn.epitaka/Data/Library/'
          'Application Support/com.dn.epitaka/epitaka.db';

  final file = File(dbPath);
  if (!file.existsSync()) {
    stderr.writeln('DB not found at $dbPath');
    exit(2);
  }
  print('DB path : $dbPath');
  print('DB size : ${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB');

  final db = sqlite3.open(dbPath);

  void section(String t) => print('\n════════ $t ════════');

  section('dictionary_books (user prefs for the dictionary sections)');
  try {
    for (final r in db.select(
      'SELECT id, name, user_choice, user_order FROM dictionary_books '
      'ORDER BY user_order',
    )) {
      print('  id=${r['id']} choice=${r['user_choice']} order=${r['user_order']} '
          'name="${r['name']}"');
    }
  } catch (e) {
    print('  (no dictionary_books table: $e)');
  }

  section('Tables / row counts (dictionary-related)');
  for (final t in ['dictionary', 'pali_definition', 'sentences', 'dpd_lookup']) {
    try {
      final n = db.select('SELECT COUNT(*) c FROM "$t"').first['c'];
      print('  $t: $n rows');
    } catch (e) {
      print('  $t: absent ($e)');
    }
  }

  section('Indexes on dictionary-related tables');
  for (final t in ['dictionary', 'pali_definition', 'sentences']) {
    final ix = db.select(
      "SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='$t' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    if (ix.isEmpty) {
      print('  $t: NO indexes');
    } else {
      for (final r in ix) {
        print('  $t.${r['name']}: ${r['sql']}');
      }
    }
  }

  section('Dictionary definition query (per enabled book, per lookup)');
  void timeQuery(String label, String sql, List<Object?> params) {
    final plan = db
        .select('EXPLAIN QUERY PLAN $sql', params)
        .map((r) => r['detail'])
        .join(' | ');
    // Warm then measure 5 runs.
    for (var i = 0; i < 2; i++) {
      db.select(sql, params);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 5; i++) {
      db.select(sql, params);
    }
    sw.stop();
    print('  $label');
    print('    plan : $plan');
    print('    time : ${sw.elapsedMicroseconds / 5 / 1000} ms avg '
        '(5 runs, warm)');
  }

  // word = ? AND book_id = ? — the app's dictionaryDefinitionProvider.
  for (final bookId in ['100', '11', '2']) {
    timeQuery(
      'definition WHERE word="dhamma" book_id=$bookId LIMIT 5',
      'SELECT definition FROM dictionary WHERE word = ? AND book_id = ? LIMIT 5',
      ['dhamma', int.parse(bookId)],
    );
  }

  section('Pali-definition prefix + window query (book 100, "gacchati")');
  timeQuery(
    'pali_definition LIKE prefix with DENSE_RANK/ROW_NUMBER',
    'WITH ranked AS ( '
    '  SELECT book_id, para_id, line_id, word, plain, ending, '
    '         DENSE_RANK() OVER (ORDER BY length(word), word) AS word_rank, '
    '         ROW_NUMBER() OVER ('
    '           PARTITION BY word ORDER BY book_id, para_id, line_id) AS rn '
    '  FROM pali_definition WHERE word LIKE ? '
    ') '
    'SELECT book_id, para_id, line_id, word, plain, ending FROM ranked '
    'WHERE (word_rank <= ? OR word = ?) AND rn <= ? '
    'ORDER BY length(word), word, book_id, para_id, line_id',
    ['gacchat%', 25, 'gacchati', 5],
  );

  section('Sentences fetch (book/para, used per matched paragraph)');
  final sample = db.select(
    'SELECT book_id, para_id FROM pali_definition WHERE word = ? LIMIT 1',
    ['gacchati'],
  );
  if (sample.isNotEmpty) {
    final bookId = sample.first['book_id'];
    final paraId = sample.first['para_id'];
    timeQuery(
      'sentences WHERE book_id=? AND para_id IN (?)',
      'SELECT para_id, line_id, pali FROM sentences '
      'WHERE book_id = ? AND para_id IN (?)',
      [bookId, paraId],
    );
  }

  section('pali_definition sample words / case');
  for (final r in db.select(
    "SELECT word FROM pali_definition WHERE word LIKE 'gacchati%' LIMIT 6",
  )) {
    print('  "${r['word']}"');
  }

  db.dispose();
}
