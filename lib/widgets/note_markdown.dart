import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

final noteInlineSyntaxes = <md.InlineSyntax>[_LegacyNoteBold()];

Widget noteImagePlaceholder(Uri _, String? title, String? alt) =>
    Text(alt?.isNotEmpty == true ? alt! : '［图片］');

// Previous versions of the bold button included spaces inside the markers.
// Interpret that simple case in the preview without rewriting stored notes.
class _LegacyNoteBold extends md.InlineSyntax {
  _LegacyNoteBold()
    : super(
        r'(?<!\*)\*\*((?:[ \t]+[^*\s`\\][^*\r\n`\\]*|[^*\s`\\][^*\r\n`\\]*?[ \t]+))\*\*(?!\*)',
        startCharacter: 42,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match[1]!;
    final text = content.trim();
    final start = content.length - content.trimLeft().length;
    if (start > 0) parser.addNode(md.Text(content.substring(0, start)));
    parser.addNode(md.Element.text('strong', text));
    if (start + text.length < content.length) {
      parser.addNode(md.Text(content.substring(start + text.length)));
    }
    return true;
  }
}
