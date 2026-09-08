import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/pali_script_converter.dart';
import '../../core/utils/pali_text_utils.dart';
import '../../features/reader/utils/reader_word_hit_test.dart'
    show cleanPali, wordRangeAt;
import 'pali_text.dart';
import 'nissaya_text.dart';
import '../utils/html_text_parser.dart';

/// A single line of preview content.
class PreviewLineData {
  final int paraId;
  final int lineId;
  final String pali;
  final Map<String, String> translations;

  const PreviewLineData({
    required this.paraId,
    required this.lineId,
    required this.pali,
    this.translations = const {},
  });
}

/// Renders a list of Pāli + translation lines using the same typography
/// settings as the reader (LanguageTypography, color pairs, script).
///
/// Used by [ParagraphPreviewSheet] (book-link sections and search previews).
/// Highlights the matched paragraph (or, when [highlightLineId] is given,
/// only the exact matched line) with a left border + background tint.
/// Supports optional Pāli word tap via [onPaliWordTap] (e.g. dictionary lookup).
class PreviewContent extends ConsumerWidget {
  final List<PreviewLineData> lines;

  /// Paragraph to highlight. When [highlightLineId] is null the whole
  /// paragraph is highlighted; otherwise only the matching line is.
  final int? highlightParaId;

  /// When set together with [highlightParaId], only this line of that
  /// paragraph gets the highlight (used by search previews).
  final int? highlightLineId;
  final int? firstSnippetIndex;
  final String? paliSnippet;

  /// Per-line [GlobalKey]s indexed by position in [lines]. The owning sheet
  /// uses them both to scroll the target line into view on open and to
  /// resolve the currently-visible line when the user taps an action (e.g.
  /// "open in reader" should jump to where the user stopped reading).
  final Map<int, GlobalKey>? lineKeys;

  /// Called when the user double-taps on a Pāli text (opens dictionary).
  final ValueChanged<String>? onPaliWordTap;

