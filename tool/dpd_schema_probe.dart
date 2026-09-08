// DPD dictionary schema / query-plan probe.
//
//   dart run tool/dpd_schema_probe.dart [path-to-dpd-dictionary.db]
//
// Prints table info, indexes and EXPLAIN QUERY PLAN for the exact queries
// the app runs, to show why prefix LIKE scans are slow.

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
  db.execute('PRAGMA journal_mode=WAL');

  void section(String title) {
    print('\n════════ $title ════════');
  }

  section('TABLES & ROW COUNTS');
  final tables = db.select(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  for (final t in tables) {
    final name = t['name'] as String;
    final n = db.select('SELECT COUNT(*) c FROM "$name"').first['c'];
    print('  $name: $n rows');
  }

  section('INDEXES');
  final indexes = db.select(
    "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='index' "
    "AND name NOT LIKE 'sqlite_%'",
  );
  for (final ix in indexes) {
    print('  ${ix['tbl_name']}.${ix['name']}: ${ix['sql']}');
  }

  section('dpd_lookup sample keys (case / diacritics)');
  for (final r in db.select(
    'SELECT lookup_key FROM dpd_lookup LIMIT 8',
  )) {
    print('  "${r['lookup_key']}"');
  }

  section('EXPLAIN QUERY PLAN');
  void plan(String label, String sql, [List<Object?> params = const []]) {
    final rows = db.select('EXPLAIN QUERY PLAN $sql', params);
    final detail = rows.map((r) => r['detail']).join('  |  ');
    print('  $label\n    $detail');
  }

  plan('exact lookup (app getLookup)',
      'SELECT lookup_key, headwords, deconstructor FROM dpd_lookup '
      'WHERE lookup_key = ?', ['sīla']);
  plan('prefix LIKE (app searchLookup)',
      'SELECT lookup_key, headwords, deconstructor FROM dpd_lookup '
      'WHERE lookup_key LIKE ? LIMIT 25', ['mettā%']);
  plan('prefix GLOB (case-sensitive)',
      'SELECT lookup_key FROM dpd_lookup WHERE lookup_key GLOB ? LIMIT 25',
      ['mettā*']);
  plan('range >= < (lowercase, binary)',
      'SELECT lookup_key FROM dpd_lookup WHERE lookup_key >= ? '
      'AND lookup_key < ? LIMIT 25', ['mettā', 'mettb']);

  // Collation of lookup_key: find mixed-case duplicates that only differ
  // by ASCII case, which shows whether LIKE must do case folding.
  section('Case variants of a prefix in dpd_lookup');
  final variants = db.select(
    "SELECT lookup_key FROM dpd_lookup WHERE lookup_key LIKE 'sila%' "
    'ORDER BY lookup_key LIMIT 6',
  );
  for (final v in variants) {
    print('  "${v['lookup_key']}"');
  }

  db.dispose();
}
