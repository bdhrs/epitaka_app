/// Regression tests for double-tap dictionary lookup inside previews
/// ([PreviewContent], used by the book-link bottom sheet, search quickview
/// and outline section sheet).
///
/// Previously the double-tap handler split the whole line into words and
/// always looked up `words.first`, so double-tapping ANY word of a line
/// opened the dictionary for the line's first word. The fix resolves the
/// word UNDER the tap position from the rendered paragraph, so these tests
/// double-tap a later word of the line and expect that exact word.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:epitaka/core/providers/settings_provider.dart';
import 'package:epitaka/shared/widgets/preview_content.dart';

void main() {
  Widget wrap({
    required String pali,
    String? paliSnippet,
    required void Function(String) onWord,
  }) =>
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) {
            final notifier = SettingsNotifier(null);
            notifier.state = const AppSettings();
            return notifier;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreviewContent(
                lines: [
                  PreviewLineData(paraId: 1, lineId: 1, pali: pali),
                ],
                // When a snippet is given, it replaces the line's Pāli text
                // (same as the search quickview: index 0, para 1, <mark>).
                highlightParaId: paliSnippet != null ? 1 : null,
                firstSnippetIndex: paliSnippet != null ? 0 : null,
                paliSnippet: paliSnippet,
                onPaliWordTap: onWord,
              ),
            ),
          ),
        ),
      );

  /// The [RenderParagraph] whose plain text is [plainText].
  RenderParagraph paragraphOf(WidgetTester tester, String plainText) =>
      tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().trim() == plainText,
        ),
      );

  /// Global coordinates of the center of [word] as rendered by [paragraph].
  Offset wordCenter(RenderParagraph paragraph, String word) {
    final plain = paragraph.text.toPlainText();
    final start = plain.indexOf(word);
    expect(start, greaterThanOrEqualTo(0),
        reason: '"$word" must be inside "$plain"');
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: start,
        extentOffset: start + word.length,
      ),
    );
    expect(boxes, isNotEmpty, reason: 'word "$word" must have a render box');
    return paragraph.localToGlobal(boxes.first.toRect().center);
  }

  /// Two quick taps at [pos] — a double-tap for the GestureDetector.
  Future<void> doubleTapAt(WidgetTester tester, Offset pos) async {
    await tester.tapAt(pos);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(pos);
    await tester.pump();
  }

  testWidgets('double-tap on the 2nd word of a line looks up that word, '
      'not the first', (tester) async {
    const pali = 'dhammaṃ khetta ādhipateyya';
    final lookedUp = <String>[];
    await tester.pumpWidget(
      wrap(pali: pali, onWord: lookedUp.add),
    );
    await tester.pump();

    final paragraph = paragraphOf(tester, pali);
    await doubleTapAt(tester, wordCenter(paragraph, 'khetta'));
    await tester.pumpAndSettle();

    expect(lookedUp, ['khetta'],
        reason: 'double-tap on the 2nd word must look up "khetta" — '
            'got $lookedUp');
  });

  testWidgets('double-tap on the last word of a wrapped line looks up that '
      'word', (tester) async {
    // A long line forces wrapping inside the narrow column, so the tapped
    // word can be on a later visual row — the old whole-line split could
    // never hit it correctly.
    const pali =
        'evam me sutaṃ ekaṃ samayaṃ bhagavā sāvatthiyaṃ viharati jetavane '
        'anāthapiṇḍikassa ārāme ādhipateyya';
    final lookedUp = <String>[];
    await tester.pumpWidget(
      wrap(pali: pali, onWord: lookedUp.add),
    );
    await tester.pump();

    final paragraph = paragraphOf(tester, pali);
    await doubleTapAt(tester, wordCenter(paragraph, 'ādhipateyya'));
    await tester.pumpAndSettle();

    expect(lookedUp, ['ādhipateyya'],
        reason: 'double-tap on the last word must look up "ādhipateyya" — '
            'got $lookedUp');
  });

  testWidgets('double-tap on a word inside a highlighted snippet looks it up',
      (tester) async {
    // The snippet path renders text with <mark> markup around the match;
    // the word must still resolve from the rendered text, not the raw HTML.
    const pali = 'dhammaṃ khetta ādhipateyya';
    final lookedUp = <String>[];
    await tester.pumpWidget(
      wrap(
        pali: pali,
        paliSnippet: 'dhammaṃ <mark>khetta</mark> ādhipateyya',
        onWord: lookedUp.add,
      ),
    );
    await tester.pump();

    final paragraph = paragraphOf(tester, pali);
    await doubleTapAt(tester, wordCenter(paragraph, 'ādhipateyya'));
    await tester.pumpAndSettle();

    expect(lookedUp, ['ādhipateyya'],
        reason: 'double-tap in the snippet must look up the tapped word — '
            'got $lookedUp');
  });
}