  const PreviewContent({
    super.key,
    required this.lines,
    this.highlightParaId,
    this.highlightLineId,
    this.firstSnippetIndex,
    this.paliSnippet,
    this.lineKeys,
    this.onPaliWordTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final settings = ref.watch(settingsProvider);
    final paliColor = settings.paliColorPair.resolve(brightness);
    final transColor = settings.translationColorPair.resolve(brightness);
    final script = settings.paliScript;
    final paliTypo = settings.typography.pali;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.asMap().entries.map((entry) {
        final index = entry.key;
        final line = entry.value;
        final isTargetPara = line.paraId == highlightParaId;
        // When [highlightLineId] is given (search previews) highlight only
        // the exact matched line; otherwise keep the paragraph-level
        // highlight used by book-link / AI-citation previews.
        final isMatch =
            isTargetPara &&
            (highlightLineId == null || line.lineId == highlightLineId);
        // The snippet (with <mark> highlights) always shows on the line the
        // caller pointed at, independent of which line is highlighted.
        final isFirstSnippetLine =
            isTargetPara && firstSnippetIndex != null && index == firstSnippetIndex;

        final isNewPara = index == 0 || line.paraId != lines[index - 1].paraId;

        return Column(
          key: lineKeys?[index],
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Paragraph gap
            if (isNewPara && index > 0) const SizedBox(height: 12),

            // Match-highlighted paragraph block
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isMatch
                    ? colors.primaryContainer.withValues(alpha: 0.25)
                    : null,
                border: isMatch
                    ? Border(left: BorderSide(color: colors.primary, width: 3))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pāli text
                  if (isFirstSnippetLine &&
                      paliSnippet != null &&
                      paliSnippet!.isNotEmpty)
                    _buildPaliSnippet(paliSnippet!, paliColor, paliTypo, script)
                  else if (line.pali.isNotEmpty)
                    _buildPaliLine(line.pali, paliColor, paliTypo, script),
                  // Translations
                  ...line.translations.entries.map((tEntry) {
                    if (tEntry.value.isEmpty) return const SizedBox.shrink();
                    // Resolve the effective typography (override or scaled
                    // default) so previews follow the global font-size
                    // controls, matching the reader.
                    final langTypo = settings.typography.typographyFor(
                      tEntry.key,
                    );
                    return _buildTranslationLine(
                      tEntry.value,
                      transColor,
                      langTypo,
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildPaliSnippet(
    String snippet,
    Color paliColor,
    LanguageTypography paliTypo,
    Script script,
  ) {
    // Convert the snippet to match the target script (preserving HTML <mark> tags)
    final converted = convertPaliToScriptPreservingHtml(snippet, script);
    final effectiveColor = paliTypo.effectiveColor(paliColor);
    final baseStyle = TextStyle(
      fontFamily: scriptFontFamily(script),
      fontSize: paliTypo.fontSize,
      height: paliTypo.lineHeight,
      fontWeight: paliTypo.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: paliTypo.italic ? FontStyle.italic : FontStyle.normal,
      decoration: paliTypo.underline
          ? TextDecoration.underline
          : TextDecoration.none,
      color: effectiveColor,
    );

    return _buildTappablePali(
      child: HtmlTextParser.richText(converted, baseStyle, maxLines: null),
    );
  }

  Widget _buildPaliLine(
    String text,
    Color paliColor,
    LanguageTypography paliTypo,
    Script script,
  ) {
    final effectiveColor = paliTypo.effectiveColor(paliColor);
    final baseStyle = TextStyle(
      fontFamily: scriptFontFamily(script),
      fontSize: paliTypo.fontSize,
      height: paliTypo.lineHeight,
      fontWeight: paliTypo.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: paliTypo.italic ? FontStyle.italic : FontStyle.normal,
      decoration: paliTypo.underline
          ? TextDecoration.underline
          : TextDecoration.none,
      color: effectiveColor,
    );

    return _buildTappablePali(
      child: PaliHtmlText(text, style: baseStyle, maxLines: null),
    );
  }

  /// Wrap Pāli content in GestureDetector for double-tap dictionary lookup.
  ///
  /// The double-tap resolves the word UNDER the pointer (hit-tested from the
  /// tap position), not the first word of the line — the line text may wrap
  /// onto multiple visual rows and may have been converted to a non-Roman
  /// script, so a plain text split cannot locate the tapped word. The
  /// [Builder] provides a context whose render subtree contains exactly this
  /// line's text paragraph, which the hit-test needs.
  Widget _buildTappablePali({required Widget child}) {
    if (onPaliWordTap == null) return child;

    return Builder(
      builder: (context) {
        Offset? doubleTapPosition;
        return GestureDetector(
          onDoubleTapDown: (details) {
            doubleTapPosition = details.globalPosition;
          },
          onDoubleTap: () {
            final pos = doubleTapPosition;
            if (pos == null) return;
            _lookupWordAtTap(context, pos);
          },
          child: child,
        );
      },
    );
  }

  /// Look up the Pāli word rendered under [globalPosition] inside [context]'s
  /// render subtree (one Pāli line).
  ///
  /// Hit-tests the subtree to find the [RenderParagraph] under the pointer,
  /// maps the tap offset to a text position, expands to the surrounding word
  /// (space/punctuation-delimited, same rules as the reader), converts it
  /// back to Roman for the dictionary, and reports it via [onPaliWordTap].
  /// Taps on whitespace/punctuation (no word there) look up nothing.
  void _lookupWordAtTap(BuildContext context, Offset globalPosition) {
    final onTap = onPaliWordTap;
    if (onTap == null) return;

    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.attached) return;

    final result = BoxHitTestResult();
    renderBox.hitTest(
      result,
      position: renderBox.globalToLocal(globalPosition),
    );

    RenderParagraph? paragraph;
    for (final entry in result.path) {
      if (entry.target is RenderParagraph) {
        paragraph = entry.target as RenderParagraph;
        break;
      }
    }
    if (paragraph == null) return;

    final localInParagraph =
        globalPosition - paragraph.localToGlobal(Offset.zero);
    final textPosition = paragraph.getPositionForOffset(localInParagraph);
    final fullText = paragraph.text.toPlainText();
    final range = wordRangeAt(fullText, textPosition.offset);
    if (range.isCollapsed) return;

    final rawWord = fullText.substring(range.start, range.end);
    // Convert from the display script (if any) back to Roman for lookup.
    final cleaned = cleanPali(convertToRomanPali(rawWord));
    if (cleaned.length < 2) return;
    onTap(cleaned);
  }

  Widget _buildTranslationLine(
    String text,
    Color transColor,
    LanguageTypography? langTypo,
  ) {
    final effectiveFallback = transColor;
    final style = langTypo != null
        ? langTypo.toTextStyle(fallbackColor: effectiveFallback)
        : TextStyle(
            fontFamily: AppTypography.translationFont,
            fontSize: 17,
            fontWeight: FontWeight.w400,
            height: 28 / 17,
            color: effectiveFallback.withValues(alpha: 0.85),
          );

    // Check for nissaya-formatted text
    if (NissayaTextParser.isNissayaFormat(text)) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: NissayaText(text: text, baseStyle: style, plainStyle: style),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: HtmlTextParser.richText(text, style, maxLines: null),
    );
  }
}
