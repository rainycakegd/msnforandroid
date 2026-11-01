// lib/widgets/emoticon_parser.dart
import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Converts text shortcuts such as `:)`, `:D` and `;)` into inline emoticon
/// images loaded from `assets/emoticons/`.
class EmoticonParser {
  EmoticonParser._();

  static final Map<String, String> _lookup = <String, String>{
    for (final entry in Emoticons.shortcuts.entries)
      entry.key.toUpperCase(): entry.value,
  };

  static final RegExp _pattern = _buildPattern();

  static RegExp _buildPattern() {
    final keys = Emoticons.shortcuts.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final endsWithAlnum = RegExp(r'[A-Za-z0-9]$');
    final parts = keys.map((key) {
      final escaped = RegExp.escape(key);
      // Avoid matching ":D" inside words like ":Dog".
      return endsWithAlnum.hasMatch(key)
          ? '$escaped(?![A-Za-z0-9])'
          : escaped;
    });
    return RegExp(parts.join('|'), caseSensitive: false);
  }

  /// Returns the asset file name for a shortcut, or null if unknown.
  static String? fileFor(String shortcut) => _lookup[shortcut.toUpperCase()];

  /// True when [text] contains at least one emoticon shortcut.
  static bool containsEmoticon(String text) => _pattern.hasMatch(text);

  /// Splits [text] into plain text spans and emoticon image spans.
  static List<InlineSpan> parse(
    String text, {
    TextStyle? style,
    double size = 22,
  }) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      final file = fileFor(token);
      if (file == null) {
        spans.add(TextSpan(text: token));
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: EmoticonImage(file: file, size: size),
            ),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }
}

/// Text widget that renders emoticon shortcuts as images.
class EmoticonText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double? emoticonSize;
  final TextAlign? textAlign;

  const EmoticonText({
    super.key,
    required this.text,
    this.style,
    this.emoticonSize,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final fontSize = baseStyle.fontSize ?? 14;
    final size = emoticonSize ?? fontSize * 1.7;

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: EmoticonParser.parse(text, style: baseStyle, size: size),
      ),
      textAlign: textAlign,
    );
  }
}

/// A single emoticon image. Falls back to a painted yellow smiley when the
/// asset file is missing, so the UI never shows a broken image.
class EmoticonImage extends StatelessWidget {
  final String file;
  final double size;

  const EmoticonImage({super.key, required this.file, this.size = 24});

  String get _mood {
    final dot = file.lastIndexOf('.');
    return dot == -1 ? file : file.substring(0, dot);
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      '${AppConstants.emoticonsDir}$file',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _SmileyPainter(_mood)),
        );
      },
    );
  }
}

