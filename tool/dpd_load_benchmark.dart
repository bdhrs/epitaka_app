// DPD dictionary load/query benchmark.
//
// Run from epitaka_app/:
//   dart run tool/dpd_load_benchmark.dart [path-to-dpd-dictionary.db]
//
// Measures each stage of the dictionary open + query path with concrete
// numbers, mirroring what DpdDictionaryDatabase does in the app.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

final class _Stage {
  final String name;
  final Stopwatch sw = Stopwatch()..start();
  _Stage(this.name);
}

class _Bench {
  final List<_Stage> _stages = [];
  _Stage stage(String name) {
    final s = _Stage(name);
    _stages.add(s);
    return s;
  }

  void report() {
    print('');
    print('════════ TIMING REPORT ════════');
    for (final s in _stages) {
      print(
        '${s.name.padRight(52)} '
        '${s.sw.elapsedMilliseconds.toString().padLeft(6)} ms',
      );
    }
  }
}

int _dbSize(String path) => File(path).lengthSync();

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '.';
  final dbPath = args.isNotEmpty
      ? args.first
      : '$home/Library/Containers/com.dn.epitaka/Data/Library/'
          'Application Support/com.dn.epitaka/dpd-dictionary.db';

  final bench = _Bench();
  final file = File(dbPath);
  if (!file.existsSync()) {
    stderr.writeln('DB not found at $dbPath');
    exit(2);
  }

  print('════════ ENVIRONMENT ════════');
  print('DB path : $dbPath');
  print('DB size : ${(_dbSize(dbPath) / (1024 * 1024)).toStringAsFixed(1)} MB');

  // ── Stage 1: sqlite3.open ───────────────────────────────────────────
  final openStage = bench.stage('sqlite3.open()');
  final db = sqlite3.open(dbPath);
  openStage.sw.stop();

  // ── Stage 2: PRAGMAs (exactly as DpdDictionaryDatabase.open) ────────
  final pragmaStage = bench.stage('PRAGMA journal_mode=WAL + foreign_keys');
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('PRAGMA foreign_keys=ON');
  pragmaStage.sw.stop();

  // ── Stage 3: first indexed exact lookup (cold cache) ────────────────
  final exactCold = bench.stage('exact lookup "sīla" (cold, first run)');
  final r1 = db.select(
    'SELECT lookup_key, headwords, deconstructor FROM dpd_lookup '
    'WHERE lookup_key = ?',
    ['sīla'],
  );
  exactCold.sw.stop();
  print(
    '   → rows=${r1.length} headwordsJsonLen='
    '${(r1.isNotEmpty ? r1.first['headwords'] as String? ?? '' : '').length}',
  );

  // ── Stage 4: warm exact lookups (cache + OS page cache warm) ────────
  const words = [
    'sīla', 'samādhi', 'paññā', 'dukkha', 'anicca', 'anattā',
    'mettā', 'kamma', 'nibbāna', 'sāra',
  ];
  final exactWarm = bench.stage('exact lookup x10 words (warm)');
  for (final w in words) {
    db.select(
      'SELECT lookup_key, headwords, deconstructor FROM dpd_lookup '
      'WHERE lookup_key = ?',
      [w],
    );
  }
  exactWarm.sw.stop();

  // ── Stage 5: prefix search — the app's searchLookup() query ─────────
  // This is `WHERE lookup_key LIKE 'xxx%'` — measure it for several
  // prefixes and report per-query time.
  final prefixStage = bench.stage('prefix LIKE search x10 prefixes');
  final perPrefix = <String, int>{};
  for (final w in words) {
    final sw = Stopwatch()..start();
    final rows = db.select(
      'SELECT lookup_key, headwords, deconstructor FROM dpd_lookup '
      "WHERE lookup_key LIKE ? LIMIT 25",
      ['$w%'],
    );
    sw.stop();
    perPrefix[w] = sw.elapsedMilliseconds;
    if (rows.isEmpty) print('   → "$w%": 0 rows');
  }
  prefixStage.sw.stop();
  final sortedPrefix = perPrefix.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print('   → slowest prefixes (ms): $sortedPrefix');

  // ── Stage 6: COUNT(*) — table scale reference ───────────────────────
  final countStage = bench.stage('COUNT(*) dpd_lookup (full scan)');
  final n = db.select('SELECT COUNT(*) c FROM dpd_lookup').first['c'] as int;
  countStage.sw.stop();
  print('   → dpd_lookup rows: $n');

  // ── Stage 7: full-scan cost of one LIKE query, isolated ─────────────
  // Force a cold-ish measurement by using a prefix that matches nothing,
  // so we pay the full 1.28M-row scan with minimal row output.
  final scanStage = bench.stage('LIKE "zzzz%" (no matches → full scan cost)');
  db.select(
    'SELECT lookup_key FROM dpd_lookup WHERE lookup_key LIKE ? LIMIT 25',
    ['zzzzqqqq%'],
  );
  scanStage.sw.stop();

  // ── Stage 8: case-sensitive GLOB equivalent (index-usable form) ─────
  final globStage = bench.stage('GLOB "Sīla*" (case-sensitive, indexable)');
  db.select(
    'SELECT lookup_key FROM dpd_lookup WHERE lookup_key GLOB ? LIMIT 25',
    ['${words[0][0].toUpperCase()}īla*'],
  );
  globStage.sw.stop();

  // ── Stage 9: headword fetch by ids (typical result set) ─────────────
  final hwStage = bench.stage('headwords by ids (10 ids, meaning_html)');
  final ids = <int>[];
  for (final w in words.take(3)) {
    final r = db.select(
      'SELECT headwords FROM dpd_lookup WHERE lookup_key = ?',
      [w],
    );
    if (r.isEmpty) continue;
    final list = (jsonDecode(r.first['headwords'] as String) as List).cast<int>();
    ids.addAll(list.take(4));
  }
  if (ids.isNotEmpty) {
    final ph = List.filled(ids.length, '?').join(',');
    db.select(
      'SELECT id, lemma_1, meaning_html FROM dpd_headwords '
      'WHERE id IN ($ph)',
      ids,
    );
  }
  hwStage.sw.stop();

  // ── Stage 10: JSON parse cost (what _parseLookupRow does per row) ────
  final parseStage = bench.stage('jsonDecode headwords+deconstructor x10');
  for (final w in words) {
    final r = db.select(
      'SELECT headwords, deconstructor FROM dpd_lookup WHERE lookup_key = ?',
      [w],
    );
    if (r.isEmpty) continue;
    jsonDecode(r.first['headwords'] as String? ?? '[]');
    jsonDecode(r.first['deconstructor'] as String? ?? '[]');
  }
  parseStage.sw.stop();

  // ── Stage 11: WAL file size + page cache info ───────────────────────
  final wal = File('$dbPath-wal');
  final shm = File('$dbPath-shm');
  print('');
  print('════════ DB FILE INFO ════════');
  print(
    'WAL file  : ${wal.existsSync() ? "${(wal.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB" : "absent"}',
  );
  print(
    'SHM file  : ${shm.existsSync() ? "${(shm.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB" : "absent"}',
  );

  bench.report();
  db.dispose();
}
