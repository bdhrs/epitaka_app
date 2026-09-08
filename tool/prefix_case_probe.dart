// Verifies the case invariants the app relies on for case-sensitive prefix
// matching (GLOB / range) to be equivalent to the current case-insensitive
// LIKE queries.
//
//   dart run tool/prefix_case_probe.dart [dpd-db] [epitaka-db]

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '.';
  final dpd = args.isNotEmpty
      ? args[0]
      : '$home/Library/Containers/com.dn.epitaka/Data/Library/'
          'Application Support/com.dn.epitaka/dpd-dictionary.db';
  final epi = args.length > 1
      ? args[1]
      : '$home/Library/Containers/com.dn.epitaka/Data/Library/'
          'Application Support/com.dn.epitaka/epitaka.db';

  void checkColumn(Database db, String table, String column) {
    final total =
        db.select('SELECT COUNT(*) c FROM "$table"').first['c'] as int;
    final asciiUpper = db
        .select('SELECT COUNT(*) c FROM "$table" '
            'WHERE "$column" GLOB "*[A-Z]*"')
        .first['c'] as int;

    // Scan the whole column through Dart's Unicode toLowerCase — catches any
    // uppercase diacritic (Ā, Ṭ…) too.
    var dartDiff = 0;
    var checked = 0;
    for (final r in db.select('SELECT "$column" v FROM "$table"')) {
      final v = r['v'] as String? ?? '';
      if (v.toLowerCase() != v) dartDiff++;
      checked++;
      if (checked >= 500000) break;
    }
    final sampled = checked < total;
    print(
      '  $table.$column: total=$total ascii-uppercase=$asciiUpper '
      'unicode-lower-diffs(first $checked rows)=$dartDiff '
      '${sampled ? '(sampled)' : ''}',
    );
  }

  print('════════ dpd-dictionary.db ════════');
  final d = sqlite3.open(dpd);
  checkColumn(d, 'dpd_lookup', 'lookup_key');
  d.dispose();

  print('\n════════ epitaka.db ════════');
  final e = sqlite3.open(epi);
  checkColumn(e, 'pali_definition', 'word');
  checkColumn(e, 'dictionary', 'word');
  e.dispose();
}