/// Grid of all available emoticons. Calls [onSelected] with the shortcut text.
class EmoticonPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;
  final double itemSize;

  const EmoticonPicker({
    super.key,
    required this.onSelected,
    this.itemSize = 32,
  });

  List<MapEntry<String, String>> _uniqueEmoticons() {
    final seen = <String>{};
    final result = <MapEntry<String, String>>[];
    for (final entry in Emoticons.shortcuts.entries) {
      if (seen.add(entry.value)) result.add(entry);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final items = _uniqueEmoticons();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withOpacity(0.95),
            const Color(0xFFE6F4FF).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AeroColors.msnBlueDark.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: items.map((entry) {
          return Tooltip(
            message: entry.key,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(entry.key),
              child: Container(
                width: itemSize + 14,
                height: itemSize + 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withOpacity(0.6),
                  border: Border.all(
                    color: AeroColors.msnBlueDark.withOpacity(0.12),
                  ),
                ),
                child: EmoticonImage(file: entry.value, size: itemSize),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SmileyPainter extends CustomPainter {
  final String mood;

  const _SmileyPainter(this.mood);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    Offset p(double x, double y) => Offset(w * x, h * y);

    final body = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.45),
        radius: 1.0,
        colors: <Color>[
          Color(0xFFFFF7B0),
          AeroColors.smileyYellow,
          AeroColors.smileyYellowDark,
        ],
        stops: <double>[0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius - w * 0.03, body);
    canvas.drawCircle(
      center,
      radius - w * 0.03,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.05
        ..color = AeroColors.smileyYellowDark,
    );

    const ink = Color(0xFF3B2A00);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ink;

    final leftEye = p(0.35, 0.38);
    final rightEye = p(0.65, 0.38);

    void eyes() {
      canvas.drawCircle(leftEye, w * 0.065, fill);
      canvas.drawCircle(rightEye, w * 0.065, fill);
    }

    Path smile() => Path()
      ..moveTo(w * 0.27, h * 0.58)
      ..quadraticBezierTo(w * 0.5, h * 0.86, w * 0.73, h * 0.58);

    Path frown() => Path()
      ..moveTo(w * 0.3, h * 0.74)
      ..quadraticBezierTo(w * 0.5, h * 0.54, w * 0.7, h * 0.74);

    Path heart(Offset c, double s) {
      final path = Path()
        ..moveTo(c.dx, c.dy + s * 0.9)
        ..cubicTo(c.dx - s * 1.4, c.dy - s * 0.1, c.dx - s * 0.6,
            c.dy - s * 1.1, c.dx, c.dy - s * 0.35)
        ..cubicTo(c.dx + s * 0.6, c.dy - s * 1.1, c.dx + s * 1.4,
            c.dy - s * 0.1, c.dx, c.dy + s * 0.9)
        ..close();
      return path;
    }

    switch (mood) {
      case 'wink':
        canvas.drawCircle(leftEye, w * 0.065, fill);
        canvas.drawLine(p(0.57, 0.38), p(0.73, 0.38), line);
        canvas.drawPath(smile(), line);
        break;
      case 'grin':
        eyes();
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.24, h * 0.56)
            ..lineTo(w * 0.76, h * 0.56)
            ..quadraticBezierTo(w * 0.5, h * 1.0, w * 0.24, h * 0.56)
            ..close(),
          fill,
        );
        canvas.drawRect(
          Rect.fromLTWH(w * 0.3, h * 0.57, w * 0.4, h * 0.07),
          Paint()..color = Colors.white,
        );
        break;
      case 'sad':
        eyes();
        canvas.drawPath(frown(), line);
        break;
      case 'cry':
        eyes();
        canvas.drawPath(frown(), line);
        final tear = Paint()..color = const Color(0xFF4FA9F5);
        canvas.drawCircle(p(0.28, 0.55), w * 0.05, tear);
        canvas.drawCircle(p(0.72, 0.55), w * 0.05, tear);
        break;
      case 'tongue':
        eyes();
        canvas.drawPath(smile(), line);
        canvas.drawOval(
          Rect.fromLTWH(w * 0.5, h * 0.62, w * 0.16, h * 0.22),
          Paint()..color = const Color(0xFFFF6F91),
        );
        break;
      case 'surprised':
        eyes();
        canvas.drawOval(
          Rect.fromCenter(
            center: p(0.5, 0.72),
            width: w * 0.2,
            height: h * 0.26,
          ),
          fill,
        );
        break;
      case 'angry':
        eyes();
        canvas.drawLine(p(0.25, 0.25), p(0.43, 0.32), line);
        canvas.drawLine(p(0.75, 0.25), p(0.57, 0.32), line);
        canvas.drawPath(frown(), line);
        break;
      case 'confused':
        eyes();
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.3, h * 0.7)
            ..quadraticBezierTo(w * 0.4, h * 0.62, w * 0.5, h * 0.7)
            ..quadraticBezierTo(w * 0.6, h * 0.78, w * 0.7, h * 0.68),
          line,
        );
        break;
      case 'neutral':
        eyes();
        canvas.drawLine(p(0.32, 0.7), p(0.68, 0.7), line);
        break;
      case 'cool':
        final glass = Paint()..color = ink;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.17, h * 0.3, w * 0.30, h * 0.18),
            Radius.circular(w * 0.06),
          ),
          glass,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.53, h * 0.3, w * 0.30, h * 0.18),
            Radius.circular(w * 0.06),
          ),
          glass,
        );
        canvas.drawLine(p(0.47, 0.34), p(0.53, 0.34), line);
        canvas.drawPath(smile(), line);
        break;
      case 'embarrassed':
        eyes();
        final blush = Paint()..color = const Color(0xFFFF8A8A).withOpacity(0.7);
        canvas.drawOval(
          Rect.fromCenter(center: p(0.24, 0.55), width: w * 0.16, height: h * 0.1),
          blush,
        );
        canvas.drawOval(
          Rect.fromCenter(center: p(0.76, 0.55), width: w * 0.16, height: h * 0.1),
          blush,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.36, h * 0.66)
            ..quadraticBezierTo(w * 0.5, h * 0.78, w * 0.64, h * 0.66),
          line,
        );
        break;
      case 'heart':
        final red = Paint()..color = const Color(0xFFE53950);
        canvas.drawPath(heart(leftEye, w * 0.1), red);
        canvas.drawPath(heart(rightEye, w * 0.1), red);
        canvas.drawPath(smile(), line);
        break;
      case 'angel':
        eyes();
        canvas.drawPath(smile(), line);
        canvas.drawOval(
          Rect.fromCenter(center: p(0.5, 0.08), width: w * 0.5, height: h * 0.12),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.05
            ..color = const Color(0xFFFFE066),
        );
        break;
      case 'devil':
        eyes();
        canvas.drawPath(smile(), line);
        final horn = Paint()..color = const Color(0xFFD32F2F);
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.2, h * 0.22)
            ..lineTo(w * 0.18, h * 0.02)
            ..lineTo(w * 0.38, h * 0.12)
            ..close(),
          horn,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.8, h * 0.22)
            ..lineTo(w * 0.82, h * 0.02)
            ..lineTo(w * 0.62, h * 0.12)
            ..close(),
          horn,
        );
        break;
      case 'smile':
      default:
        eyes();
        canvas.drawPath(smile(), line);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SmileyPainter oldDelegate) =>
      oldDelegate.mood != mood;
}